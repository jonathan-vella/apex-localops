# Plan: Workloads + AVD on the Azure Local cluster

Deliver **one human-run deployment script** (`scripts/deploy-workloads.sh`) + **AVD Bicep** + the in-VM PowerShell it drives. You run it manually — stage by stage or `--all` — **after** you've validated the cluster is operational. Everything is idempotent, supports `--what-if`, prints its plan, and confirms before acting (unless `--yes`). No autopilot, no self-launching background jobs.

## Goal

On the now-live `localboxcluster` (`rg-azlocal-swc01`, registered in **westeurope**, 3 nodes Connected): download 3 Marketplace images → ensure the vlan200 logical network → wait for images → deploy a domain-joined **WS2025** VM (OS + data) and a **SQL2022** VM (OS + tempdb + data) → stand up an **AVD-on-Azure-Local** host pool with 1 Win11 session host. All AD-joined to nested `jumpstart.local`.

## Foundation facts (from repo + cluster state)

- Cluster `localboxcluster` is live in `rg-azlocal-swc01`, registered in **westeurope** → custom location, images, lnet, and VMs all use `--location westeurope`.
- Custom location name = `jumpstart` (`rbCustomLocationName` in `LocalBox-Config.psd1`); id via `az customlocation show -g rg-azlocal-swc01 -n jumpstart --query id -o tsv`.
- VM switch = `"ConvergedSwitch(compute_management)"`.
- DC `jumpstartdc` @ `192.168.1.254` (domain `jumpstart.local`). Router bridges vlan200 → DC; DNS on the lnet = the DC so domain join resolves.
- VM admin user = `arcdemo`. Domain creds = `jumpstart\Administrator` + `SDNAdminPassword` (from `LocalBox-Config.psd1`).
- `Configure-VMLogicalNetwork.ps1` lacks an IP pool and references config keys (`vmIpPrefix`/`vmGateway`/`vmDNS`/`vmVLAN`) that are **missing** from `LocalBox-Config.psd1` → the new automation self-defines these in `Workloads-Config.psd1` and adds the pool.
- Repo `sqlmi*.json` = SQL **Managed Instance on Arc/AKS**, **not** this ask. SQL-on-a-Windows-VM is net-new. AVD is net-new.
- `Microsoft.EdgeMarketplace` RP is already registered.

## Phases

You invoke each stage; steps are sequential unless noted.

### Phase 0 — Prereqs *(operator creds, local/dev-container)*
- Confirm `Microsoft.EdgeMarketplace` registered (done).
- Assign **Azure Connected Machine Resource Manager** role to the HCI RP app (spn `bd244008-…`) on the RG (needs UAA/Owner).
- Confirm the VM managed identity has Contributor on the RG (from build).
- Add CLI extensions: `customlocation`, `stack-hci-vm`, `desktopvirtualization`.
- Author `Workloads-Config.psd1`.
- Script prints what it will do and asks for confirmation (unless `--yes`).

### Phase 1 — Images *(in-VM via run-command, idempotent)*
- For each of the 3 images: `az stack-hci-vm image list` → **skip if `Succeeded`/`InProgress`**, else `az stack-hci-vm image create --custom-location <cl> --location westeurope --os-type Windows --publisher <p> --offer <o> --sku <s> [--version latest]` (or the equivalent `--urn publisher:offer:sku:version`).
- Verify the offer/SKU exists in the catalog first; auto-correct if needed.
- **Long downloads (~11–30 GB+ each):** `az stack-hci-vm image create` has **no `--no-wait`** — launch the three creates as PowerShell background jobs (`Start-Job`) or three separate fire-and-forget run-command invocations, so the human's run returns and the run-command slot isn't held for the whole download. Phase 3 polls for completion.
- Image URNs (version = latest) — all three **verified present in the official curated Azure Local Marketplace catalog** (Microsoft Learn, 2026-06-12):
  - **WS2025 DC Azure Edition Core Gen2**: `microsoftwindowsserver:windowsserver:2025-datacenter-azure-edition-core`
  - **Win11 Ent multi-session 25H2 + M365 Gen2**: `microsoftwindowsdesktop:office-365:win11-25h2-avd-m365`
  - **SQL2022 Std on WS2022 Gen2**: `microsoftsqlserver:sql2022-ws2022:standard-gen2`

### Phase 2 — Logical network *(in-VM, idempotent)*
- `lnet show` → skip-or-create `localbox-vm-lnet-vlan200`:
  `--ip-allocation-method static --address-prefixes 192.168.200.0/24 --gateway 192.168.200.1 --dns-servers 192.168.1.254 --vlan 200 --ip-pool-start 192.168.200.50 --ip-pool-end 192.168.200.150 --vm-switch-name "ConvergedSwitch(compute_management)"`.

