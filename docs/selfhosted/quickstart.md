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
- [What this lab does not validate](#what-this-lab-does-not-validate)
- [Refresh the pinned images](#refresh-the-pinned-images)
- [Tear down](#tear-down)
- [Resume a failed build at its stage](#resume-a-failed-build-at-its-stage)
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

> [!IMPORTANT]
> **The example values below are the reference lab, not requirements — change them for your
> environment.** `rg-apexlocal`, `swedencentral`, the `apexlocal` cluster name, and
> `canadacentral` are defaults; choose your own so nothing collides with another subscription:
>
> | Flag | Default | Yours |
> | --- | --- | --- |
> | `--resource-group` | `rg-apexlocal` | any new/empty resource group |
> | `--location` | `swedencentral` | `swedencentral` or `germanywestcentral` (infra region) |
> | `--cluster-name` | `apexlocal` | 3–15 chars; the Azure Local instance name |
> | `--azure-local-location` | `canadacentral` | a supported instance region (listed below) |
>
> **Deploying from a fork?** Export `GITHUB_ACCOUNT` (and `GITHUB_REPO`) before you run, so the
> in-VM bootstrap pulls runtime artifacts from your fork instead of the upstream repo:
> `export GITHUB_ACCOUNT=<you> GITHUB_REPO=<your-fork>`.

If you have already read and accepted both licence terms (step 3 explains them), run the
whole lab from one command — deployment and ISO staging back to back:

```bash
export LOCALSELF_ADMIN_PASSWORD='<approved-lab-password>'
./scripts/deploy-selfhosted.sh --resource-group rg-apexlocal \
  --location swedencentral --artifact-ref <candidate-commit-sha> \
  --accept-azure-local-license-terms \
  --accept-windows-server-evaluation-terms
```

To review the licence terms first, omit the two `--accept-*` flags and stage the ISOs
yourself in step 3:

```bash
export LOCALSELF_ADMIN_PASSWORD='<approved-lab-password>'
./scripts/deploy-selfhosted.sh --resource-group rg-apexlocal \
  --location swedencentral --artifact-ref <candidate-commit-sha>
```

Use an immutable pushed candidate commit SHA until the `v1.3.0-rc.1` release tag exists. The
script runs mandatory preflight before reading the password or creating the resource group,
then runs what-if and deploys the hardened storage account, network, Bastion, NAT Gateway, Log
Analytics, jumpbox, and cluster host. ARM finishes in about 15–20 minutes.

**Azure Hybrid Benefit is enabled by default.** Both Azure VMs deploy with
`licenseType = Windows_Server`, billing Windows Server at the Hybrid Benefit rate instead of the
license-included rate. Enabling it self-attests that you hold qualifying Windows Server licenses —
read [Azure Hybrid Benefit](sizing.md#azure-hybrid-benefit) before you deploy. If you do not hold
them, rerun with `--disable-azure-hybrid-benefit` for license-included (PAYG) billing.

The deployment does not pause for cost or licensing confirmation; technical preflight remains
mandatory. Sweden Central is primary. Use `--location germanywestcentral` only as the explicit
capacity fallback.

The **Azure Local instance region is separate** from the infrastructure region and supports far
fewer locations. It defaults to Canada Central and is set with `--azure-local-location`. The
allowed values are the public regions that support clusters deployed anywhere in the world:
`australiaeast`, `canadacentral`, `centralindia`, `eastus`, `japaneast`, `southcentralus`,
`southeastasia`, `westeurope`.

A region on that list can still be closed to *your* subscription. Preflight creates a real
`Microsoft.HybridCompute/machines` resource in the chosen region and deletes it again, because
creating a resource group succeeds even where the subscription is barred from creating
resources — and Arc onboarding would otherwise fail about ninety minutes into the build with
"The selected region is currently not accepting new customers", which the agent reports as a
credentials problem rather than a region one.

The cluster host then installs Hyper-V, pools its data disks into `V:`, configures the internal
and NAT-uplink switches, and **waits** for both ISOs to appear in storage. The nested router VM
(the management gateway) is built later by the in-VM automation, from the Windows Server ISO.

To preview only, with no deploy:

```bash
./scripts/deploy-selfhosted.sh --what-if-only
```

## 3. Stage the two ISOs

Skip this step if you passed both `--accept-*` flags in step 2 — staging already ran.

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
# expect: Succeeded, then Connected or ConnectedRecently (both are healthy).
```

## Customization

The release topology is fixed to three nodes, no witness, an `E64s_v6` host, and 96 GB/16 vCPU
per node. Unsupported shape parameters are intentionally not exposed. Select only the approved
infrastructure region, immutable artifact ref, cluster name, and
[Azure Hybrid Benefit](sizing.md#azure-hybrid-benefit) mode through `deploy-selfhosted.sh`.

## What this lab does not validate

The build runs Microsoft's Environment Checker before deploying, and a critical finding stops
the build. Four findings are waived because they cannot pass on nested hardware, listed by
exact test id in
[ApexLocal-Config.psd1](../../artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1):

| Waived test | Why it cannot pass here |
| --- | --- |
| `AzStackHci_Hardware_MemoryProperties` | A nested guest exposes no physical DIMM inventory. |
| `AzStackHci_Hardware_PhysicalDisk` | Virtual disks are not vendor-qualified physical drives. |
| `AzStackHci_Hardware_Test_NetAdapter` | Synthetic adapters lack the hardware attributes read. |
| `AzStackHci_ExternalActiveDirectory_..._ExecutingAsDeploymentUser` | Readiness runs on the workgroup host as SYSTEM, never as the domain LCM account. |

This means the lab proves the **deployment workflow**, not hardware suitability. On real
qualified hardware all four are expected to pass and must not be waived. The list is exact test
ids with no wildcards, so any finding outside it still stops the build.

## Refresh the pinned images

Both ISO pins are perishable. The Azure Local release alias
(`https://aka.ms/hcireleaseimage/<YYMM>`) is superseded every few months, and the Windows Server
2025 download is a **180-day evaluation** build that is periodically rolled. Preflight resolves
both aliases before creating any resource, so a dead pin costs nothing rather than being
discovered mid-build.

If preflight reports that the **Azure Local** alias no longer resolves, pass a current release:

```bash
./scripts/deploy-selfhosted.sh --azure-local-release-code 2610 ...
```

If preflight reports that the **Windows Server** alias no longer resolves, the evaluation
fwlink has rolled. Update `WINDOWS_SERVER_ISO_ALIAS` in
[scripts/deploy-selfhosted.sh](../../scripts/deploy-selfhosted.sh) and `$sourceAlias` in
[Get-ApexWindowsServerIso.ps1](../../artifacts/selfhosted/PowerShell/Get-ApexWindowsServerIso.ps1)
to the current Windows Server 2025 evaluation link, keeping the approved download host unchanged.

Both downloaders verify the resolved host, response length, ISO signature, and SHA-256 before
anything is uploaded, so a changed pin cannot silently substitute an untrusted image.

## Tear down

```bash
./scripts/cleanup-selfhosted.sh --resource-group rg-apexlocal
```

The host, its 8 Premium disks, Bastion, and the NAT Gateway bill continuously even when the
nested VMs are off — deleting the resource group is the only way to reach $0.

## Resume a failed build at its stage

When the build fails, the `ApexStatus` tag names the stage that failed, and
`monitor-selfhosted.sh` prints the exact command to resume from it. Resuming reuses the staged
ISOs, converted base images, router, domain controller, and nodes the previous attempt already
built, so a fix costs one stage instead of a full rebuild:

```bash
./scripts/resume-selfhosted.sh --stage Readiness \
  --artifact-ref <candidate-commit-sha> --resource-group rg-apexlocal
```

The build scrubs the lab credential from the host every time it fails, so resume reads it back
from the lab Key Vault created by the deployment. That needs no retyping as long as you deployed
the lab yourself; another operator needs **Key Vault Secrets User** on the vault, or can set
`LOCALSELF_ADMIN_PASSWORD` explicitly. Deleting the resource group destroys the stored password
along with everything else.

Stages run in this order: `HostFabric`, `Isos`, `BaseImages`, `Router`, `DomainController`,
`ActiveDirectory`, `Nodes`, `Readiness`, `Arc`, `ClusterDeploy`. Resume refreshes the runtime
scripts from the artifact ref first, so pass the ref that contains your fix.

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

- Deploy workloads on the cluster and tear it down again: [Self-hosted runbook](runbook.md).
- Plan capacity and cost: [Self-hosted sizing and cost](sizing.md).
- Review the topology and RBAC model: [Self-hosted overview](overview.md).
- See the release gate and evidence schema: [Self-hosted validation](validation.md).

---

[Documentation home](../README.md) · [Self-hosted overview](overview.md) · [Glossary](../glossary.md)
