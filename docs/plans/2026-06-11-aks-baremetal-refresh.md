# Plan — AKS on bare metal refresh, sample app, hardening, repeatable redeploy

> Created 2026-06-10 (end of day). Resumes the Azure Local Small Form Factor (SFF)
> work after a successful live deployment that reached `SffProgress=VoucherStored`
> (ownership voucher stored in Key Vault `sffkvxkez2i5n2pl2w`, secret
> `sff-ownership-voucher`). Next milestone is portal machine provisioning, then the
> AKS-on-bare-metal continuation.

## Context / where we left off

- **SFF profile** (`infra/bicep/azlocal-sff/`, `artifacts/sff/`) deployed end-to-end
  on sandbox `noalz` (subscription `00858ffc-dded-4f0f-8bbf-e17fff0d47d9`).
- Nested ROE VM `linuxsff-vm` booted: `Maintenance environment setup completed
  successfully`, `Connectivity: Online`, `eth0 192.168.200.50`,
  serial `1282-0679-5411-1074-5466-1279-70`. The 4-point gate (Gen2 + TPM +
  SecureBoot off + 4 vCPU) **passed**.
- Ownership voucher extracted over SSH/SCP (`edgeuser`/`Password1`,
  `/var/staging/export/vouchers/*/*.pem`) and stored in Key Vault (5219 bytes,
  valid RFC 8366 `OWNERSHIP VOUCHER`).
- Known transient: the host guest agent got wedged (`agentStatus=null`) from too
  many concurrent `az vm run-command` calls + nested-VM CPU load. A host VM restart
  clears it. The `bb4a243` reconnecting-serial-reader fix means a fresh run should
  auto-catch ROE success without a manual tag poke.

## Authoritative upstream references

- Create cluster (Bicep): <https://learn.microsoft.com/en-us/azure/aks/aksarc/aks-bare-metal-create-cluster-bicep>
- System requirements: <https://learn.microsoft.com/en-us/azure/aks/aksarc/aks-bare-metal-system-requirements>
- Deploy a sample application: <https://learn.microsoft.com/en-us/azure/aks/aksarc/aks-bare-metal-deploy-application>
- Template source of truth (updated 2026-06-05):
  - `Azure/aksArc` → `deploymentTemplates/aks-baremetal-bicep/cluster-create.bicep`
  - `Azure/aksArc` → `deploymentTemplates/aks-baremetal-bicep/create.example.bicepparam`
- Connect machine + **configure the site** (portal flow): <https://learn.microsoft.com/en-us/azure/azure-local/small-form-factor/small-form-factor-connect-portal?view=azloc-2605#configure-the-site>
- Arc Gateway CLI (`az arcgateway`, GA extension v2.57.0+): <https://learn.microsoft.com/en-us/cli/azure/arcgateway>
- Arc site manager (`Microsoft.Edge/sites`, preview): <https://learn.microsoft.com/en-us/azure/azure-arc/site-manager/overview>

---

## Item 1 — Refresh `aks-baremetal` profile to the current upstream template

> **Status: DONE (2026-06-11).** Template rewritten to the upstream DevicePool model
> (8 resources: DevicePool + 2 RBAC + placeholder LogicalNetwork + connectedCluster +
> provisionedClusterInstance + optional Policy/Monitoring). `edgeMachineName` replaces
> `customLocationId`; K8s version is free-form (date-suffixed); param names match upstream
> (`enableAzureRbac`, `adminGroupObjectIds`, `controlPlaneIp`). The cluster now deploys
> into the **EdgeMachine's RG** (`rg-localsff`), so `deploy-aks-baremetal.sh`,
> `resolve-aks-inputs.sh`, `connect-aks-baremetal.sh`, `deploy-all.sh`, `main.bicepparam`,
> and docs (quickstart, runbook, zero-touch) were updated; cleanup made safe (no whole-RG
> delete). Added `--admin-group` flag. `bicep build`/lint clean (4 expected BCP081
> preview-type warnings); all scripts pass `bash -n` + shellcheck.

Our `infra/bicep/aks-baremetal/main.bicep` has **drifted** and would likely fail to
deploy as-is. Realign it to the upstream **DevicePool** model.

