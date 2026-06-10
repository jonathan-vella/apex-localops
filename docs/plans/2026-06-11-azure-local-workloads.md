# Plan — 2026-06-11: Validate deployment, then automate VM + AVD workloads on Azure Local

> Scope: the **`azlocal-js` (LocalBox)** profile in `rg-localbox`. The `azlocal-sff` profile
> is separate work and out of scope here.

## Where we are now (start-of-day state)

- **`rg-localbox` is ABSENT.** The full RG was deleted yesterday to clear an orphaned
  `jumpstart` custom location that was blocking the cluster phase (the failure surfaced as
  a Key Vault error but the root cause was the leftover custom location). A fresh
  `deploy.sh` was started but **parked at the password prompt and never proceeded** — so
  nothing is deploying.
- **Key Vault is clear**: no soft-deleted `localbox-kv-*` vaults; vault names are
  randomized per deploy (`localbox-kv-<rand5>`), so no purge/collision risk.
- **Code is current on `main`**: the image auto-discovery **regex fix** and the
  `azureLocalImageUrl` / `windowsServerImageUrl` params are committed and pushed.
- Latest Azure Local node image available = `AzLocal2604` (24H2 / build 26100.x);
  `2605` is a *solution* release, not a published image yet.

## Objectives (requested)

1. **Validate end-to-end deployment** of the 3-node LocalBox cluster.
2. **Automate Azure Local VM deployment** — 2–3 Arc VMs on the cluster.
3. **Automate AVD on Azure Local** — session hosts as Arc VMs joined to a host pool.

Objectives 2 and 3 **require a healthy cluster from Objective 1**, so the day is sequential.

---

## Phase 0 — Finish the redeploy (pre-req, ~18 min ARM + ~4–5 h in-VM build)

The cluster must exist before anything else. This is mostly wall-clock wait time, so
**start it first thing** and run validation prep while it builds.

- [ ] Confirm login + clean state:
  - `az account show` → sub `noalz`
  - `az group show -n rg-localbox` → still absent
  - `az keyvault list-deleted --query "[?starts_with(name,'localbox-kv')]" -o table` → empty
- [ ] Run `bash ./scripts/deploy.sh` (enter the `arcdemo` password directly in the terminal).
  - Preflight + what-if should show **29 resources**; confirm `y`.
- [ ] After ARM `Succeeded` (~18 min), the in-VM build self-starts (autologon → logon task).
- [ ] Watch with `bash ./scripts/monitor.sh --interval 300`.

**Exit criteria:** ARM deployment `Succeeded`; in-VM build progressing through milestones.

---

## Phase 1 — Validate end-to-end deployment

Goal: prove the whole chain works and capture the foundation resources Objectives 2 & 3
depend on. (Reminder: `az resource list` does **not** surface the cluster — use
`az stack-hci cluster list`.)

### 1a. Verification gates (run top-to-bottom)

- [ ] **Image auto-discovery actually ran** (not the fallback) — confirms yesterday's fix:
  - In-VM: `Select-String -Path C:\LocalBox\Logs\New-LocalBoxCluster.log -Pattern 'Latest Azure Local node image resolved|Using Azure Local node image'`
  - Expect `.../AzLocal2604.vhdx` (or newer if published).
- [ ] **Nested VMs running**: AzLMGMT + AzLHOST1/2/3 (via `az vm run-command` → `Get-VM`).
- [ ] **Arc nodes connected**: `az connectedmachine list -g rg-localbox -o table` → 3 machines `Connected`.
- [ ] **Cluster ARM deploys**: `az deployment group list -g rg-localbox -o table` →
  `localcluster-validate` **and** `localcluster-deploy` = `Succeeded`.
- [ ] **Cluster healthy** (authoritative):
  `az stack-hci cluster list -g rg-localbox -o table` →
  `ProvisioningState=Succeeded`, `ConnectivityStatus=Connected`.
- [ ] **In-VM tests**: RG tag `DeploymentStatus = Tests succeeded: 16 Tests failed: 0`
  (the tag is stale mid-build — only trust it once `DeploymentProgress=Completed`).
- [ ] **Connectivity**: reach `LocalBox-Client` / `LocalBox-Mgmt` via Azure Bastion (portal),
  user `arcdemo`.

### 1b. Capture the foundation for Phases 2 & 3

- [ ] **Custom location** present + its id:
  `az customlocation list -g rg-localbox --query "[].{name:name,id:id}" -o table`
  (expected name from config = `rbCustomLocationName`; previously `jumpstart`).
