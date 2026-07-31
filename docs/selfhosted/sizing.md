# Self-hosted sizing and cost

[Documentation home](../README.md) / Self-hosted / Sizing and cost

This guide covers sizing for the `azlocal-selfhosted` profile. The default builds a 3-node
nested Azure Local cluster plus a domain controller and a router VM inside a single Azure host
VM, with a separate small jumpbox for ISO staging. To deploy, see the
[Self-hosted quickstart](quickstart.md).

> [!NOTE]
> This page covers the self-hosted profile. For the edge profile, see
> [SFF sizing and cost](../sff/sizing.md).

## In this guide

- [Default footprint (3-node)](#default-footprint-3-node)
- [2-node alternative](#2-node-alternative)
- [Host SKU allow-list](#host-sku-allow-list)
- [Nested storage capacity](#nested-storage-capacity)
- [Quota](#quota)
- [Regions](#regions)
- [Azure Hybrid Benefit](#azure-hybrid-benefit)
- [Cost control](#cost-control)
- [Time budget](#time-budget)

## Default footprint (3-node)

| Resource | SKU / size | Notes |
| --- | --- | --- |
| Cluster host `apex-host` | `Standard_E64s_v6` (64 vCPU / 512 GB) | Hosts 3 × 96 GB nodes plus the domain controller and the router. |
| Host OS disk | 1 × Premium 1024 GB | |
| Host data disks | 8 × Premium 1024 GB (P30 tier) | Pooled into `V:` for nested storage. Sized so the nested S2D pool yields ~2.1 TB usable — see [Nested storage capacity](#nested-storage-capacity). |
| Jumpbox `apex-mgmt` | `Standard_D4s_v5` (4 vCPU / 16 GB) | ISO download and upload only. |
| Jumpbox OS disk | 1 × Premium 256 GB | Holds two multi-GB ISOs before upload. |
| Storage account | Standard_LRS | `iso-images/` (two ISOs) plus `logs/`. |
| Bastion | Standard | One per VNet. |
| NAT Gateway | Standard + static PIP | All subnet egress. |
| Log Analytics | pergb2018 | Host telemetry via Azure Monitor Agent plus a data collection rule (Windows event logs and performance); build logs also go to blob. |

**Nested VMs (inside `apex-host`):** 3 × node (96 GB / 16 vCPU each) plus 1 × domain controller
(4 GB / 4 vCPU) plus 1 × router (2 GB / 2 vCPU). Total committed nested RAM is about 294 GB,
comfortably under the host's 512 GB, leaving headroom for the host OS, the storage pool cache,
and Arc agents. The nested VMs add no Azure cost — they live on the host.

## 2-node alternative

| Override | Value |
| --- | --- |
| `hostVmSize` | `Standard_E32s_v6` (32 vCPU / 256 GB) |
| `clusterNodeCount` | `2` |
| `hostDataDiskCount` | `6` |
| `witnessType` (config) | `Cloud` (required for an even node count) |

A 2-node cluster needs a cloud witness for quorum — set `witnessType = 'Cloud'` in
[ApexLocal-Config.psd1](../../artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1). Two 96 GB
nodes plus a domain controller fit within 256 GB.

## Host SKU allow-list

`deploy-selfhosted.sh` and `main.bicep` constrain the host to high-memory,
nested-virtualization-capable SKUs:

The release host is fixed to `Standard_E64s_v6`. Each of the three nested nodes receives 96 GB
RAM, 16 vCPUs, and four 600-GB capacity disks. These values are not deployment parameters.

## Nested storage capacity

The nested cluster's usable capacity is **not** what the CSVs report. The volumes are thin
provisioned, so `Get-ClusterSharedVolume` happily shows hundreds of free GB while writes fail with
`There is not enough space on the disk` because the underlying pool is exhausted. Size the **pool**:

```text
host V:          = 8 × 1024 GB            = 8192 GB   (Simple space - Azure disks are already replicated)
nested S2D pool  = 3 nodes × 4 × 600 GB   = 7200 GB
fixed volumes    ~ Infrastructure_1 (252 GB) + performance history (24 GB), 3-way mirrored
usable           = (7200 - ~830) / 3      ≈ 2.1 TB
```

Everything is 3-way mirrored, so **every 1 GB of guest data costs 3 GB of pool**. Budget roughly:

| Consumer | Actual | Pool footprint |
| --- | --- | --- |
| Marketplace images (WS2025 smalldisk 30 GB, SQL 2022 and Win11 AVD 127 GB each) | ~300 GB | ~900 GB |
| Each VM cloned from the SQL or Win11 image (127 GB OS disk) | 127 GB | ~380 GB |
| Each VM cloned from the WS2025 smalldisk image | 30 GB | ~90 GB |
| An AKS cluster (1 control plane + 2 nodes) | ~60 GB | ~180 GB |

Prefer the WS2025 **smalldisk** image where possible: the SQL and Win11 images are 127 GB fixed
VHDs, so a single VM built from either costs more pool than four smalldisk VMs.

## Quota

The single most common blocker is host-family vCPU quota in the target region. The default needs
**64 vCPUs** of the `standardESv6Family`. Preflight checks this and
fails fast; request an increase if you are short.

## Regions

- **Infrastructure** (`location`) uses `swedencentral` as primary and
  `germanywestcentral` as the explicit fallback. This covers the host VM, jumpbox,
  Bastion, and NAT Gateway.
- **Azure Local instance** (`azureLocalInstanceLocation`) is separate and defaults to
  `canadacentral`. Keep the infrastructure and instance regions distinct. The allowed values
  are the public regions that support clusters deployed anywhere in the world: East US,
  West Europe, Australia East, Southeast Asia, India Central, Canada Central, Japan East,
  and South Central US. `uksouth`, `ukwest` and `germanywestcentral` are not on that list —
  and `germanywestcentral` additionally lacks the Arc Resource Bridge extension
  `microsoft.hybridaksoperator`, so a deployment there passes all 23 validation steps and
  then fails about three hours in.
- A region on the list can still be unavailable to *your* subscription. Preflight creates a
  real `Microsoft.HybridCompute/machines` resource there and deletes it, because creating a
  resource group succeeds even where the subscription is barred from creating resources.

## Azure Hybrid Benefit

Azure Hybrid Benefit (AHB) is **enabled by default** in this profile. Both Azure VMs — the cluster
host and the jumpbox — deploy with `licenseType = Windows_Server`, set in
[host.bicep](../../infra/bicep/azlocal-selfhosted/host/host.bicep) and
[mgmtVm.bicep](../../infra/bicep/azlocal-selfhosted/mgmt/mgmtVm.bicep).

| Question | Answer |
| --- | --- |
| What it changes | Windows Server is billed at the Hybrid Benefit rate instead of the license-included rate. Compute, storage, Bastion, and NAT Gateway charges are unaffected. |
| What it requires | Windows Server Datacenter or Standard licenses with active Software Assurance, or qualifying subscription licenses. |
| Who attests | You do. Setting `licenseType` is a self-attestation that you hold the licenses; Azure does not verify entitlement at deployment time. |
| Scope | The two Azure VMs only. The nested router, domain controller, and Azure Local nodes run evaluation media and are not licensed by AHB. |
| How to opt out | Deploy with `--disable-azure-hybrid-benefit` for license-included (PAYG) billing. |

Because every operator deploys into their own subscription, entitlement is **per deployer** — it is
not inherited from this repository or from anyone else's run. If you are unsure whether your
organization holds qualifying licenses, deploy with `--disable-azure-hybrid-benefit` and confirm
entitlement before enabling it. Reference:
[Azure Hybrid Benefit for Windows Server](https://learn.microsoft.com/azure/virtual-machines/windows/hybrid-use-benefit-licensing).

## Cost control

The host, its 8 Premium data disks, Bastion, and the NAT Gateway bill continuously — even when
the nested VMs are powered off.

- **Between runs:** deallocating the host stops compute charges, but the disks, Bastion, and NAT
  keep billing (a meaningful monthly floor).
- **To reach $0:** delete the resource group with
  [cleanup-selfhosted.sh](../../scripts/cleanup-selfhosted.sh).
- **Faster re-iteration:** the converted base VHDXs live on `V:`; a redeploy reuses them (and
  the already-staged ISOs), so you skip the multi-GB download and the DISM conversion on
  subsequent builds.

## Time budget

| Phase | Duration |
| --- | --- |
| ARM deploy (infrastructure) | ~15–20 min |
| Hyper-V install plus reboot | ~10 min |
| ISO staging (manual, on jumpbox) | Depends on download speed. |
| ISO to VHDX conversion (×2) | ~20–40 min |
| Router plus domain controller build | ~15–30 min |
| Node build | ~30–60 min |
| Cluster validate then deploy | ~2.5–3 h |

Plan for a half-day end to end on the first run; redeploys that reuse cached VHDXs are
substantially faster.

## Next steps

- Deploy with these settings: [Self-hosted quickstart](quickstart.md).
- Review the topology and RBAC model: [Self-hosted overview](overview.md).
- Compare with the other profiles: [Choose a profile](../choose-a-profile.md).

---

[Documentation home](../README.md) · [Self-hosted overview](overview.md) · [Glossary](../glossary.md)
