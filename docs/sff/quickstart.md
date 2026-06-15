# Deploy the SFF profile

[Documentation home](../README.md) / SFF / Quickstart

This guide deploys an Azure Local Small Form Factor (SFF) test environment inside a single Azure
VM — no physical edge hardware. A nested-virtualization Hyper-V host builds the SFF Maintenance
OS (ROE) test VM inside itself and drives it to the "ROE setup completed successfully" state.
New to this profile? Read the [SFF overview](overview.md) first.

> [!IMPORTANT]
> SFF on a VM is for **testing and evaluation only** — Microsoft does not support it for
> production. Production SFF must run on a
> [validated device](https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-overview#supported-devices).
> SFF is in **preview**; flows and artifact names may change.

| | |
| --- | --- |
| **What** | One nested-virtualization host VM that builds a Gen2 ROE test VM (TPM on, Secure Boot off, ≥4 vCPU). |
| **Deploy time** | ~10–15 min ARM, then the Hyper-V install and nested-VM build. |
| **Default region** | Host in `swedencentral` (`rg-sff-host-swc01`); the Azure Local site, edge machine, and AKS in `eastus` (`rg-sff-azl-eus01`). |
| **Est. cost** | ~$700–900/month at 24×7 — see [SFF sizing and cost](sizing.md). |
| **Access** | Azure Bastion only (no public IP on the VMs). |

## In this guide

- [Prerequisites](#prerequisites)
- [1. Clone the repo and sign in](#1-clone-the-repo-and-sign-in)
- [2. Register providers and the ZTP preview feature](#2-register-providers-and-the-ztp-preview-feature)
- [3. Deploy the host](#3-deploy-the-host)
- [4. Stage the ROE ISO and Configurator App](#4-stage-the-roe-iso-and-configurator-app)
- [5. Monitor the build](#5-monitor-the-build)
- [6. Download the voucher and provision](#6-download-the-voucher-and-provision)
- [Clean up](#clean-up)
- [Next steps](#next-steps)

## Prerequisites

- The **Owner** role (or **Contributor** plus **Role Based Access Control Administrator**) on
  the subscription, active and permanent. See [RBAC](../glossary.md#identity-and-access).
- **Azure CLI** and Bicep (`az bicep upgrade`).
- Host-VM vCPU quota in the host region (`swedencentral`): **16** of `Standard_D16s_v5` (the
  shipped default, which builds two nested VMs). For a single nested VM, use `Standard_D8s_v5`
  with `nestedVmCount=1` (8 vCPU); see [SFF sizing and cost](sizing.md).
- A strong Windows admin password: 14–123 characters, with three of lowercase, uppercase,
  digit, and special. **Avoid `$`** — it can break the in-VM bootstrap.
- A Microsoft **Entra ID security group** of machine operators (used later in portal machine
  provisioning).

## 1. Clone the repo and sign in

```bash
git clone https://github.com/jonathan-vella/apex-localops.git
cd apex-localops
az login
az account set --subscription "<your-subscription>"
```

## 2. Register providers and the ZTP preview feature

```bash
./scripts/check-providers-sff.sh             # register providers + AzureLocalZTP feature
./scripts/check-providers-sff.sh --check-only  # report only, no changes
```

This registers the SFF resource providers and the `Microsoft.DeviceOnboarding/AzureLocalZTP`
preview feature (zero-touch provisioning), then reminds you of the manual RBAC and Entra group
steps the preview also requires.

## 3. Deploy the host

```bash
./scripts/deploy-sff.sh
```

`deploy-sff.sh` prompts for the Windows password (never written to disk), runs preflight (the
nested-virtualization SKU assertion, the ZTP feature, provider, and vCPU-quota checks), previews
the changes with what-if, deploys, then hands off to `monitor-sff.sh`.

> [!NOTE]
> The host deploys to **`swedencentral`** (`rg-sff-host-swc01`) — East US restricts the
> nested-virtualization VM capacity SFF needs. Later, the Azure Local site, edge machine, and
> AKS on bare metal are provisioned separately into **`eastus`** (`rg-sff-azl-eus01`), because
> AKS on bare metal is East US only.

Useful flags:

```bash
./scripts/deploy-sff.sh --what-if-only    # preview only
./scripts/deploy-sff.sh --no-monitor      # deploy but don't auto-launch the monitor
./scripts/deploy-sff.sh -g rg-sff-host-swc01 -l swedencentral   # the defaults; override if needed
```

> [!NOTE]
> **Azure Hybrid Benefit is on by default** (`enableAzureHybridBenefit = true`): the host VM
> uses `Windows_Server` and the jumpbox uses `Windows_Client`, dropping the Windows license
> charge. This attests that you hold eligible licenses — set the parameter to `false` for
> license-included (PAYG) billing. See
> [SFF sizing and cost](sizing.md#azure-hybrid-benefit-on-by-default).

## 4. Stage the ROE ISO and Configurator App

After the ARM deployment, the host installs Hyper-V and **waits** for two Microsoft-owned
artifacts. Per this project's rule, **all downloads are initiated from an Azure resource** —
never your laptop. The `LocalSFF-Mgmt` jumpbox is pre-provisioned for this: its setup extension
installs Azure CLI and Az PowerShell and stages `Publish-SffArtifacts.ps1` into `C:\LocalSFF`,
with a `SFF-Staging-Instructions.txt` on the desktop (the real staging account name is baked
in). Its managed identity holds **Storage Blob Data Contributor** on the staging account, so
uploads need no keys or extra login.

1. RDP to the `LocalSFF-Mgmt` jumpbox over Azure Bastion (the tooling is already installed).
2. In the portal, go to **Azure Arc → Operations → Machine provisioning (preview) → Get started
   → View downloads → Download all**.
3. Upload both files to the staging container (canonical names `roe.iso` and
   `configurator.msi`). The easiest way uses the staged helper, which uses the jumpbox managed
   identity automatically:

   ```powershell
   C:\LocalSFF\Publish-SffArtifacts.ps1 `
     -StorageAccountName <localsff…> -IsoPath .\roe.iso -ConfiguratorPath .\configurator.msi
   ```

   Or use the CLI (run `az login --identity` first):

   ```bash
   az login --identity
   az storage blob upload --account-name <localsff…> --container-name sff-artifacts \
     --name roe.iso --file <roe>.iso --auth-mode login
   az storage blob upload --account-name <localsff…> --container-name sff-artifacts \
     --name configurator.msi --file <configurator>.msi --auth-mode login
   ```

> [!NOTE]
> Uploading through the Azure portal blob browser uses *your* Entra identity, which needs the
> **Storage Blob Data Contributor** data-plane role — Owner or Contributor alone are not enough.
> `deploy-sff.sh` grants the deploying user this role automatically; the jumpbox
> `Publish-SffArtifacts.ps1` path uses the jumpbox managed identity and needs no user role.

The host watcher detects both blobs, builds the nested Gen2 VM (TPM on, Secure Boot off,
≥4 vCPU), applies the IMDS deny ACL, boots the ROE ISO, and waits for success.

## 5. Monitor the build

```bash
./scripts/monitor-sff.sh            # poll until RoeSucceeded or Failed
./scripts/monitor-sff.sh --once --logs   # one snapshot plus in-VM log tail
```

The build has succeeded when the `SffProgress` tag reaches **`RoeSucceeded`**. The milestones
are:

```text
Initializing → HyperVInstalling → NetworkConfigured → AwaitingArtifacts →
ArtifactsStaged → NestedVmCreated → RoeBooting → RoeSucceeded
```

## 6. Download the voucher and provision

Follow the [SFF runbook](runbook.md) to download the ownership voucher (the Configurator App on
the host), store it in Key Vault, and provision the machine from the Azure portal.

## Clean up

```bash
./scripts/cleanup-sff.sh            # delete the host RG (rg-sff-host-swc01), stop all billing
```

> [!WARNING]
> Disks, Bastion, and the NAT Gateway bill **even when the VMs are stopped**. Deallocate the
> host between test runs to cut compute cost; delete the resource group to stop everything.

## Next steps

- Provision the machine into Azure: [SFF runbook](runbook.md).
- Plan capacity and cost: [SFF sizing and cost](sizing.md).
- Automate the whole chain: [Zero-touch deployment](zero-touch.md).
- Deploy Kubernetes onto the machine: [AKS on bare metal](aks-baremetal.md).

---

[Documentation home](../README.md) · [SFF overview](overview.md) · [Glossary](../glossary.md)