### Gaps to fix (ours → upstream)

- **Custom location.** Ours expects a pre-existing `customLocationId`. Upstream
  **auto-creates** the custom location via a `DevicePool`. → Switch the primary
  input from `customLocationId` to **`edgeMachineName`**.
- **Resource set (upstream creates 8).** Add the four missing resources plus two
  optional extensions:
  1. `DevicePool` — `Microsoft.AzureStackHCI/devicePools@2024-11-01-preview`,
     `SystemAssigned` MSI, `devices=[edgeMachineResourceId]`, `customLocationName`.
  2. RBAC: DevicePool MSI → **Device Pool Manager**
     (`adc3c795-c41e-4a89-a478-0b321783324c`) on the DevicePool scope.
  3. RBAC: DevicePool MSI → **Azure Stack HCI Edge Machine Contributor**
     (`1a6f9009-515c-4455-b170-143e4c9ce229`) on the EdgeMachine scope.
     Role-assignment `name` must be a deterministic `guid(scope, label, roleId)`
     (not the runtime principalId) per upstream comments.
  4. **Placeholder `LogicalNetwork`** —
     `Microsoft.AzureStackHCI/logicalNetworks@2024-09-01-preview`. Required by the
     PCI webhook (`infraNetworkProfile` validation), **not** used for networking.
     Dummy-but-valid values: prefix `10.0.0.0/24`, gw `10.0.0.1`, pool
     `10.0.0.2`–`10.0.0.10`, `vmSwitchName 'PlaceholderSwitch'`, default route
     `0.0.0.0/0 → gw`. `dependsOn: devicePool`.
  5. `connectedCluster` —
     `Microsoft.Kubernetes/connectedClusters@2024-01-01`, `kind ProvisionedCluster`,
     `agentPublicKeyCertificate: ''`, `aadProfile { enableAzureRbac,
     adminGroupObjectIDs[] }`.
  6. `provisionedClusterInstance` —
     `Microsoft.HybridContainerService/provisionedClusterInstances@2024-09-01-preview`,
     name `default`, `scope: connectedCluster`, `extendedLocation` CustomLocation =
     `customLocationName`, `controlPlane.count = 1` + `hostIP = controlPlaneIp`,
     `networkProfile { podCidr 10.244.0.0/16, loadBalancerProfile.count 0 }`,
     `cloudProviderProfile.infraNetworkProfile.vnetSubnetIds = [logicalNetwork.id]`,
     **`agentPoolProfiles: []`** (empty), `linuxProfile.ssh.publicKeys`.
  7. *(optional)* Azure Policy extension —
     `Microsoft.KubernetesConfiguration/extensions@2023-05-01`
     (`microsoft.policyinsights`).
  8. *(optional)* Container Monitoring extension —
     `microsoft.azuremonitor.containers` + `logAnalyticsWorkspaceResourceID`.
- **Kubernetes version.** Upstream uses a **free-form, date-suffixed** string
  (e.g. `1.34.3-20260204`). Our `@allowed(['1.34.2','1.34.3'])` would reject it. →
  Remove `@allowed`; accept a free string with a sane default.
- **Param naming.** Upstream uses `enableAzureRbac`, `adminGroupObjectIds` (array),
  `controlPlaneIp`. → Match upstream to minimize future drift.
- **Outputs.** Match upstream: `connectedClusterId`, `provisionedClusterId`,
  `devicePoolId`, `customLocationId` (resourceId of the auto-created CL),
  `devicePoolPrincipalId`.

### Keep our automation niceties

- `ensure-admin-group.sh` (Entra group auto-create/reuse), preflight, what-if,
  `connectedk8s` extension install.
- Update `scripts/deploy-aks-baremetal.sh`: introduce `AKSBM_EDGE_MACHINE_NAME`
  (replaces `AKSBM_CUSTOM_LOCATION_ID`); add optional
  `AKSBM_LOG_ANALYTICS_WORKSPACE_ID`, `AKSBM_ENABLE_POLICY`,
  `AKSBM_ENABLE_MONITORING`.
- Update `infra/bicep/aks-baremetal/main.bicepparam` and
  `docs/aks-baremetal-quickstart.md` (and sizing notes) to match.

