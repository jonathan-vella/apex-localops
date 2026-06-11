# Azure Local SFF — Sizing & Cost

The SFF profile is far lighter than the LocalBox cluster profile: it nests one or two
16 GB / 4 vCPU ROE test VMs (set by `nestedVmCount`) rather than a multi-node Azure Local
cluster. The shipped [main.bicepparam](../infra/bicep/azlocal-sff/main.bicepparam) builds
**two** (a pair, e.g. for a 2-node Azure Local instance); set `nestedVmCount = 1` for one.

## Default footprint

| Item | Default | Notes |
| --- | --- | --- |
| Host VM | `Standard_D16s_v5` (16 vCPU / 64 GB) | Nested-virtualization capable; hosts **two** 16 GB / 4 vCPU guests (32 GB / 8 vCPU committed) plus host overhead. Drop to `Standard_D8s_v5` for a single guest |
| Host data disk | 1 × 1024 GB Premium SSD (drive `V:`) | Holds the nested VHDX(es) — 256 GB dynamic each — plus the ROE ISO/zip and transient extraction. 512 GB is enough for one guest |
| Host OS disk | 256 GB Premium SSD | Windows Server 2025 |
| Jumpbox (optional) | Win11 `Standard_D4s_v5` | Artifact-acquisition workstation |
| Staging storage | Standard_LRS | ROE ISO + Configurator App MSI |
| Key Vault | Standard | Ownership voucher |
| Bastion | Standard | Ingress (no public IP on VMs) |
| NAT Gateway | Standard + 1 PIP | Egress |
| Log Analytics | pergb2018 | Host telemetry |
| Azure Hybrid Benefit | **On by default** | `Windows_Server` on the host, `Windows_Client` on the jumpbox — drops the Windows license charge (see below) |

## Host SKU options

All are nested-virtualization capable (`allowed` in `main.bicep`):

| SKU | vCPU / RAM | When to use |
| --- | --- | --- |
| `Standard_D8s_v5` | 8 / 32 GB | Single ROE test VM (`nestedVmCount = 1`) |
| `Standard_E8s_v5` | 8 / 64 GB | Single guest, extra RAM headroom |
| `Standard_D16s_v5` (shipped default) | 16 / 64 GB | **Two** ROE test VMs (`nestedVmCount = 2`) |
| `Standard_E16s_v5` | 16 / 128 GB | Two larger guests / more RAM headroom |
| `*_v6` variants | — | Newer generation; use if quota/availability favors v6 |

## Nested VM count (`nestedVmCount`)

`nestedVmCount` (in [main.bicepparam](../infra/bicep/azlocal-sff/main.bicepparam)) controls how
many SFF guests the host builds **inside itself**, sequentially. Each guest is identical
(Gen2 · TPM on · Secure Boot off · 4 vCPU · 16 GB · 256 GB VHD) and gets:

| Per-instance resource | `nestedVmCount = 1` | `nestedVmCount = 2` |
| --- | --- | --- |
| VM name | `linuxsff-vm` | `linuxsff-vm-1`, `linuxsff-vm-2` |
| Reserved IP (NAT scope) | `192.168.200.50` | `192.168.200.50`, `.51` |
| Static MAC | `00:15:5D:5F:F0:01` | `…:01`, `…:02` |
| Key Vault voucher secret | `sff-ownership-voucher` | `sff-ownership-voucher-1`, `-2` |

Size the host so `nestedVmCount × (4 vCPU, 16 GB)` fits with headroom for the host OS +
Hyper-V (the shipped `Standard_D16s_v5` leaves ~8 vCPU / 32 GB free for two guests). Provision
each guest as a separate machine in the Azure Local site using its matching voucher secret.

> Guests are built **sequentially**, so a two-VM run takes roughly twice as long as one.

## Rough monthly cost (24×7, East US, retail PAYG)

| Scenario | Approx. /month |
| --- | --- |
| Full default (host + jumpbox + Bastion + NAT + disks) | **~$700–900** |
| Host **deallocated** between runs (Bastion + NAT + disks still bill) | **~$250 floor** |
| Resource group deleted | **$0** |

These are approximate; use the Azure Pricing Calculator for an authoritative quote. The host
VM and Bastion dominate the bill.

> The cost figures above assume **Azure Hybrid Benefit (AHB) is on** (the project default),
> so they exclude the Windows license component — you pay only the base compute/storage.

## Azure Hybrid Benefit (on by default)

AHB is enabled across the SFF profile via a single param, `enableAzureHybridBenefit = true`
(in [main.bicepparam](../infra/bicep/azlocal-sff/main.bicepparam)). It applies:

- `licenseType: Windows_Server` to the **host VM** (Windows Server), and
- `licenseType: Windows_Client` to the **Windows 11 jumpbox**.

This removes the Windows license charge from both VMs (you keep paying the base compute,
storage, and networking). It matches the LocalBox profile, which applies AHB the same way.

**Attestation:** enabling AHB attests that you hold the corresponding eligible licenses:
Windows Server licenses with active Software Assurance (or qualifying subscription licenses)
for the host, and Windows 10/11 E3/E5 or Windows VDA per-user licenses (with multi-tenant
hosting rights) for the jumpbox. If you do not, **opt out** for license-included (PAYG)
billing:

```bash
# At deploy time: set the param to false (e.g. edit main.bicepparam or pass an override).
param enableAzureHybridBenefit = false
```

**Already deployed?** `licenseType` is updatable in place (no redeploy):

```bash
az vm update -g rg-azlocal-sff-eus01 -n LocalSFF-Host --set licenseType=Windows_Server   # or None
az vm update -g rg-azlocal-sff-eus01 -n LocalSFF-Mgmt --set licenseType=Windows_Client   # or None
```

Verify: `az vm show -g rg-azlocal-sff-eus01 -n LocalSFF-Host --query licenseType -o tsv` → `Windows_Server`.

## Cost guidance

- **SFF test runs are bursty.** Deallocate the host (`az vm deallocate -g rg-azlocal-sff-eus01 -n
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
