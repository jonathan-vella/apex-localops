# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic-ish versioning](https://semver.org/) via git tags. Pin `githubBranch` to a tag
in `infra/bicep/azlocal-js/main.bicepparam` for reproducible deploys.

## [Unreleased]

### Added

- **Small Form Factor (SFF) evaluation profile** (`infra/bicep/azlocal-sff/`,
  `artifacts/sff/`, `scripts/*-sff.sh`). A lighter second profile: one nested-virtualization
  host (`Standard_D8s_v5`) builds the Azure Local SFF **Maintenance OS (ROE)** test VM inside
  itself — Generation 2, TPM on, Secure Boot off, ≥4 vCPU, 16 GB, 256 GB — and drives it to
  "ROE setup completed successfully". Bastion-only with NAT egress, staging storage for the
  Azure-staged ROE ISO + Configurator App, and a Key Vault for the ownership voucher.
  ~$700–900/mo (≈1/10th of the cluster profile). `check-providers-sff.sh` registers the SFF
  providers + the `Microsoft.DeviceOnboarding/AzureLocalZTP` preview feature; `deploy-sff.sh`,
  `monitor-sff.sh`, and `cleanup-sff.sh` mirror the LocalBox tooling. Docs:
  `docs/sff-quickstart.md`, `docs/sff-runbook.md`, `docs/sff-sizing.md`,
  `docs/sff-support-plan.md`.
- **AKS on bare metal (preview) downstream add-on** (`infra/bicep/aks-baremetal/`,
  `scripts/{deploy,connect}-aks-baremetal.sh`). Deploys a single-node, Arc-connected
  Kubernetes cluster directly onto a provisioned SFF machine
  (`Microsoft.Kubernetes/connectedClusters` + `Microsoft.HybridContainerService/provisionedClusterInstances`,
  Cilium, East US, zero-rated in preview). `connect-aks-baremetal.sh` wraps the
  `az connectedk8s proxy` + `kubectl` flow. Docs: `docs/aks-baremetal-quickstart.md`.
- **Zero-touch end-to-end chain** (`scripts/deploy-all.sh`). One orchestrator chains
  providers → SFF host build → ownership voucher → machine provisioning → AKS → kubectl with
  tag/resource-gated waits and stage-addressable resume (`--from/--to/--skip/--dry-run`). The
  ownership voucher is now extracted **automatically over SSH** on the host
  (`artifacts/sff/PowerShell/Get-OwnershipVoucher-Ssh.ps1`) and stored in Key Vault, removing
  the GUI Configurator step. `provision-machine.sh` auto-drives Azure machine provisioning
  when the preview CLI is present, else guides the single portal action and polls to
  `Provisioned`; `resolve-aks-inputs.sh` auto-resolves the AKS deploy inputs. The Entra admin
  group for cluster access is **created automatically** (idempotent: an existing same-named
  group is reused, and the signed-in user is added) via `ensure-admin-group.sh` — no GUID
  input required. Docs: `docs/sff-zero-touch.md`.
- **Vendored upstream SFF docs** (`docs/azure-local-sff/upstream/`) sparse-synced from
  `MicrosoftDocs/azure-stack-docs` via `.github/workflows/sync-azure-local-sff-docs.yml`
  (CC BY 4.0), plus the vendored `Azure-Samples/AzureLocal` SFF helper scripts (MIT) under
  `artifacts/sff/vendor/`.

### Changed

- `validate` CI now also builds + lints the SFF and AKS-bare-metal Bicep templates.
- README gains a profile selector, an SFF topology note, and an SFF + AKS + zero-touch
  documentation index; `ATTRIBUTION.md` credits the new vendored scripts and docs.

> The LocalBox cluster profile is unchanged; existing deploys are unaffected.

## [v1.2.1] - 2026-06-09

### Fixed

- **Headless auto-login reliability.** The in-VM build already starts itself via
  `vmAutologon = true` (default) — the VM auto-logs-in after the Hyper-V reboot and the
  cluster-build script runs with no manual sign-in. `Bootstrap.ps1` now also sets
  `DefaultDomainName` (to the local computer name) alongside the existing autologon keys;
  without it, `AutoAdminLogon` can silently fall back to the interactive logon screen and
  force a manual login. `LocalBoxLogonScript.ps1` removes `DefaultDomainName` too in its
  end-of-build cleanup.

### Changed

- Docs (README + deployment quickstart) now state explicitly that the 4–5 h build starts
  automatically (no login required) and document the `vmAutologon=false` opt-out plus the
  plaintext-password-in-registry security note.

## [v1.2.0] - 2026-06-09

### Added

- **Selectable cluster topology via `clusterNodeCount`** (2 or 3) - one parameter now drives
  the node count _and_ the witness type at deploy time, so both topologies ship from a
  single branch:
  - `clusterNodeCount = 3` (default): three nodes, **no witness**, pair with
    `Standard_E64s_v6` + `dataDiskCount = 12`.
  - `clusterNodeCount = 2`: two nodes, **cloud witness**, pair with `Standard_E32s_v6` +
    `dataDiskCount = 8`. Use only where storage shared-key access is permitted.