### Providers to verify in `scripts/check-providers-sff.sh`

`Microsoft.HybridCompute`, `Microsoft.HybridContainerService`,
`Microsoft.Kubernetes`, `Microsoft.ExtendedLocation`,
`Microsoft.KubernetesConfiguration`, `Microsoft.AzureStackHCI`. Region **eastus only**.

---

## Item 2 — Add "Deploy a sample application"

> **Status: DONE (2026-06-11).** Added `artifacts/aks/sample-app/hello-app.yaml`
> (nginx Deployment + NodePort Service, MCR image, requests/limits) and
> `scripts/deploy-aks-sample-app.sh` (starts the Arc proxy, applies the manifest,
> waits for rollout, prints NodePort + access URL; `--delete` to remove). Documented
> in the quickstart (deploy steps, single-node best practices, troubleshooting) and
> added to the zero-touch scripts table. shellcheck clean; YAML structurally validated.

Source: `aks-bare-metal-deploy-application` (updated 2026-06-05).

- **LoadBalancer is not supported in preview → use `NodePort`.**
- Vendor `artifacts/aks/sample-app/hello-app.yaml` — Deployment + NodePort Service,
  image `mcr.microsoft.com/cbl-mariner/base/nginx:1.24`, container port 80, with
  resource requests/limits (`requests cpu 100m / mem 128Mi`, `limits cpu 250m /
  mem 256Mi`).
- Add `scripts/deploy-aks-sample-app.sh`: start `az connectedk8s proxy`,
  `kubectl apply -f`, then print the NodePort + access URL
  (`http://<bare-metal-host-ip>:<nodeport>`).
- Bake in single-node best practices: set requests/limits; reserve ~2 GB RAM +
  1 CPU for the control plane; NodePort only; pull images from MCR.
- Include troubleshooting notes: `ErrImagePull` → MCR reachability/DNS/firewall;
  `Pending` → node CPU/memory pressure (`kubectl describe node`); service
  unreachable → correct NodePort + host IP + firewall; `context deadline exceeded`
  → restart `az connectedk8s proxy`.

---

## Item 3 — Automate Arc site + gateway creation (machine-provisioning bridge)

> **Status: DONE (2026-06-11).** Spike confirmed: Arc Gateway = `az arcgateway`
> (GA ext, `Microsoft.HybridCompute/gateways`); Arc site = `az site` (GA ext,
> `Microsoft.Edge/sites`, RG-scoped). The "Configure the site" Region + gateway
> binding and the voucher upload are **portal-only** in the preview (machine-
> provisioning doc 404s; no standalone CLI). Built `scripts/ensure-arc-site.sh`
> (idempotent create-or-reuse of gateway + site, `--emit`, mirrors
> `ensure-admin-group.sh`), wired it into `provision-machine.sh` (pre-creates both
> so they are *selectable* in the wizard; guided steps updated). Documented in the
> runbook + zero-touch (flow + scripts table). All scripts shellcheck + `bash -n`
> clean. The residual portal toggle is documented, not faked.

Replace the manual portal step **"Create and configure an Azure Arc site"** with
automation, so the SFF → machine-provisioning bridge is scripted (it currently sits
between `VoucherStored` and the AKS work). Source:
`small-form-factor-connect-portal#configure-the-site`.

### Portal steps being automated

- **Create site** (Basics): site name, subscription, resource group. (By default
  Azure creates a new RG with the same name as the site; an existing RG may be
  selected instead.)
- **Configure site** (Site Configuration pane): **Region = East US**,
  **Use Azure Arc Gateway = Yes**, **Arc Gateway = select existing or create new**,
  then **Save**.

### Confirmed scriptable now

- **Arc Gateway** — `az arcgateway create --name <n> -g <rg> -l eastus`
  (`arcgateway` CLI extension, GA, v2.57.0+; auto-installs on first use). Defaults:
  `--gateway-type Public`, `--allowed-features ['*']`. Backing ARM type is
  `Microsoft.HybridCompute/gateways`. Has `list`/`show`/`wait` for idempotent
  create-or-reuse and readiness gating.

