# SFF sizing and cost

[Documentation home](../README.md) / SFF / Sizing and cost

This guide covers sizing for the SFF profile, which is far lighter than the cluster profiles: it
nests one or two 16 GB / 4 vCPU ROE test VMs (set by `nestedVmCount`) rather than a multi-node
Azure Local cluster. The shipped
[main.bicepparam](../../infra/bicep/azlocal-sff/main.bicepparam) builds **two** (a pair, for
example for a 2-node Azure Local instance); set `nestedVmCount = 1` for one. To deploy, see the
[SFF quickstart](quickstart.md).

## In this guide

- [Default footprint](#default-footprint)
- [Host SKU options](#host-sku-options)
- [Nested VM count](#nested-vm-count)
- [Cost](#cost)
- [Azure Hybrid Benefit (on by default)](#azure-hybrid-benefit-on-by-default)
- [Cost guidance](#cost-guidance)
- [Comparison with the Self-hosted profile](#comparison-with-the-self-hosted-profile)

## Default footprint

| Item | Default | Notes |
| --- | --- | --- |
| Host VM | `Standard_D16s_v5` (16 vCPU / 64 GB) | Nested-virtualization capable; hosts two 16 GB / 4 vCPU guests (32 GB / 8 vCPU committed) plus host overhead. Drop to `Standard_D8s_v5` for a single guest. |
| Host data disk | 1 × 1024 GB Premium SSD (drive `V:`) | Holds the nested VHDXs (256 GB dynamic each) plus the ROE ISO/zip and transient extraction. 512 GB is enough for one guest. |
| Host OS disk | 256 GB Premium SSD | Windows Server 2025. |
| Jumpbox (optional) | Win11 `Standard_D4s_v5` | Artifact-acquisition workstation. |
| Staging storage | Standard_LRS | ROE ISO plus Configurator App MSI. |
| Key Vault | Standard | Ownership voucher. |
| Bastion | Standard | Ingress (no public IP on the VMs). |
| NAT Gateway | Standard + 1 PIP | Egress. |
| Log Analytics | pergb2018 | Host telemetry. |
| Azure Hybrid Benefit | **On by default** | `Windows_Server` on the host, `Windows_Client` on the jumpbox — drops the Windows license charge (see below). |

## Host SKU options

All are nested-virtualization capable (allowed in `main.bicep`):

| SKU | vCPU / RAM | When to use |
| --- | --- | --- |
| `Standard_D8s_v5` | 8 / 32 GB | A single ROE test VM (`nestedVmCount = 1`). |
| `Standard_E8s_v5` | 8 / 64 GB | A single guest with extra RAM headroom. |
| `Standard_D16s_v5` (shipped default) | 16 / 64 GB | **Two** ROE test VMs (`nestedVmCount = 2`). |
| `Standard_E16s_v5` | 16 / 128 GB | Two larger guests or more RAM headroom. |
| `*_v6` variants | — | Newer generation; use if quota or availability favors v6. |

## Nested VM count

`nestedVmCount` (in [main.bicepparam](../../infra/bicep/azlocal-sff/main.bicepparam)) controls
how many SFF guests the host builds inside itself, sequentially. Each guest is identical (Gen2,
TPM on, Secure Boot off, 4 vCPU, 16 GB, 256 GB VHD) and gets:

| Per-instance resource | `nestedVmCount = 1` | `nestedVmCount = 2` |
| --- | --- | --- |
| VM name | `linuxsff-vm` | `linuxsff-vm-1`, `linuxsff-vm-2` |
| Reserved IP (NAT scope) | `192.168.200.50` | `192.168.200.50`, `.51` |
| Static MAC | `00:15:5D:5F:F0:01` | `…:01`, `…:02` |
| Key Vault voucher secret | `sff-ownership-voucher` | `sff-ownership-voucher-1`, `-2` |

Size the host so `nestedVmCount × (4 vCPU, 16 GB)` fits with headroom for the host OS and
Hyper-V (the shipped `Standard_D16s_v5` leaves about 8 vCPU / 32 GB free for two guests).
Provision each guest as a separate machine in the Azure Local site, using its matching voucher
secret.

> [!NOTE]
> Guests are built **sequentially**, so a two-VM run takes roughly twice as long as one.

## Cost

Retail pay-as-you-go in the host region (`swedencentral`), priced from the
[Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
on **2026-07-31**, with **Azure Hybrid Benefit on** (the project default), so the Windows license
component is excluded.

SFF runs are bursty, so the figures are per **hour** and per **40-hour working week**. Only the
two VMs stop billing when deallocated; disks, Bastion, and NAT bill until the resource group is
deleted. Disk prices are monthly and converted at 730 h.

| Component | Billed | $/hour |
| --- | --- | --- |
| Host `Standard_D16s_v5` | while running | 0.816 |
| Jumpbox `Standard_D4s_v5` | while running | 0.204 |
| Disks (1 × P30 data, 2 × P15 OS) | until deleted | 0.318 |
| Bastion Standard | until deleted | 0.290 |
| NAT Gateway + static public IP | until deleted | 0.050 |
| **Everything running** | | **~$1.68/h** |
| **Host and jumpbox deallocated** | | **~$0.66/h** |

| Usage pattern over one week | 40 h of use |
| --- | --- |
| Deallocate host and jumpbox when not in use | **~$151** |
| Leave everything running 24×7 | ~$282 |
| Delete the resource group after each session | **~$67** |

The host VM and Bastion dominate. Dropping the optional jumpbox saves ~$0.26/h, and
`Standard_D8s_v5` with `nestedVmCount = 1` roughly halves the host line.

> [!IMPORTANT]
> As with the Self-hosted profile, deallocating leaves ~$111 of the ~$151 week billing for time
> you are not using the lab — Bastion alone is $0.29/h whether or not anything is running.
> Deleting the resource group between runs is what actually gets you to $0.

## Azure Hybrid Benefit (on by default)

AHB is enabled across the SFF profile via a single parameter, `enableAzureHybridBenefit = true`
(in [main.bicepparam](../../infra/bicep/azlocal-sff/main.bicepparam)). It applies:

- `licenseType: Windows_Server` to the **host VM** (Windows Server), and
- `licenseType: Windows_Client` to the **Windows 11 jumpbox**.

This removes the Windows license charge from both VMs (you keep paying for the base compute,
storage, and networking). It matches the Self-hosted profile, which applies AHB the same way.

> [!IMPORTANT]
> **Attestation:** enabling AHB attests that you hold the corresponding eligible licenses —
> Windows Server licenses with active Software Assurance (or qualifying subscription licenses)
> for the host, and Windows 10/11 E3/E5 or Windows VDA per-user licenses (with multi-tenant
> hosting rights) for the jumpbox. If you do not, **opt out** for license-included (PAYG)
> billing:
>
> ```bash
> # At deploy time, set the param to false (edit main.bicepparam or pass an override).
> param enableAzureHybridBenefit = false
> ```

Already deployed? `licenseType` is updatable in place, with no redeploy:

```bash
az vm update -g rg-sff-host-swc01 -n LocalSFF-Host --set licenseType=Windows_Server   # or None
az vm update -g rg-sff-host-swc01 -n LocalSFF-Mgmt --set licenseType=Windows_Client   # or None
```

Verify with: `az vm show -g rg-sff-host-swc01 -n LocalSFF-Host --query licenseType -o tsv`
→ `Windows_Server`.

## Cost guidance

- **SFF test runs are bursty.** Deallocate the host
  (`az vm deallocate -g rg-sff-host-swc01 -n LocalSFF-Host`) when idle; the scheduled-task
  watcher resumes on the next start. Compute stops billing while deallocated.
- **Disks, Bastion, and NAT bill even when the VMs are stopped.** To stop *all* charges, delete
  the resource group (`./scripts/cleanup-sff.sh`).
- **Skip the jumpbox** (`deployManagementVm=false`) and stage artifacts from Azure Cloud Shell
  instead, to save the Windows 11 VM cost — still Azure-initiated.

## Comparison with the Self-hosted profile

| | Self-hosted (3-node) | **SFF** |
| --- | --- | --- |
| Host VM | `Standard_E64s_v6` (64 / 512) | `Standard_D16s_v5` (16 / 64) |
| Data disks | 8 × 1024 GB P30 (8 TB) | 1 × 1024 GB Premium |
| Est. per 40-hour week | ~$563 | ~$151 (~1/4) |
| Nested payload | 3-node Azure Local cluster + DC + router | One or two ROE SFF test VMs (two by default) |

## Next steps

- Deploy with these settings: [SFF quickstart](quickstart.md).
- Review the topology: [SFF overview](overview.md).
- Compare with the other profiles: [Choose a profile](../choose-a-profile.md).

---

[Documentation home](../README.md) · [SFF overview](overview.md) · [Glossary](../glossary.md)
