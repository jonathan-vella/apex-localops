# Deploy the self-hosted profile

[Documentation home](../README.md) / Self-hosted / Quickstart

This guide deploys a nested 3-node Azure Local cluster with zero Jumpstart dependency. Both
base images come from ISOs that you stage into a storage account; the cluster host converts them
to bootable VHDXs and builds the domain controller, the nodes, and the cluster itself with the
in-repo [`ApexLocalOps`](../../artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psm1)
module.

> [!NOTE]
> New here? Read the [Self-hosted overview](overview.md) first for the topology and the RBAC
> model, and [Self-hosted sizing and cost](sizing.md) for VM sizes and cost.

> [!NOTE]
> The self-hosted profile is in **preview** and still being validated across regions and Azure
> Local builds. See [Project status](../../README.md#project-status) and the
> [roadmap](../roadmap.md).

## In this guide

- [Prerequisites](#prerequisites)
- [1. Register providers and resolve the RP object ID](#1-register-providers-and-resolve-the-rp-object-id)
- [2. Deploy the infrastructure](#2-deploy-the-infrastructure)
- [3. Stage the two ISOs](#3-stage-the-two-isos)
- [4. Watch the build](#4-watch-the-build)
- [5. Confirm success](#5-confirm-success)
- [Customization](#customization)
- [Tear down](#tear-down)
- [Troubleshooting](#troubleshooting)
- [Next steps](#next-steps)

## Prerequisites

- **Azure CLI 2.65 or later** with Bicep, and `az login` to a subscription where you are
  **Owner** (the deploy creates role assignments; Contributor alone cannot). See
  [RBAC](../glossary.md#identity-and-access).
- vCPU quota for the host family in your region (the default needs **64 vCPUs** of
  `Standard_E64s_v6` — see [Self-hosted sizing and cost](sizing.md)).
- The two ISOs (downloaded later, on the jumpbox):
  - **Azure Local OS ISO** — Azure portal → search *Azure Local* → **Get started** →
    **Download software** (license-gated; there is no anonymous URL).
  - **Windows Server 2025 ISO** — <https://www.microsoft.com/evalcenter/> (evaluation is fine).

## 1. Register providers and resolve the RP object ID

```bash
./scripts/check-providers-selfhosted.sh
```

This registers the required resource providers and prints `hciResourceProviderObjectId` (the
object ID of the Azure Local RP, app `1412d89f-b8a8-4111-b4fd-e82905cbd85d`).
`deploy-selfhosted.sh` resolves it automatically; you can also export it:

```bash
export LOCALSELF_HCI_RP_OBJECT_ID=<oid>
```

## 2. Deploy the infrastructure

```bash
./scripts/deploy-selfhosted.sh --resource-group rg-apexlocal --location swedencentral
```

The script prompts for the Windows admin password (never written to disk), runs preflight and a
what-if preview, then deploys: the hardened storage account, the network (Bastion plus NAT
Gateway, closed inbound NSG), Log Analytics, the jumpbox, and the cluster host. ARM finishes in
about 15–20 minutes.

The cluster host then installs Hyper-V, pools its data disks into `V:`, configures the internal
and NAT-uplink switches, and **waits** for both ISOs to appear in storage. The nested router VM
(the management gateway) is built later by the in-VM automation, from the Windows Server ISO.

To preview only, with no deploy:

```bash
./scripts/deploy-selfhosted.sh --what-if-only
```

## 3. Stage the two ISOs

This is the one manual step. All downloads stay inside Azure. The jumpbox is pre-provisioned
with Azure CLI, Az PowerShell, AzCopy, and `Upload-Isos.ps1` (see `STAGE-ISOS-README.txt` on its
desktop).

1. **RDP to the jumpbox over Azure Bastion** (`ApexLocal-Mgmt`, no public IP).
2. Download the **Azure Local OS ISO** (portal) and the **Windows Server 2025 ISO** onto the
   jumpbox, for example to `C:\isos\`.
3. Upload both (this uses the jumpbox managed identity — no keys):

   ```powershell
   Connect-AzAccount -Identity
   C:\ApexLocal\Upload-Isos.ps1 -StorageAccountName <staging-sa> `
       -AzureLocalIsoPath    C:\isos\AzureLocal.iso `
       -WindowsServerIsoPath C:\isos\WindowsServer2025.iso
   ```

   `<staging-sa>` is printed by `deploy-selfhosted.sh` and shown in the desktop README. The blob
   names must be `AzureLocalOS.iso` and `WindowsServer.iso` (the helper sets these by default).

## 4. Watch the build

```bash
./scripts/monitor-selfhosted.sh --resource-group rg-apexlocal
# one snapshot plus in-VM log tail:
./scripts/monitor-selfhosted.sh --once --logs -g rg-apexlocal
```

The host advances through these `ApexProgress` tag milestones:

```text
Initializing → HyperVInstalling → HyperVInstalled → NetworkConfigured →
AwaitingIsos → IsosStaged → BaseImagesConverted → RouterReady →
DomainControllerReady → NodesCreated → NodesArcConnected → ClusterValidating →
ClusterDeploying → Completed
```

The tag becomes `Failed` on error, and logs are uploaded to the storage `logs/` container.

## 5. Confirm success

Do **not** trust the progress tag alone. Confirm the cluster with the Azure Local control plane:

```bash
az stack-hci cluster list -g rg-apexlocal -o table
# expect: ProvisioningState=Succeeded, ConnectivityStatus=Connected
az stack-hci cluster list -g rg-apexlocal \
  --query "[0].{prov:provisioningState, conn:status}" -o tsv
```

## Customization

Override at deploy time without editing files:

```bash
# 2-node cluster (cloud witness) on a smaller host:
az deployment group create -g rg-apexlocal \
  -f infra/bicep/azlocal-selfhosted/main.bicep \
  -p infra/bicep/azlocal-selfhosted/main.bicepparam \
  -p clusterNodeCount=2 -p hostVmSize=Standard_E32s_v6 -p hostDataDiskCount=8
```

For a 2-node cluster, also set `witnessType=Cloud` (in
[ApexLocal-Config.psd1](../../artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1)) so the
cluster has quorum.

For reproducible builds, pin `githubBranch` to a release tag in
[main.bicepparam](../../infra/bicep/azlocal-selfhosted/main.bicepparam) so the host pulls the
in-VM scripts from that tag.

## Tear down

```bash
./scripts/cleanup-selfhosted.sh --resource-group rg-apexlocal
```

The host, its 12 Premium disks, Bastion, and the NAT Gateway bill continuously even when the
nested VMs are off — deleting the resource group is the only way to reach $0.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Build stuck at `AwaitingIsos` | Are both blobs present? `az storage blob list --account-name <sa> -c iso-images --auth-mode login -o table`. Names must be `AzureLocalOS.iso` and `WindowsServer.iso`. |
| Upload fails with "not authorized" | The deployer or jumpbox needs **Storage Blob Data** roles (a control-plane Owner role is not enough). Re-run the deploy so RBAC is reapplied; allow a few minutes for propagation. |
| `Failed` during cluster deploy | The in-VM identity needs **User Access Administrator** on the resource group (assigned by the template); confirm the role assignments exist. Pull logs from the `logs/` container. |
| No public internet on nested nodes | Egress is via the host NAT (`192.168.1.0/24`) → host NIC → Azure NAT Gateway. Check `Get-NetNat` on the host. |
| `az stack-hci cluster list` empty | Use this command (not `az resource list`); allow time after `ClusterDeploying`. The deploy itself takes ~2.5–3 hours. |

For the shared, nested-cluster build failures (witness and policy issues), see
[LocalBox troubleshooting](../localbox/troubleshooting.md).

## Next steps

- Plan capacity and cost: [Self-hosted sizing and cost](sizing.md).
- Review the topology and RBAC model: [Self-hosted overview](overview.md).

---

[Documentation home](../README.md) · [Self-hosted overview](overview.md) · [Glossary](../glossary.md)
