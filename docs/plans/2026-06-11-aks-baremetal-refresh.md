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

## Item 4 — Double-check everything at depth, fix all issues in code

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

## Item 5 — Redeploy to validate repeatability

- Full clean cycle: `scripts/cleanup-sff.sh` → `scripts/deploy-sff.sh` end-to-end on
  sandbox `noalz`. No cost concerns. Use a **dedicated** terminal.
  - **Password handling:** the sandbox admin password is typed only at the
    `deploy-sff.sh` `read -rs` prompt. **Never** persist it to a file, memory,
    shell history, or any command line.
- Confirm zero-touch SFF reaches `VoucherStored` **unattended** — validating the
  `bb4a243` reconnecting-serial-reader fix (no manual tag poke this run).
- Then run `ensure-arc-site.sh` (Item 3) to create/reuse the Arc site + gateway →
  provision the machine (voucher already in Key Vault) → capture `edgeMachineName`
  / custom location → run the refreshed `deploy-aks-baremetal.sh` → deploy the
  sample app → verify nginx is reachable via NodePort.
- **Operational caution:** do not hammer the host guest agent with concurrent
  `az vm run-command` calls (that wedged it today). Space them out; prefer a single
  capture over many.

---

## Definition of done

- [ ] `aks-baremetal` Bicep matches the current upstream model (DevicePool +
      placeholder LogicalNetwork + edgeMachineName + free-form K8s version +
      optional Policy/Monitoring); `bicep build`/lint clean.
- [ ] `deploy-aks-baremetal.sh`, `main.bicepparam`, and docs updated and shellcheck
      clean.
- [ ] Sample-app manifest + `deploy-aks-sample-app.sh` added (NodePort, MCR image,
      requests/limits) and documented.
- [ ] Arc site + gateway automated (`ensure-arc-site.sh`): `az arcgateway` create-
      or-reuse works; site resource type + "configure the site" surface confirmed
      (or the residual portal-only toggle documented); wired into the bridge.
- [ ] Repo audited: no secrets/GUIDs committed; cleartext voucher removed.
- [ ] Clean redeploy of SFF reaches `VoucherStored` unattended; AKS cluster
      provisioned; sample app reachable via NodePort.