### Phase 3 — Wait
- Poll `az stack-hci-vm image show` per image until `provisioningState=Succeeded` (timeout-guarded).
- Re-runnable as its own stage so the human needn't hold the terminal during long downloads.

### Phase 4 — WS2025 VM *(depends 2 + 3)*
- Create disk (128 GB data) → NIC on lnet pool → `az stack-hci-vm create` (image, `arcdemo` creds, `--processors 4 --memory-mb 8192`, storage-path, guest management on) → attach data disk.
- Domain-join via run-command: pre-check `nslookup jumpstart.local`; `Add-Computer jumpstart.local` + restart → wait + verify domain.

### Phase 5 — SQL VM *(after 4)*
- Same flow but 16 GB RAM + 2 data disks (128 GB data + 64 GB tempdb), SQL image; domain-join.
- **Post-config** run-command: init/format both data disks, set SQL default data/log path to the data disk, `ALTER` tempdb files onto the tempdb disk, restart SQL.

### Phase 6 — AVD *(depends Win11 image + lnet)*
- **6a — Control plane (operator-run Bicep from dev container)**: `infra/bicep/azlocal-js/avd/main.bicep` deploys a **Standard-management** host pool (pooled, BreadthFirst) + application group (Desktop) + workspace to AVD metadata region **westeurope**. (⚠️ *Session host configuration* management is **not supported on Azure Local** — must be Standard.) Operator retrieves the registration token via `az desktopvirtualization hostpool` (regenerate if expired).
- **6b — Session host**: Win11 VM (4 vCPU/16 GB) via the Phase-4 path, AD-joined to `jumpstart.local`.
- **6c — Agents (two-step, order matters)**:
  1. **Azure Connected Machine agent** — VMs created outside the AVD service (our `stack-hci-vm create` path) must have the Arc Connected Machine agent installed + connected so the VM can reach **IMDS**, a required AVD endpoint. Enable VM guest management (installs it on Azure Local Arc VMs); verify `azcmagent`/IMDS reachable **before** the next step.
  2. **AVD agent** — in-guest run-command installs `RDAgent` + `RDAgentBootLoader` MSIs with the `REGISTRATIONTOKEN`. (No RDSH role needed — Win11 multi-session, not Windows Server.)
- **6d — Verify**: `az desktopvirtualization session-host list` → `Available`.
- **Fallback (lower risk):** if the scripted agent install proves fiddly, create+register the session host **with the AVD service** — the portal **"Add session hosts → Azure Local"** wizard (or an ARM template from the RDS-Templates repo) provisions the VM on Azure Local *and* installs the Arc + AVD agents in one operation. Keep 6a (control plane) in Bicep either way.

## Files

- **NEW** `scripts/deploy-workloads.sh` — the single human entry point. Flags: `--stage prereqs|images|network|wait|ws2025|sql|avd|all`, `--what-if`, `--yes`, `--resource-group` (default `rg-azlocal-swc01`), `--vm-name` (default `LocalBox-Client`). Does operator-cred work locally (Phase 0 RP/role, Phase 6a AVD Bicep + token) and delivers/triggers the in-VM orchestrator via short, one-at-a-time run-commands. Prints plan + confirms unless `--yes`. Not auto-invoked; no background self-launch.
- **NEW** `artifacts/PowerShell/workloads/Deploy-AzLocalWorkloads.ps1` — in-VM orchestrator (`az login --identity`, `-Stage`, idempotent; the cluster-side worker).
- **NEW** `artifacts/PowerShell/workloads/AzLocalWorkloads.psm1` — `Ensure-MarketplaceImage`, `Ensure-WorkloadLogicalNetwork`, `Wait-ImagesReady`, `New-WorkloadVm`, `Join-VmToDomain`, `Set-SqlStoragePaths`, `Add-AvdSessionHost`.
- **NEW** `artifacts/PowerShell/workloads/Workloads-Config.psd1` — image/VM/lnet/AVD definitions (no secrets; domain creds read from `artifacts/PowerShell/LocalBox-Config.psd1`).
- **NEW** `infra/bicep/azlocal-js/avd/main.bicep` + `main.bicepparam` — host pool (pooled/BreadthFirst) + app group (Desktop) + workspace; region westeurope.
- **REUSE**: `Configure-VMLogicalNetwork.ps1`, `Configure-AKSWorkloadCluster.ps1` (lnet + pool pattern), `LocalBox-Config.psd1` (creds/custom-location/DNS), `check-providers.sh`/`deploy.sh` (EdgeMarketplace), `recover-cluster.sh` (run-command delivery technique only — not its autopilot).

## Verification

