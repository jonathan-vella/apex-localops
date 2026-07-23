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

<!-- Separate adjacent callouts for markdownlint. -->

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
- [Recover a cloud deployment](#recover-a-cloud-deployment)
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
export LOCALSELF_ADMIN_PASSWORD='<approved-lab-password>'
./scripts/deploy-selfhosted.sh --resource-group rg-apexlocal \
  --location swedencentral --artifact-ref <candidate-commit-sha>
```

Use an immutable pushed candidate commit SHA until the `v1.3.0-rc.1` release tag exists. The
script runs mandatory preflight before reading the password or creating the resource group,
then runs what-if and deploys the hardened storage account, network, Bastion, NAT Gateway, Log
Analytics, jumpbox, and cluster host. ARM finishes in about 15–20 minutes.

Azure Hybrid Benefit, paid deployment, and the half-day execution window are pre-authorized for
this evaluation. They are not interactive approval gates; technical preflight remains mandatory.
Sweden Central is primary. Use `--location germanywestcentral` only as the explicit capacity
fallback. Azure Local registration remains pinned to West Europe.

The cluster host then installs Hyper-V, pools its data disks into `V:`, configures the internal
and NAT-uplink switches, and **waits** for both ISOs to appear in storage. The nested router VM
(the management gateway) is built later by the in-VM automation, from the Windows Server ISO.

To preview only, with no deploy:

```bash
./scripts/deploy-selfhosted.sh --what-if-only
```

## 3. Stage the two ISOs

After accepting the Azure Local and Windows Server Evaluation terms, start unattended staging
from the repository workstation:

```bash
./scripts/stage-selfhosted-isos.sh \
  --artifact-ref <candidate-commit-sha> \
  --accept-azure-local-license-terms \
  --accept-windows-server-evaluation-terms
```

Azure Managed Run Command executes on `ApexLocal-Mgmt` as SYSTEM. It downloads the pinned Azure
Local 2607 and Windows Server 2025 Evaluation ISOs from their official Microsoft aliases,
validates final hosts, response lengths, ISO signatures, and SHA-256 hashes, then uploads both
with the jumpbox managed identity. `iso-manifest.json` is published last. No VM password,
storage key, Bastion session, or third-party script is used.

Track staging and build progress:

```bash
az vm run-command show -g rg-apexlocal --vm-name ApexLocal-Mgmt \
  --run-command-name ApexLocalIsoStaging -o table
./scripts/monitor-selfhosted.sh --resource-group rg-apexlocal
```

For manual fallback, connect to `ApexLocal-Mgmt` over Bastion and run:

```powershell
C:\ApexLocal\Get-ApexAzureLocalIso.ps1 -AcceptLicenseTerms
C:\ApexLocal\Get-ApexWindowsServerIso.ps1 -AcceptEvaluationTerms
Connect-AzAccount -Identity
C:\ApexLocal\Upload-Isos.ps1 -StorageAccountName <staging-sa> `
  -AzureLocalIsoPath C:\ISOs\AzureLocal-2607.iso `
  -WindowsServerIsoPath C:\ISOs\WindowsServer2025.iso
```

Raw `az storage blob upload` commands are unsupported because they omit the integrity manifest.

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

The release topology is fixed to three nodes, no witness, an `E64s_v6` host, and 96 GB/16 vCPU
per node. Unsupported shape parameters are intentionally not exposed. Select only the approved
infrastructure region, immutable artifact ref, cluster name, and Azure Hybrid Benefit mode through
`deploy-selfhosted.sh`.

## Tear down

```bash
./scripts/cleanup-selfhosted.sh --resource-group rg-apexlocal
```

The host, its 12 Premium disks, Bastion, and the NAT Gateway bill continuously even when the
nested VMs are off — deleting the resource group is the only way to reach $0.

## Recover a cloud deployment

Cluster-only recovery is supported only after all three nested nodes exist and their Arc machine
resources report `Connected`. Supply the same immutable artifact ref and approved lab password:

```bash
export LOCALSELF_ADMIN_PASSWORD='<approved-lab-password>'
./scripts/recover-selfhosted.sh --artifact-ref <candidate-commit-sha> \
  --resource-group rg-apexlocal --mode ValidateDeploy
```

Use `ValidateDeploy` for a failed validation or when the cloud failure stage is uncertain. Use
`DeployOnly` only when the same candidate already passed ARM Validate and then failed during ARM
Deploy. Azure Managed Run Command encrypts the password as a protected parameter; the in-VM
recovery process reconstructs credentials transiently and clears the plaintext parameter before
exit. For failures before three Arc-connected nodes, use cleanup and start a clean deployment.

See [Self-hosted troubleshooting](troubleshooting.md) for the evidence and recovery decision table.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Build stuck at `AwaitingIsos` | Confirm `AzureLocalOS.iso`, `WindowsServer.iso`, and `iso-manifest.json` are present. Re-run `Upload-Isos.ps1` if the manifest is missing or invalid. |
| Upload fails with "not authorized" | Confirm the jumpbox has **Storage Blob Data Contributor**, resolves `<account>.blob.core.windows.net` to the Blob private endpoint, and can reach TCP 443. Re-run the deploy to restore RBAC/private DNS. |
| `Failed` during cluster deploy | The in-VM identity needs **User Access Administrator** on the resource group (assigned by the template); confirm the role assignments exist. Pull logs from the `logs/` container. |
| No public internet on nested nodes | Egress is via the host NAT (`192.168.1.0/24`) → host NIC → Azure NAT Gateway. Check `Get-NetNat` on the host. |
| `az stack-hci cluster list` empty | Use this command (not `az resource list`); allow time after `ClusterDeploying`. The deploy itself takes ~2.5–3 hours. |

For failure evidence and supported recovery points, see
[Self-hosted troubleshooting](troubleshooting.md).

## Next steps

- Plan capacity and cost: [Self-hosted sizing and cost](sizing.md).
- Review the topology and RBAC model: [Self-hosted overview](overview.md).

---

[Documentation home](../README.md) · [Self-hosted overview](overview.md) · [Glossary](../glossary.md)
