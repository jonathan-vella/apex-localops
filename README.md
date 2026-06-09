# apex-localops — Deploy Azure Local in an Azure VM (Jumpstart LocalBox)

Stand up a complete, nested **Azure Local** (formerly Azure Stack HCI) evaluation
environment inside a **single Azure VM** — no physical hardware. This repository is a
**self-contained**, deploy-ready packaging of the Arc Jumpstart **LocalBox** sandbox:
the Bicep templates, the in-VM cluster-build automation, and a guided deploy/monitor
experience all live here, so the build does not depend on any third-party repository at
deploy time.

> **What you get:** one `LocalBox-Client` Hyper-V host VM that nests a 2-node Azure Local
> cluster (`AzLHOST1`/`AzLHOST2`) plus a management host (`AzLMGMT`) running a domain
> controller, router, and Windows Admin Center — and an optional Windows 11 jumpbox.

## What it deploys

| Layer | Component | Role |
| --- | --- | --- |
| Azure | `LocalBox-Client` VM (`Standard_E32s_v6`) | Hyper-V host — the only large billable compute |
| Azure | 8 × 256 GB Premium SSD (P30 tier) | Storage pool for the nested VMs |
| Azure | VNet, NSG, **Bastion**, **NAT Gateway**, Key Vault, Log Analytics | Supporting infrastructure (no public IP on the VM) |
| Azure | `LocalBox-Mgmt` Windows 11 VM (`Standard_D4s_v5`) | Optional management jumpbox (Trusted Launch) |
| Nested | `AzLHOST1`, `AzLHOST2` | The two Azure Local cluster nodes |
| Nested | `AzLMGMT` | Hosts the Domain Controller, RRAS/BGP router, Windows Admin Center |

Default regions: Azure infrastructure in **`swedencentral`**, the Azure Local instance
registered in **`westeurope`** (Sweden Central is not a supported Azure Local region).
Both are overridable. Sizing rationale: [docs/sizing-guidance.md](docs/sizing-guidance.md).

## Prerequisites

- **Owner** (or Contributor + User Access Administrator) on the target subscription.
- **Azure CLI ≥ 2.65** (`az --version`) and Bicep (`az bicep upgrade`).
- **32 vCPUs** of `Standard_E32s_v6` (or `_v5`) quota in your infra region.
- A strong Windows admin password (14–123 chars; 3 of lower/upper/digit/special).
  **Avoid `$`** — it breaks the in-VM LogonScript.

## Quickstart

```bash
git clone https://github.com/jonathan-vella/apex-localops.git
cd apex-localops

az login                              # authenticate
az account set --subscription "<your-subscription>"

# 1) Register the required resource providers (idempotent; ~a few minutes).
./scripts/check-providers.sh

# 2) Preflight + what-if + deploy + auto-hand-off to the monitor.
#    Prompts for the Windows admin password (never written to disk).
./scripts/deploy.sh
```

That's it. `deploy.sh` resolves your `tenantId` and the Azure Local resource-provider id
automatically, runs preflight checks, previews changes with `what-if`, deploys, and then
launches `monitor.sh` to track the long in-VM build.

### Useful flags

```bash
./scripts/deploy.sh --what-if-only    # preview only, no deploy
./scripts/deploy.sh --no-monitor      # deploy but don't auto-launch the monitor
./scripts/deploy.sh -g rg-localbox -l swedencentral   # override RG / region
./scripts/monitor.sh --once --logs    # one status snapshot + in-VM log tail
```

## How it works (and why the monitor matters)

The ARM deployment finishes in **~18 minutes**, but that only provisions the VM. The
client VM then runs `Bootstrap.ps1` (a custom script extension) which builds the entire
nested Azure Local cluster **inside the VM for 2–4 hours** — a phase that has **no
Azure-visible deployment state**.

`scripts/monitor.sh` makes that phase observable without Bastion/RDP. It reads:

- the `DeploymentProgress` / `DeploymentStatus` **resource-group tags** the in-VM scripts
  emit at each milestone,