1. **Authoring lint first**: `az bicep build` (avd) clean; `bash -n` + `shellcheck scripts/deploy-workloads.sh`; PowerShell `[Parser]::ParseFile` on `.ps1`/`.psm1`; `Import-PowerShellDataFile Workloads-Config.psd1`. `--what-if` dry-run prints intended actions with no changes.
2. **Images**: `az stack-hci-vm image list -g rg-azlocal-swc01 -o table` → 3 `Succeeded`.
3. **Lnet**: `az stack-hci-vm network lnet show -g rg-azlocal-swc01 -n localbox-vm-lnet-vlan200`.
4. **VMs**: `az stack-hci-vm list -o table` → both `Succeeded`; run-command `(Get-CimInstance Win32_ComputerSystem).Domain` = `jumpstart.local` on both.
5. **SQL**: run-command `sqlcmd -Q "SELECT @@VERSION"`; verify default data path on the data disk + tempdb files on the tempdb disk (`SELECT physical_name FROM sys.master_files`).
6. **AVD**: `az desktopvirtualization session-host list --host-pool-name <hp> -g rg-azlocal-swc01 -o table` → `Status=Available`.

## Risks

- **(TOP RISK) Nested egress for the AVD session host** — to reach `Available` the host must reach the AVD broker **and** IMDS over 443 through double-NAT (vlan200 → router → LocalBox-Client NAT → Azure). This is the single biggest threat to the success bar; validate outbound 443 + IMDS reachability from the session host early, before installing the AVD agent.
- **ACM Resource Manager role** assignment needs UAA/Owner on the RG (operator runs it; script detects + instructs if perms are missing).
- **Image downloads are large** (~11–30 GB+ each; WS2019 sample = 10.8 GB download / 130 GB disk) into the CSV → long; `Start-Job` background create + a separate `--stage wait` so the human isn't forced to hold the terminal; ensure CSV space.
- **Domain join** depends on the router + DNS from vlan200 → pre-check `nslookup jumpstart.local` + DC reachable before `Add-Computer`; clear error if unreachable.
- **AVD registration token expires** (regenerate via `az desktopvirtualization hostpool` if the session-host step runs later).
- **run-command can wedge** (seen during cluster build) → keep each run-command short, one at a time; run image creates as background jobs so the slot isn't held for the whole download.
- **Win11/WS Azure Edition activation** — session hosts on Azure Local must be licensed/activated via **Azure verification for VMs** to be genuinely usable (not strictly required to reach host-pool `Available`, but a documented post-step).

## Decisions (all locked)

- Execution: **committed, idempotent repo scripts**, run **in-VM on LocalBox-Client via `az login --identity`**; pushed to `main`.
- **Human-invoked manual execution only**; staged (`--stage`) + idempotent + `--what-if`; **no autopilot / no background self-launch**. The outcome is a deployment script + Bicep that a human runs once the cluster is validated as operational.
- Logical network: reuse `localbox-vm-lnet-vlan200` (`192.168.200.0/24`, gw `.200.1`, DNS `192.168.1.254`, VLAN 200, static) + IP pool `.200.50–.200.150`.
- Domain join: nested `jumpstart.local`, default Computers OU, creds `jumpstart\Administrator`.
- Images: 3 URNs, version = latest (verify SKU at build).
- Sizing: WS2025 4 vCPU/8 GB + 128 GB data; SQL 4 vCPU/16 GB + 128 GB data + 64 GB tempdb; AVD host 4 vCPU/16 GB.
- AVD: **Standard-management** host pool, pooled, breadth-first, 1 session host; success = session host AD-joined + agent-registered + **Available** (no end-user launch — isolated `jumpstart.local` has no Entra Connect / hybrid identity).
- Consideration 1 — SQL post-config (place data/tempdb on their disks): **included**.
- Consideration 2 — AVD control-plane region: **westeurope**.
- Consideration 3 — AVD control plane ownership: **operator-run Bicep from the dev container** (no VM MI AVD grant).

## RBAC (least-privilege; operator is likely Owner)

- **Host pool / workspace / application group** → Desktop Virtualization Contributor.
- **Generate host-pool registration key** → Desktop Virtualization Host Pool Contributor.
- **Session hosts on Azure Local** → Azure Stack HCI VM Contributor.
- **Assign users to the app group** → User Access Administrator or Owner.
- **Marketplace image download** → Azure Connected Machine Resource Manager role on the `Microsoft.AzureStackHCI` RP app, on the RG.

## Verified against Microsoft Learn (2026-06-12)

- All three image URNs exist in the official curated Azure Local Marketplace catalog (incl. `win11-25h2-avd-m365` and `sql2022-ws2022:standard-gen2`).
- `az stack-hci-vm image create` shape confirmed; **no `--no-wait`** parameter.
- AD DS join **required** for Azure Local session hosts (Entra-only not supported; hybrid join optional).
- AVD control plane lives in Azure; session hosts on Azure Local; **Standard** management only (session host configuration unsupported on Azure Local).
- Static logical network **with an IP pool** (automatic allocation) is a supported shape for the AVD add-session-host flow.