### Needs a short spike (preview; connect-portal doc shows portal UX only)

- Confirm the **site resource type** used by the machine-provisioning flow.
  Candidate: `Microsoft.Edge/sites` (Arc site manager, scoped 1:1 to an RG or
  subscription; has a create quickstart). Verify whether the provisioning "site"
  is the same `Microsoft.Edge/sites` resource or a provisioning-specific construct.
- Determine where the **"Configure the site" settings live** (Region = East US,
  Use Azure Arc Gateway = Yes + the gateway binding) — which resource/property
  carries them, and whether they are settable via CLI/ARM or portal-only in
  preview. If no first-class CLI exists, capture the create call via `az rest`
  (grab the request from a portal network trace) and wrap it.

### Implementation

- Add `scripts/ensure-arc-site.sh` — **idempotent create-or-reuse** mirroring the
  `ensure-admin-group.sh` pattern: ensure the Arc Gateway exists (create if
  absent, reuse if a same-named one exists), then ensure the site exists and is
  configured (Region `eastus` + gateway = Yes). Emit the site name/ID for the
  provisioning step.
- Wire it into the SFF → provisioning bridge (after `VoucherStored`, before/at
  machine provisioning) and reference it from `docs/sff-runbook.md` and the
  zero-touch doc.
- **Fallback:** if the site configuration is portal-only in preview, script the
  gateway + site **create**, and document the single residual manual toggle rather
  than faking automation.
- Region **eastus** only (matches the AKS preview + the portal default).

---

## Item 4 — Enable Azure Hybrid Benefit on the SFF host VM

Windows **Azure Hybrid Benefit (AHB)** is **on by default project-wide** (removes
the Windows license charge; you keep paying only base compute/storage). This
matches the **LocalBox profile** (`azlocal-js`), which already applies AHB to both
its VMs — confirmed live: `LocalBox-Client` (host) = `Windows_Server`,
`LocalBox-Mgmt` (Win11) = `Windows_Client`.

### Status: IMPLEMENTED (2026-06-11) — on by default, both SFF VMs

- Single project-wide toggle `enableAzureHybridBenefit bool = true` in
  `main.bicep`, threaded to both modules; explicit `= true` in `main.bicepparam`
  (flip to `false` for license-included/PAYG on both VMs).
- `host/host.bicep` (Windows Server): `licenseType: enableAzureHybridBenefit ?
  'Windows_Server' : null`.
- `mgmt/managementVm.bicep` (Windows 11 jumpbox): `licenseType:
  enableAzureHybridBenefit ? 'Windows_Client' : null` — the gap that was missed
  initially; now matches the LocalBox convention.
- Verified: `az bicep build` clean; compiled host carries `Windows_Server`, jumpbox
  carries `Windows_Client`; no stale param references.

### Remaining (docs + validation only)

> **Docs DONE (2026-06-11):** sizing doc gained an AHB footprint row + a dedicated
> "Azure Hybrid Benefit (on by default)" section (savings, attestation, opt-out, in-
> place `az vm update` toggle, verify command); quickstart deploy section gained an
> AHB opt-out note. Only the post-deploy `licenseType` verification (Item 6) remains.

- Post-deploy assertion (Item 6): `az vm show -g rg-localsff -n LocalSFF-Host
  --query licenseType -o tsv` returns `Windows_Server`, and the jumpbox returns
  `Windows_Client`.

---

## Item 5 — Double-check everything at depth, fix all issues in code

> **Status: DONE (2026-06-11), except the optional hardening (deferred).** Results:
> - All 3 Bicep profiles `build` + `lint` clean (azlocal-js, azlocal-sff: 0 warnings;
>   aks-baremetal: 4 expected `BCP081` preview-type warnings, no Error-level — CI passes).
> - All 17 scripts pass `bash -n` + `shellcheck --severity=warning`.
> - All 8 SFF PowerShell scripts AST-parse cleanly (PSScriptAnalyzer not installed;
>   host targets PS 5.1). Re-read `Stage-SffArtifacts.ps1` — logic sound (network-before-
>   Azure, roe.zip extraction, optional non-blocking Configurator, clean VM-build handoff).
> - Secrets/GUID audit clean: only built-in role-definition GUIDs + the partner usage PID
>   (public-safe); no tenant/sub GUIDs or secrets; 9 `readEnvironmentVariable` keep inputs
>   out of source. Cleartext `ownership-voucher.pem` already removed; no `.pem` tracked.
> - Cross-check: AKS API versions + role IDs match upstream; every provider the template
>   uses is registered by `check-providers-sff.sh` (`Microsoft.Authorization` is always-on).
> - **Deferred:** the principalId-keyed role-assignment hardening (still optional).

