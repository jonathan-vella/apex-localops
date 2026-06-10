# Azure Local SFF — Sizing & Cost

The SFF profile is far lighter than the LocalBox cluster profile: it nests a **single**
16 GB / 4 vCPU ROE test VM rather than a multi-node Azure Local cluster.

## Default footprint

| Item | Default | Notes |
| --- | --- | --- |
| Host VM | `Standard_D8s_v5` (8 vCPU / 32 GB) | Nested-virtualization capable; hosts one 16 GB / 4 vCPU guest comfortably |
| Host data disk | 1 × 512 GB Premium SSD (drive `V:`) | Holds the nested VHDX (256 GB dynamic) + the ROE ISO |
| Host OS disk | 256 GB Premium SSD | Windows Server 2025 |
| Jumpbox (optional) | Win11 `Standard_D4s_v5` | Artifact-acquisition workstation |
| Staging storage | Standard_LRS | ROE ISO + Configurator App MSI |
| Key Vault | Standard | Ownership voucher |
| Bastion | Standard | Ingress (no public IP on VMs) |
| NAT Gateway | Standard + 1 PIP | Egress |
| Log Analytics | pergb2018 | Host telemetry |

## Host SKU options

All are nested-virtualization capable (`allowed` in `main.bicep`):

| SKU | vCPU / RAM | When to use |
| --- | --- | --- |
| `Standard_D8s_v5` (default) | 8 / 32 GB | Single ROE test VM |
| `Standard_E8s_v5` | 8 / 64 GB | Extra RAM headroom |
| `Standard_D16s_v5` / `Standard_E16s_v5` | 16 / 64–128 GB | Multiple/larger guests, faster builds |
| `*_v6` variants | — | Newer generation; use if quota/availability favors v6 |

## Rough monthly cost (24×7, Sweden Central, retail PAYG)

| Scenario | Approx. /month |
| --- | --- |
| Full default (host + jumpbox + Bastion + NAT + disks) | **~$700–900** |
| Host **deallocated** between runs (Bastion + NAT + disks still bill) | **~$250 floor** |
| Resource group deleted | **$0** |

These are approximate; use the Azure Pricing Calculator for an authoritative quote. The host
VM and Bastion dominate the bill.

## Cost guidance

- **SFF test runs are bursty.** Deallocate the host (`az vm deallocate -g rg-localsff -n
  LocalSFF-Host`) when idle; the scheduled-task watcher resumes on next start. Compute stops
  billing while deallocated.
- **Disks, Bastion, and NAT bill even when VMs are stopped.** To stop *all* charges, delete
  the resource group (`./scripts/cleanup-sff.sh`).
- **Skip the jumpbox** (`deployManagementVm=false`) and stage artifacts from Azure Cloud
  Shell instead to save the Win11 VM cost — still Azure-initiated.

## Comparison with the LocalBox (cluster) profile

| | LocalBox (3-node) | **SFF** |
| --- | --- | --- |
| Host VM | `Standard_E64s_v6` (64/512) | `Standard_D8s_v5` (8/32) |
| Data disks | 12 × 256 GB P30 (3 TB) | 1 × 512 GB Premium |
| Est. 24×7 | ~$7,850/mo | ~$700–900/mo (~1/10th) |
| Nested payload | 3-node Azure Local cluster + mgmt host | 1 ROE SFF test VM |