- `vmSize` and `dataDiskCount` are now first-class `main.bicep` parameters (the disk count
  was previously a hard-coded variable).
- `deploy.sh` preflight check: **topology coherence** - fails a 3-node-on-E32 combo (cannot
  boot) and warns on 2-node-on-E64 (over-provisioned) before the ~18 min deploy.

### Changed

- `Bootstrap.ps1` accepts `-clusterNodeCount` and exports it; `New-LocalBoxCluster.ps1` and
  `Generate-ARM-Template.ps1` trim the node list to two when requested; the generated
  `azlocal.parameters.json` `witnessType` is now substituted at runtime (`Cloud` vs
  `No Witness`) instead of being hard-coded.

> The default deployed topology is unchanged from v1.1.x (3-node, witnessless, E64).

## [v1.1.1] - 2026-06-09

Operational tooling and safety checks. No change to the deployed topology, so a `v1.1.0`
deploy and a `v1.1.1` deploy produce the same infrastructure.

### Added

- `scripts/cleanup.sh` - teardown helper that deletes the resource group (the only way to
  stop all billing) after a typed confirmation; leaves subscription-level provider
  registrations intact.
- `scripts/recover-cluster.sh` - re-runs only the in-VM cluster cloud deployment
  (validate + deploy) without rebuilding the Arc-registered nodes, via a SYSTEM scheduled
  task. Writes the same status files `monitor.sh` reads.
- `deploy.sh` preflight check #5: host-VM vCPU quota. Fails fast when the target region
  clearly lacks enough `Esv6` vCPUs for the chosen SKU (64 for the 3-node default), instead
  of discovering it after the ~18 min ARM deploy.

### Changed

- `deploy.sh` post-deploy output now points at `recover-cluster.sh` (on failure) and
  `cleanup.sh` (teardown).
- CI: pinned the `ludeeus/action-shellcheck` action to a released version instead of
  tracking the moving `master` branch.

## [v1.1.0] - 2026-06-09

### Changed

- **3-node, witnessless cluster.** The nested Azure Local cluster now runs three nodes
  (`AzLHOST1`/`AzLHOST2`/`AzLHOST3`) with `witnessType = "No Witness"`. Odd quorum needs no
  witness, which removes the cloud-witness storage account entirely - and with it any
  dependency on `allowSharedKeyAccess` (a Deny policy on shared-key storage no longer
  blocks the build).
- **Host VM `Standard_E64s_v6`** (64 vCPU / 512 GB), up from `E32s_v6`, to fit three 96 GB
  nodes plus the 28 GB management host (~316 GB committed).
- **12 × 256 GB P30 data disks** (3 TB `V:` pool), up from 8, for the larger S2D footprint.
- Docs (README, sizing guidance, quickstart, troubleshooting) and `ATTRIBUTION.md` updated
  to match; new troubleshooting section on cluster witness vs `allowSharedKeyAccess`.

### Known follow-ups

- `artifacts/azlocal.json` still creates the witness storage account + Key Vault secret
  unconditionally (`condition: None`), so the 3-node path provisions an unused witness SA.
  It is harmless (the cluster does not reference it and the witness validator does not run),
  but a future change could gate those resources on `witnessType != 'No Witness'`.

## [v1.0.0] - 2026-06-09

Initial release - a self-contained packaging of the Arc Jumpstart **LocalBox** sandbox.

### Added

- Vendored Bicep (`bicep/`) and the full in-VM cluster-build `artifacts/` tree, served from
  this repository's own raw URLs (`templateBaseUrl`) so the build has no
  `microsoft/azure_arc` runtime dependency.
- 2-node Azure Local cluster on an `E32s_v6` host with a cloud witness; 8 × 256 GB P30 data
  disks; optional Windows 11 jumpbox; Bastion + NAT Gateway (no public IP on the VM).
- `scripts/check-providers.sh`, `scripts/deploy.sh` (preflight + secure password + runtime
  identity resolution + monitor hand-off), `scripts/monitor.sh` (observes the in-VM build).
- Docs, CC BY 4.0 `LICENSE` + `ATTRIBUTION.md`, and a `validate` CI workflow (Bicep
  build/lint + ShellCheck).

[v1.2.1]: https://github.com/jonathan-vella/apex-localops/releases/tag/v1.2.1
[v1.2.0]: https://github.com/jonathan-vella/apex-localops/releases/tag/v1.2.0
[v1.1.1]: https://github.com/jonathan-vella/apex-localops/releases/tag/v1.1.1
[v1.1.0]: https://github.com/jonathan-vella/apex-localops/releases/tag/v1.1.0
[v1.0.0]: https://github.com/jonathan-vella/apex-localops/releases/tag/v1.0.0