- [ ] **Logical network** present:
  `az stack-hci-vm network lnet list -g rg-localbox -o table`
  — `Configure-VMLogicalNetwork.ps1` creates `localbox-vm-lnet-vlan200` (the VM lnet).
  Confirm it exists, or plan to run that script as part of 2a.
- [ ] Record cluster name (`localboxcluster`), custom-location id, lnet name/id, and the
  nested AD domain (`jumpstart.local`, DC `jumpstartdc`) into session notes — these feed 2 & 3.

**Definition of done:** cluster `Succeeded`+`Connected`, 16/16 tests, Bastion access verified,
and custom-location + lnet ids captured.

---

## Phase 2 — Automate Azure Local VM deployment (2–3 Arc VMs)

Goal: a repeatable, idempotent script that stands up 2–3 Arc VMs on the cluster. Layers
directly onto the existing `stack-hci-vm` + logical-network pattern already in the repo.

### Building blocks (already proven in-repo)
- CLI: `az extension add --name stack-hci-vm` (+ `customlocation`).
- `Configure-VMLogicalNetwork.ps1` → `az stack-hci-vm network lnet create` (VLAN 200 lnet).
- Custom location id from Phase 1b.

### Tasks
- [ ] **2a. Ensure the VM logical network exists.** If Phase 1b didn't show it, run the
  in-VM `Configure-VMLogicalNetwork.ps1` (or replicate its `lnet create` from the deploy box).
- [ ] **2b. Add the Windows Server VM image from Azure Marketplace** (DECIDED: Marketplace,
  not a local VHDX). The Marketplace path has **two extra prerequisites** the VHDX path
  doesn't — do these once before `image create`:
  - Register the **`Microsoft.EdgeMarketplace`** RP on the subscription. ⚠️ This is **NOT**
    in `scripts/check-providers.sh` today — add it there too:
    `az provider register --namespace Microsoft.EdgeMarketplace`
  - Ensure the **Azure Connected Machine Resource Manager** role is assigned to the
    `Microsoft.AzureStackHCI` RP app (object id = our `spnProviderId`, `bd244008-…`) on the RG.
  Then create the image (downloads ~10 GB into the cluster — budget time, cache on V:):
  ```
  az stack-hci-vm image create -g rg-localbox --custom-location <customLocationId> \
    --name ws2025-azed --os-type Windows \
    --publisher microsoftwindowsserver --offer windowsserver \
    --sku 2025-datacenter-azure-edition   # omit --version for latest
  ```
  Windows Server SKUs (publisher `microsoftwindowsserver`, offer `windowsserver`):
  - **WS 2025 Datacenter Azure Edition**: `2025-datacenter-azure-edition` (+ `-core`, `-smalldisk`)
  - WS 2022 Datacenter Azure Edition: `2022-datacenter-azure-edition` (+ `-hotpatch`, `-core`)
  - WS 2019: `2019-datacenter-gensecond` (+ `2019-datacenter-core-g2`)
- [ ] **2c. Author `scripts/deploy-workload-vms.sh`** (deploy-box wrapper) + an in-VM
  `artifacts/PowerShell/Deploy-AzLocalVMs.ps1`, mirroring repo conventions:
  - Params: `--count` (2–3), `--vm-size`, `--image`, `--name-prefix` (e.g. `localvm`).
  - Loop `az stack-hci-vm create` with `--custom-location`, `--storage-path` (S2D CSV),
    `--network lnet`, admin creds from Key Vault, `--memory-mb`/`--processors`.
  - **Idempotent**: skip VMs that already exist; safe to re-run.
- [ ] **2d. Sizing guard.** Workload VMs consume the **nested** nodes' capacity (96 GB RAM
  each, 3 TB S2D pool). Keep 2–3 VMs small (e.g. 2 vCPU / 4–8 GB) so they fit; add a
  preflight check that sums requested RAM vs nested headroom.
- [ ] **2e. Validate**: `az stack-hci-vm list -g rg-localbox -o table` → VMs `Succeeded`/running;
  confirm guest reachable on the lnet; (optional) Arc agent `Connected` inside each VM.

**Definition of done:** one command brings up 2–3 VMs on the cluster, is idempotent, and
the VMs show `Succeeded` + are reachable. Sizing preflight prevents over-commit.

**Open decisions:** image source **DECIDED — Azure Marketplace, Windows Server**; remaining:
exact SKU (WS 2025 vs 2022 Azure Edition) + version; static IPs vs pool; domain-join to
`jumpstart.local` now (helps Phase 3) or leave workgroup.

