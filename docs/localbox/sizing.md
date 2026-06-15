# LocalBox sizing and cost

[Documentation home](../README.md) / LocalBox / Sizing and cost

This guide explains how the LocalBox profile is sized and what it costs. All values are
verified against the vendored `artifacts/PowerShell/LocalBox-Config.psd1`; pricing is retail
pay-as-you-go in Sweden Central (USD) and approximate. To deploy, see the
[LocalBox quickstart](quickstart.md).

> [!NOTE]
> This page covers the LocalBox profile. For the Small Form Factor profile (host SKU options,
> ~$700–900/mo), see [SFF sizing and cost](../sff/sizing.md). For the clean-room profile, see
> [Self-hosted sizing and cost](../selfhosted/sizing.md).

## In this guide

- [Summary](#summary)
- [Host VM](#host-vm)
- [Disks](#disks)
- [Nested Azure Local layout](#nested-azure-local-layout)
- [Regions](#regions)
- [Cost](#cost)

## Summary

The profile offers two selectable topologies, set by `clusterNodeCount` in
[main.bicepparam](../../infra/bicep/azlocal-js/main.bicepparam):

| Profile | Nodes | Host SKU | Data disks | Witness | RAM committed |
| --- | --- | --- | --- | --- | --- |
| **3-node (default)** | 3 × 96 GB | `Standard_E64s_v6` (512 GB) | 12 × 256 GB = 3 TB | none (odd quorum) | ~316 GB |
| **2-node** | 2 × 96 GB | `Standard_E32s_v6` (256 GB) | 8 × 256 GB = 2 TB | cloud witness | ~220 GB |

The table below details the default 3-node profile:

| Layer | What you size | Value | Why |
| --- | --- | --- | --- |
| Azure VM | SKU | `Standard_E64s_v6` (64 vCPU / 512 GB) | Must fit ~316 GB of nested VM RAM. |
| Azure VM | OS disk | 1024 GB Premium SSD (P30) | Windows Server plus the VHDX image cache. |
| Azure VM | Data disks | 12 × 256 GB Premium SSD (P30 tier) = 3 TB | Pooled into `V:` for all nested VMs. |
| Nested | Azure Local nodes | `AzLHOST1` / `AzLHOST2` / `AzLHOST3` @ 96 GB | The 3-node cluster (no witness). |
| Nested | Management host | `AzLMGMT` @ 28 GB / 20 vCPU | Hosts the domain controller, router, and Windows Admin Center. |
| Nested | S2D storage | 3 nodes × 4 × 170 GB dynamic VHDX | Software-defined storage pool. |

> [!IMPORTANT]
> On the default profile you **cannot shrink the VM below E64 (512 GB RAM)**. The 3-node
> workload commits ~316 GB; E32 (256 GB) cannot boot all three nodes. To use E32, switch to
> the 2-node profile (`clusterNodeCount = 2`), which also enables a cloud witness.

> [!TIP]
> **Why 3 nodes by default?** An odd number of nodes gives the cluster odd quorum, so it needs
> no witness at all. That removes the cloud-witness storage account entirely — which is what an
> `allowSharedKeyAccess = false` storage policy would otherwise block, because the cloud
> witness requires shared-key authentication. A 2-node cluster *must* have a witness; a 3-node
> cluster must not. Choose 2-node only where shared-key storage is permitted.

## Host VM

LocalBox runs everything inside one Azure VM (`LocalBox-Client`), a Windows Server Hyper-V
host. The template allows these SKUs:

| SKU | vCPU | RAM | Notes |
| --- | --- | --- | --- |
| `Standard_E32s_v5` | 32 | 256 GB | 2-node only — too small for the 3-node default. |
| `Standard_E32s_v6` | 32 | 256 GB | 2-node only — too small for the 3-node default. |
| `Standard_E64s_v6` | 64 | 512 GB | **Default**; required for the 3-node cluster. |

RAM is the binding constraint. The four top-level nested VMs commit
`96 + 96 + 96 + 28 = 316 GB` (three 96 GB nodes plus the 28 GB management host), leaving
~196 GB for the host OS and Hyper-V — comfortable headroom on E64. E32 (256 GB) cannot hold
all four, so the default is `E64s_v6`. If you drop back to a 2-node cluster you can use
`E32s_v6`, but then a witness is mandatory.

## Disks

One OS disk plus twelve data disks, all Premium SSD (LRS):

| Disk | Size | Tier | Caching | Purpose |
| --- | --- | --- | --- | --- |
| OS (`C:`) | 1024 GB | P30 | ReadWrite | Windows Server, tooling, VHDX image cache. |
| Data 0–11 | 256 GB each | **P30 (tier override)** | None | Striped into the `V:` pool for nested VHDXs. |

> [!NOTE]
> **P30 on a 256 GB disk is a performance-tier override.** A 256 GB Premium SSD bills at the
> P15 baseline (1,100 IOPS / 125 MB/s). Setting each disk's performance tier to P30 keeps the
> 256 GB capacity but delivers 5,000 IOPS / 200 MB/s — at the full P30 rate
> (~$148.68/disk/mo). This is encoded in
> [host.bicep](../../infra/bicep/azlocal-js/host/host.bicep). To revert to the P15 baseline,
> clear `dataDiskPerformanceTier` there.

The twelve disks form a ~3 TB Storage Spaces pool (`V:`) where the nested VMs live. Each Azure
Local node presents four dynamic VHDX disks of 170 GB (`3 × 4 × 170 = 2,040 GB` of S2D
capacity) plus the node OS VHDXs and the management VMs. The disk count was raised from 8 to 12
to give the third node's S2D footprint headroom. **Do not reduce the disk count or size** — the
S2D pool and image cache assume this layout.

## Nested Azure Local layout

```mermaid
graph TB
    subgraph VM["LocalBox-Client · Standard_E64s_v6 · 64 vCPU / 512 GB"]
        subgraph HV["Hyper-V host · Windows Server"]
            H1["AzLHOST1<br/>node · 96 GB"]
            H2["AzLHOST2<br/>node · 96 GB"]
            H3["AzLHOST3<br/>node · 96 GB"]
            subgraph MGMT["AzLMGMT · 28 GB · 20 vCPU"]
                DC["Domain Controller · 2 GB"]
                RR["RRAS / BGP router · 2 GB"]
                WAC["Windows Admin Center · 10 GB"]
            end
        end
    end
```

**Diagram key:** the outer box is the Azure host VM; the inner boxes are nested VMs. The three
nodes and the management host run side by side on the Hyper-V host. The domain controller,
router, and Windows Admin Center run *inside* the management host's 28 GB allocation — their
memory is not additive.

| Nested VM | RAM | Role |
| --- | --- | --- |
| `AzLHOST1` / `AzLHOST2` / `AzLHOST3` | 96 GB each | Azure Local cluster nodes (3 → no witness). |
| `AzLMGMT` | 28 GB / 20 vCPU | Nested Hyper-V host for the management VMs. |
| → DC / router / WAC | 2 / 2 / 10 GB | Run inside `AzLMGMT`'s 28 GB (not additive). |

## Regions

LocalBox uses two region parameters; Sweden Central is valid for only one:

| Parameter | Set to | Notes |
| --- | --- | --- |
| `location` (VM, disks, VNet, …) | `swedencentral` | Your infrastructure region; needs Esv6 quota (64 vCPU). |
| `azureLocalInstanceLocation` (Arc registration) | `westeurope` | **`swedencentral` is not supported** for the Azure Local instance. |

Supported `azureLocalInstanceLocation` values: `australiaeast`, `southcentralus`, `eastus`,
`westeurope`, `southeastasia`, `canadacentral`, `japaneast`, `centralindia`. Deploying
infrastructure in `swedencentral` while registering the instance in `westeurope` is normal and
supported.

## Cost

Figures are for Sweden Central, USD, 730 hours/month.

### All-in, 24×7 (default config)

| Item | Monthly |
| --- | --- |
| VM `E64s_v6` (Windows) | ~$5,436 |
| OS disk P30 (1024 GB) | ~$149 |
| 12 × data disk P30 (256 GB, tier override) | ~$1,784 |
| Bastion (Basic) + NAT Gateway + public IPs | ~$179 |
| Windows 11 jumpbox `D4s_v5` + OS disk | ~$303 |
| **Total** | **≈ $7,850 / month** |

> [!IMPORTANT]
> **Azure Hybrid Benefit is enabled** on both VMs (`licenseType` = `Windows_Server` on the
> host, `Windows_Client` on the jumpbox), so the figures above are the base compute rate
> without the Windows licensing surcharge. AHB requires eligible licenses (Windows Server plus
> Software Assurance for the host; Windows 10/11 E3/E5 or VDA for the jumpbox). Without AHB the
> `E64s_v6` line is materially higher. Remove the `licenseType` properties if you are not
> license-entitled.

### Cost-control scenarios (client VM plus P30 disks only)

| Usage pattern | Monthly |
| --- | --- |
| 24×7 always on | ≈ $7,370 |
| 8 hrs/day × 22 workdays | ≈ $3,240 |
| Spot pricing, 24×7 | ≈ $2,940 |
| Deallocated (disks only) | ≈ $1,933 |

> [!WARNING]
> **Disks, Bastion, and NAT bill even when the VMs are deallocated.** Stopping the VM saves
> compute only; delete the resource group to stop everything. The P30 tier override adds
> ~$1,282/mo over the P15 baseline (12 disks) — drop it if your lab does not need 5,000
> IOPS/disk. Switching to a 2-node `E32s_v6` cluster roughly halves the compute cost but
> reintroduces the witness requirement.

## Next steps

- Deploy with these settings: [LocalBox quickstart](quickstart.md).
- Review the topology: [LocalBox overview](overview.md).
- Compare with the other profiles: [Choose a profile](../choose-a-profile.md).

---

[Documentation home](../README.md) · [LocalBox overview](overview.md) · [Glossary](../glossary.md)
