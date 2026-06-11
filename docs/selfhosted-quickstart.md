# Self-hosted Azure Local — quickstart

Deploy a nested 3‑node Azure Local cluster with **zero Jumpstart dependency**. Both
base images come from ISOs you stage into a storage account; the cluster host
converts them to bootable VHDXs and builds the domain controller, the nodes, and
the cluster itself with the in‑repo [`ApexLocalOps`](../artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psm1) module.

> New here? Read [selfhosted-architecture.md](selfhosted-architecture.md) first for
> the topology and the RBAC model, and [selfhosted-sizing.md](selfhosted-sizing.md)
> for VM sizes and cost.

## Prerequisites

- **Azure CLI** ≥ 2.65 with Bicep, and `az login` to a subscription where you are
  **Owner** (the deploy creates role assignments; Contributor alone cannot).
- vCPU quota for the host family in your region (default **64 vCPU** of
  `Standard_E64s_v6` — see [sizing](selfhosted-sizing.md)).
- The two ISOs (downloaded later, **on the jumpbox**):
  - **Azure Local OS ISO** — Azure portal → search *Azure Local* → **Get started** →
    **Download software** (license‑gated; there is no anonymous URL).
  - **Windows Server 2025 ISO** — <https://www.microsoft.com/evalcenter/> (eval is fine).

## 1. Register providers + resolve the Azure Local RP object id

```bash
./scripts/check-providers-selfhosted.sh
```

This registers the required resource providers and prints
`hciResourceProviderObjectId` (the object id of the Azure Local RP, app
`1412d89f-b8a8-4111-b4fd-e82905cbd85d`). `deploy-selfhosted.sh` resolves it
automatically; you can also `export LOCALSELF_HCI_RP_OBJECT_ID=<oid>`.

## 2. Deploy the infrastructure

```bash
./scripts/deploy-selfhosted.sh --resource-group rg-apexlocal --location swedencentral
```

The script prompts for the Windows admin password (never written to disk), runs
preflight + a what‑if preview, then deploys: the hardened **storage account**, the
**network** (Bastion + NAT Gateway, closed inbound NSG), **Log Analytics**, the
**jumpbox**, and the **cluster host**. ARM finishes in ~15–20 min.

The cluster host then installs Hyper‑V, pools its data disks into `V:`, configures
the internal network, and **waits** for both ISOs to appear in storage.

Preview only, no deploy:

```bash
./scripts/deploy-selfhosted.sh --what-if-only
```

## 3. Stage the two ISOs (the one manual step)

All downloads stay inside Azure. The jumpbox is pre‑provisioned with Azure CLI, Az
PowerShell, AzCopy, and `Upload-Isos.ps1` (see `STAGE-ISOS-README.txt` on its desktop).

1. **RDP to the jumpbox over Bastion** (`ApexLocal-Mgmt`, no public IP).
2. Download the **Azure Local OS ISO** (portal) and the **Windows Server 2025 ISO**
   onto the jumpbox, e.g. `C:\isos\`.
3. Upload both (uses the jumpbox managed identity — no keys):

   ```powershell
   Connect-AzAccount -Identity
   C:\ApexLocal\Upload-Isos.ps1 -StorageAccountName <staging-sa> `
       -AzureLocalIsoPath    C:\isos\AzureLocal.iso `
       -WindowsServerIsoPath C:\isos\WindowsServer2025.iso
   ```

   `<staging-sa>` is printed by `deploy-selfhosted.sh` and shown in the desktop README.
   The blob names must be `AzureLocalOS.iso` and `WindowsServer.iso` (the helper sets
   these by default).

## 4. Watch the build

```bash
./scripts/monitor-selfhosted.sh --resource-group rg-apexlocal
# one snapshot + in-VM log tail:
./scripts/monitor-selfhosted.sh --once --logs -g rg-apexlocal
```

The host advances through these `ApexProgress` tag milestones:

`Initializing → HyperVInstalling → HyperVInstalled → NetworkConfigured →
AwaitingIsos → IsosStaged → BaseImagesConverted → DomainControllerReady →
NodesCreated → NodesArcConnected → ClusterValidating → ClusterDeploying → Completed`

(`Failed` on error — logs are uploaded to the storage `logs/` container.)

## 5. Confirm success (authoritative)

Do **not** trust the progress tag alone. Confirm the cluster with the Azure Local
control plane:

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

For 2‑node, also set `witnessType=Cloud` (in
[ApexLocal-Config.psd1](../artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1))
so the cluster has quorum.

**Reproducible builds:** pin `githubBranch` to a release tag in
[main.bicepparam](../infra/bicep/azlocal-selfhosted/main.bicepparam) so the host
pulls the in‑VM scripts from that tag.

## Tear down (stops all billing)

```bash
./scripts/cleanup-selfhosted.sh --resource-group rg-apexlocal
```

The host, its 12 Premium disks, Bastion, and the NAT Gateway bill continuously even
when nested VMs are off — deleting the resource group is the only way to reach $0.

## Troubleshooting

| Symptom | Check |
|---|---|
| Build stuck at `AwaitingIsos` | Both blobs present? `az storage blob list --account-name <sa> -c iso-images --auth-mode login -o table`. Names must be `AzureLocalOS.iso` + `WindowsServer.iso`. |
| Upload fails with "not authorized" | The deployer/jumpbox needs **Storage Blob Data** roles (control‑plane Owner is not enough). Re‑run the deploy so RBAC is (re)applied; allow a few minutes for propagation. |
| `Failed` during cluster deploy | The in‑VM identity needs **User Access Administrator** on the RG (assigned by the template); confirm the role assignments exist. Pull logs from the `logs/` container. |
| No public internet on nested nodes | Egress is via the host NAT (`192.168.1.0/24`) → host NIC → Azure NAT Gateway. Check `Get-NetNat` on the host. |
| `az stack-hci cluster list` empty | Use this command (not `az resource list`); allow time after `ClusterDeploying`. The deploy itself takes ~2.5–3 h. |

See [troubleshooting.md](troubleshooting.md) for the shared/Jumpstart‑profile tips.