---

## Phase 3 — Automate AVD on Azure Local

Goal: AVD session hosts running as Arc VMs on the cluster, joined to an AVD host pool.
This is the most complex objective and is **net-new** (no AVD code in the repo yet).

### Prerequisites (most satisfied by Phases 1–2)
- Healthy cluster + custom location + VM logical network (Phases 1–2).
- A **Win 11 Enterprise multi-session** image on the cluster via the **same Azure Marketplace
  flow** as Phase 2b — publisher `microsoftwindowsdesktop`, offer `windows-11`, SKU
  `win11-24h2-avd` (or offer `office-365`, SKU `win11-24h2-avd-m365` to bundle M365 apps).
  (`Microsoft.EdgeMarketplace` RP + ACM Resource Manager role from 2b already satisfy the prereqs.)
- Domain for session-host join — the nested **`jumpstart.local`** DC (`jumpstartdc`) already
  exists; decide AD-join vs Entra-join.
- AVD licensing entitlement for test users.

### Tasks
- [ ] **3a. Provision AVD control-plane (ARM/Bicep)**: host pool (pooled, `microsoft.desktopvirtualization/hostpools`),
  workspace, application group, and registration token. Add as `infra/bicep/azlocal-js/avd/`
  or a `scripts/deploy-avd.sh` wrapper.
- [ ] **3b. Create session-host Arc VMs** on the cluster (reuse Phase 2 script with the AVD
  image + sizing for desktops), 2 hosts to start.
- [ ] **3c. Install + register the AVD agent** on each session host using the host-pool
  registration token (AVD DSC extension or the Azure Local AVD session-host flow via the
  `stack-hci-vm` / desktopvirtualization integration). Domain/Entra-join per 3a decision.
- [ ] **3d. Assign a test user** to the application group; (optional) FSLogix profile share.
- [ ] **3e. Validate**: session hosts appear `Available` in the host pool; a test user can
  launch a desktop via the AVD web client.

**Definition of done:** host pool shows ≥1 `Available` session host (Arc VM on the cluster)
and a test user successfully launches a session.

**Risks / unknowns (flag early):**
- AVD-on-Azure-Local agent/registration in a **nested** sandbox is the riskiest step — may
  need the specific Azure Local AVD provisioning path rather than vanilla AVD DSC.
- Capacity: desktop session hosts are heavier than Phase 2 test VMs — recheck nested RAM
  budget; likely cap at 2 small hosts.
- Licensing/identity for test users in the isolated `jumpstart.local` domain.

---

## Suggested running order for the day

1. **First thing:** kick off Phase 0 redeploy (long pole; runs unattended ~5 h).
2. **While it builds:** scaffold Phase 2 (`Deploy-AzLocalVMs.ps1`, wrapper, config keys) and
   Phase 3 control-plane Bicep — no cluster needed to write/lint these.
3. **When cluster is `Succeeded`:** run Phase 1 validation gates; capture foundation ids.
4. **Then:** execute Phase 2 (VMs) → validate.
5. **Then:** execute Phase 3 (AVD) → validate. If time runs short, land 3a–3b and defer
   3c–3e.

## Cross-cutting

- **Cost**: cluster ~ $7,850/mo at 24×7; disks/Bastion/NAT bill even when stopped. Tear down
  with `az group delete -n rg-localbox --yes` when done testing.
- **Persistence**: any new scripts/Bicep must be committed + pushed to `main` so the VM
  fetches them at build time (artifacts are pulled from the repo's raw URLs).
- **Secrets**: never commit the `arcdemo` password, Key Vault secrets, or the SFF
  ownership voucher (`*.pem`). Keep `.gitignore` covering `*.pem`.
- **Verification gotcha**: use `az stack-hci cluster list` / `az stack-hci-vm list`, not the
  generic `az resource list`, to see Azure Local resources.

## Decisions needed before/at start

- [x] Phase 2 image source: **Azure Marketplace, Windows Server** (decided). Remaining:
  exact SKU (**WS 2025** vs 2022 Azure Edition) + version; VM **count** (2 or 3) and **size**.
- [ ] Domain strategy for workload + AVD VMs: join `jumpstart.local` vs Entra-join vs workgroup?
- [ ] Phase 3 desktop image: **Win 11 Enterprise multi-session** (`win11-24h2-avd`) — plain vs M365 (`-m365`)? Number of session hosts?
- [ ] Stretch vs must-have: is a fully launchable AVD session the bar for tomorrow, or is
  "host pool + session hosts registered" acceptable if time runs short?