- `az bicep build` + lint clean for all Bicep (CI: `.github/workflows/validate.yml`
  runs bicep build/lint + shellcheck at severity=warning).
- `shellcheck` all scripts, including the new ones. Remember: bash `UID` is
  readonly — use a different variable name (e.g. `OID`).
- **Re-read `artifacts/sff/PowerShell/Stage-SffArtifacts.ps1`** — it was edited
  after the last summary; re-validate the SFF PowerShell set.
- Confirm no tenant GUIDs or secrets are committed; `*.pem` is gitignored
  (`.gitignore:15`). **Delete the cleartext `ownership-voucher.pem`** from the repo
  root (recoverable from Key Vault any time).
- Cross-check provider lists, role definition IDs, and API versions against
  upstream. Confirm host PowerShell 5.1 compatibility for any PS changes.
- *(If time)* Apply the deferred hardening: key the SFF host role assignments on
  `principalId` via a submodule (`guid(scope, principalId, role)`) so a host VM
  delete + recreate no longer triggers `RoleAssignmentUpdateNotPermitted`.

---

## Item 6 — Redeploy to validate repeatability

- Full clean cycle: `scripts/cleanup-sff.sh` → `scripts/deploy-sff.sh` end-to-end on
  sandbox `noalz`. No cost concerns. Use a **dedicated** terminal.
  - **Password handling:** the sandbox admin password is typed only at the
    `deploy-sff.sh` `read -rs` prompt. **Never** persist it to a file, memory,
    shell history, or any command line.
- Confirm zero-touch SFF reaches `VoucherStored` **unattended** — validating the
  `bb4a243` reconnecting-serial-reader fix (no manual tag poke this run).
- Confirm AHB applied: `az vm show -g rg-localsff -n LocalSFF-Host --query
  licenseType -o tsv` returns `Windows_Server` (Item 4).
- Then run `ensure-arc-site.sh` (Item 3) to create/reuse the Arc site + gateway →
  provision the machine (voucher already in Key Vault) → capture `edgeMachineName`
  / custom location → run the refreshed `deploy-aks-baremetal.sh` → deploy the
  sample app → verify nginx is reachable via NodePort.
- **Operational caution:** do not hammer the host guest agent with concurrent
  `az vm run-command` calls (that wedged it today). Space them out; prefer a single
  capture over many.

---

## Definition of done

- [x] `aks-baremetal` Bicep matches the current upstream model (DevicePool +
      placeholder LogicalNetwork + edgeMachineName + free-form K8s version +
      optional Policy/Monitoring); `bicep build`/lint clean.
- [x] `deploy-aks-baremetal.sh`, `main.bicepparam`, and docs updated and shellcheck
      clean.
- [x] Sample-app manifest + `deploy-aks-sample-app.sh` added (NodePort, MCR image,
      requests/limits) and documented.
- [x] Arc site + gateway automated (`ensure-arc-site.sh`): `az arcgateway` create-
      or-reuse works; site resource type + "configure the site" surface confirmed
      (or the residual portal-only toggle documented); wired into the bridge.
- [x] Azure Hybrid Benefit on by default project-wide — host `Windows_Server` +
      Win11 jumpbox `Windows_Client` via a single `enableAzureHybridBenefit` toggle
      (implemented 2026-06-11, matches LocalBox); docs done (sizing + quickstart);
      **remaining:** post-deploy `licenseType` verification (Item 6).
- [x] Repo audited: no secrets/GUIDs committed; cleartext voucher removed.
- [ ] Clean redeploy of SFF reaches `VoucherStored` unattended; AKS cluster
      provisioned; sample app reachable via NodePort.
