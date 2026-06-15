# Self-hosted sizing and cost

[Documentation home](../README.md) / Self-hosted / Sizing and cost

This guide covers sizing for the `azlocal-selfhosted` profile. The default builds a 3-node
nested Azure Local cluster plus a domain controller and a router VM inside a single Azure host
VM, with a separate small jumpbox for ISO staging. To deploy, see the
[Self-hosted quickstart](quickstart.md).

> [!NOTE]
> This page covers the self-hosted profile. For the Jumpstart-based profile, see
> [LocalBox sizing and cost](../localbox/sizing.md); for the edge profile, see
> [SFF sizing and cost](../sff/sizing.md).

## In this guide

- [Default footprint (3-node)](#default-footprint-3-node)
- [2-node alternative](#2-node-alternative)
- [Host SKU allow-list](#host-sku-allow-list)
- [Quota](#quota)
- [Regions](#regions)
- [Cost control](#cost-control)
- [Time budget](#time-budget)

## Default footprint (3-node)

| Resource | SKU / size | Notes |
| --- | --- | --- |
| Cluster host `apex-host` | `Standard_E64s_v6` (64 vCPU / 512 GB) | Hosts 3 × 96 GB nodes plus the domain controller and the router. |
| Host OS disk | 1 × Premium 1024 GB | |
| Host data disks | 12 × Premium 256 GB (P30 tier) | Pooled into `V:` for nested storage. |
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
| `hostDataDiskCount` | `8` |
| `witnessType` (config) | `Cloud` (required for an even node count) |

A 2-node cluster needs a cloud witness for quorum — set `witnessType = 'Cloud'` in
[ApexLocal-Config.psd1](../../artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1). Two 96 GB
nodes plus a domain controller fit within 256 GB.

## Host SKU allow-list

`deploy-selfhosted.sh` and `main.bicep` constrain the host to high-memory,
nested-virtualization-capable SKUs:

`Standard_E32s_v5`, `Standard_E48s_v5`, `Standard_E64s_v5`, `Standard_E32s_v6`,
`Standard_E48s_v6`, `Standard_E64s_v6`.

The E-series gives the RAM that nested Azure Local nodes need; v6 is preferred where available.
Adjust `nodeMemoryMB` and `nodeCpuCount` if you change the host size.

## Quota

The single most common blocker is host-family vCPU quota in the target region. The default needs
**64 vCPUs** of the `standardESv6Family` (32 for a 2-node `E32s_v6`). Preflight checks this and
fails fast; request an increase if you are short.

## Regions

- **Infrastructure** (`location`) can be most regions; the default is `swedencentral`.
- **Azure Local instance** (`azureLocalInstanceLocation`) is separate because not every region
  supports the instance — the default is `westeurope`. Keep these two distinct, matching the
  LocalBox profile.

## Cost control

The host, its 12 Premium data disks, Bastion, and the NAT Gateway bill continuously — even when
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