- the `Microsoft.AzureStackHCI/clusters` **resource** (authoritative proof the cluster
  formed), and
- with `--logs`, a live tail of `C:\LocalBox\Logs` via `az vm run-command`.

Success = the cluster resource reaches `provisioningState = Succeeded` (or the tag becomes
`Completed`). When it's done, connect to `LocalBox-Client` (or the Windows 11 jumpbox)
over **Azure Bastion** in the portal.

## Self-containment scope

The **orchestration** is fully vendored here: the Bicep templates and the entire in-VM
cluster-build tree (`artifacts/` — PowerShell, DSC, ARM JSON, config). The VM fetches
those from **this repo's** raw URLs (`templateBaseUrl`), so there is no
`microsoft/azure_arc` dependency at deploy time.

What is **intentionally not** vendored (and cannot be — these are large or Microsoft-owned
binaries fetched from their official sources at build time):

- The Azure Local / Windows Server **OS VHDX images** (multi-GB, from Microsoft blob
  storage).
- **PowerShell 7** and **Windows Admin Center** MSIs (official Microsoft download URLs).
- The desktop **wallpaper** PNG (from `Azure/arc_jumpstart_docs`).

## Reproducible deploys (pin a release)

By default the VM fetches artifacts from the **`main`** branch. For a frozen, repeatable
build, pin to a release tag — the deploy reads exactly the artifacts in that tag:

```bash
# in bicep/main.bicepparam
param githubBranch = 'v1.0.0'
```

or override at deploy time without editing files:

```bash
az deployment group create -g rg-localbox -f bicep/main.bicep \
  -p bicep/main.bicepparam -p githubBranch=v1.0.0
```

## Defaults & customization

All of these are on by default and toggleable in
[bicep/main.bicepparam](bicep/main.bicepparam):

| Feature | Default | Param |
| --- | --- | --- |
| P30 disk performance tier (8 × 256 GB) | on | `host/host.bicep` `dataDiskPerformanceTier` |
| Windows 11 management jumpbox | on | `deployManagementVm` |
| Bastion + NAT Gateway (no public IP) | on | `deployBastion` |
| Auto-build the cluster after VM setup | on | `autoDeployClusterResource` |
| Client VM size | `Standard_E32s_v6` | `vmSize` |

Identity values (`tenantId`, `spnProviderId`) and the admin password are **never stored**
in the repo — `deploy.sh` resolves the GUIDs at runtime and reads the password from the
`LOCALBOX_ADMIN_PASSWORD` environment variable.

## Cost

The `Standard_E32s_v6` host plus 8 × P30 data disks dominate the bill. With Bastion, NAT
Gateway, and the Windows 11 jumpbox enabled, expect roughly **$4,500/month at 24×7** in
Sweden Central (approximate, retail pay-as-you-go). Disks, Bastion, and NAT bill **even
when the VMs are stopped** — delete the resource group to stop all charges. Full breakdown:
[docs/sizing-guidance.md](docs/sizing-guidance.md).

## Troubleshooting

Common failure modes (including the `InvalidResourceLocation` cluster-witness issue and how
the templates prevent it) are documented in
[docs/troubleshooting.md](docs/troubleshooting.md).

## Clean up

```bash
az group delete --name rg-localbox --yes
```

## Provenance & license

This project packages and customizes the **Arc Jumpstart LocalBox** sandbox from
[`microsoft/azure_arc`](https://github.com/microsoft/azure_arc) (`azure_jumpstart_localbox`),
vendored from commit `027b9554b2534af190271bd7443d8556da745d3e`. As a derivative work it is
distributed under the **same license as upstream — Creative Commons Attribution 4.0
International (CC BY 4.0)**; see [LICENSE](LICENSE) and the credit + list of changes in
[ATTRIBUTION.md](ATTRIBUTION.md). Azure Local OS images, PowerShell, and Windows Admin
Center are downloaded from Microsoft at build time and remain subject to their own license
terms.
