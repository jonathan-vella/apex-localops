# Azure Local Small Form Factor (SFF) — Deployment Quickstart

Stand up an Azure Local **Small Form Factor (SFF)** *test* environment inside a single
Azure VM — no physical edge hardware. This mirrors the [LocalBox](deployment-quickstart.md)
approach: a nested-virtualization Hyper-V host in a Bastion-only, NAT-gatewayed resource
group builds the SFF **Maintenance OS (ROE)** test VM inside itself and drives it to the
"ROE setup completed successfully" gate.

> [!IMPORTANT]
> SFF on a VM is for **testing/evaluation only** — Microsoft does not support it for
> production. Production SFF must run on a [validated device](https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-overview#supported-devices).
> SFF is in **PREVIEW**; flows and artifact names may change.

| | |
| --- | --- |
| **What** | One nested-virt host VM that builds a Gen2 ROE test VM (TPM on, Secure Boot off, ≥4 vCPU) |
| **Deploy time** | ~10–15 min ARM, then Hyper-V install + nested-VM build |
| **Default region** | `eastus` (keeps SFF host, site, edge machine, and optional AKS on bare metal in one region) |
| **Est. cost** | ~$700–900/month at 24×7 — see [sff-sizing.md](sff-sizing.md) |
| **Access** | Azure Bastion only (no public IP on the VMs) |

## Architecture

```mermaid
flowchart TB
    User(["Operator"])
    subgraph RG["resource group rg-azlocal-sff-eus01"]
        Bastion["Azure Bastion"]
        NAT["NAT Gateway"]
        KV["Key Vault<br/>ownership voucher"]
        SA["Staging Storage<br/>roe.iso · configurator.msi"]
        Jump["LocalSFF-Mgmt<br/>Win11 jumpbox (optional)"]
        subgraph Host["LocalSFF-Host · Standard_D8s_v5 · Hyper-V"]
            subgraph HVNet["HV-Internal-NAT · 192.168.200.0/24"]
                Nested["SFF test VM (Gen2)<br/>TPM on · SBoot off · 4 vCPU · 16 GB · 256 GB<br/>boots Maintenance OS (ROE)"]
            end
        end
    end
    User -->|HTTPS via portal| Bastion
    Bastion --> Jump
    Bastion --> Host
    Jump -->|portal Download all → upload| SA
    Host -->|managed identity: pull ISO+MSI| SA
    Host -->|store .pem| KV
    Nested -. IMDS 169.254.169.254 DENY .-> Host
```

## Prerequisites

- **Owner** (or Contributor + Role Based Access Control Administrator) on the subscription,
  **Active and Permanent**.
- **Azure CLI** and Bicep (`az bicep upgrade`).
- Host-VM vCPU quota in your region: **8** of `Standard_D8s_v5` (default).
- A strong Windows admin password (14–123 chars; 3 of lower/upper/digit/special).
  **Avoid `$`** — it can break the in-VM bootstrap.
- A Microsoft **Entra ID security group** of machine operators (used later in portal
  machine provisioning).

## 1. Clone and sign in

```bash
git clone https://github.com/jonathan-vella/apex-localops.git
cd apex-localops
az login
az account set --subscription "<your-subscription>"
```

## 2. Register providers + the ZTP preview feature

```bash
./scripts/check-providers-sff.sh             # register providers + AzureLocalZTP feature
./scripts/check-providers-sff.sh --check-only  # report only, no changes
```

This registers the SFF resource providers and the `Microsoft.DeviceOnboarding/AzureLocalZTP`
preview feature (zero-touch provisioning), then reminds you of the manual RBAC + Entra group
steps the preview also requires.

## 3. Deploy

```bash
./scripts/deploy-sff.sh
```

`deploy-sff.sh` prompts for the Windows password (never written to disk), runs preflight
(nested-virt SKU assertion, ZTP feature, provider, and vCPU-quota checks), previews changes
with `what-if`, deploys, then hands off to `monitor-sff.sh`.

Useful flags:

```bash
./scripts/deploy-sff.sh --what-if-only    # preview only
./scripts/deploy-sff.sh --no-monitor      # deploy but don't auto-launch the monitor
./scripts/deploy-sff.sh -g rg-azlocal-sff-eus01 -l eastus
```

> **Azure Hybrid Benefit is on by default** (`enableAzureHybridBenefit = true`): the host VM
> uses `Windows_Server` and the jumpbox uses `Windows_Client`, dropping the Windows license
> charge. This attests you hold eligible licenses — set the param to `false` for
> license-included (PAYG) billing. See [sff-sizing.md](sff-sizing.md#azure-hybrid-benefit-on-by-default).

## 4. Stage the ROE ISO + Configurator App (Azure-initiated)

After the ARM deploy, the host installs Hyper-V and **waits** for two Microsoft-owned
artifacts. Per this project's rule, **all downloads are initiated from an Azure resource** —
never your laptop. The **`LocalSFF-Mgmt`** jumpbox is **pre-provisioned** for this: its setup
extension installs **Azure CLI + Az PowerShell** and stages `Publish-SffArtifacts.ps1` into
`C:\LocalSFF`, with a `SFF-Staging-Instructions.txt` on the desktop (the real staging account
name baked in). Its managed identity holds **Storage Blob Data Contributor** on the staging
account, so uploads need no keys or extra login.

1. RDP to the **`LocalSFF-Mgmt`** jumpbox over Bastion (tooling is already installed).
2. In the portal: **Azure Arc → Operations → Machine provisioning (preview) → Get started →
   View downloads → Download all**.
3. Upload both files to the staging container (canonical names `roe.iso`, `configurator.msi`).
   Easiest — the staged helper (uses the jumpbox managed identity automatically):

   ```powershell
   C:\LocalSFF\Publish-SffArtifacts.ps1 `
     -StorageAccountName <localsff…> -IsoPath .\roe.iso -ConfiguratorPath .\configurator.msi
   ```

   or with the CLI (`az login --identity` first):

   ```bash
   az login --identity
   az storage blob upload --account-name <localsff…> --container-name sff-artifacts \
     --name roe.iso --file <roe>.iso --auth-mode login
   az storage blob upload --account-name <localsff…> --container-name sff-artifacts \
     --name configurator.msi --file <configurator>.msi --auth-mode login
   ```

> [!NOTE]
> Uploading via the **Azure portal blob browser** uses *your* Entra identity, which needs the
> **Storage Blob Data Contributor** data-plane role — Owner/Contributor alone are not enough.
> `deploy-sff.sh` grants the deploying user this role automatically; the jumpbox
> `Publish-SffArtifacts.ps1` path uses the jumpbox managed identity and needs no user role.

The host watcher detects both blobs, builds the nested Gen2 VM (TPM on, Secure Boot off,
≥4 vCPU), applies the IMDS deny ACL, boots the ROE ISO, and waits for success.

## 5. Monitor

```bash
./scripts/monitor-sff.sh            # poll until RoeSucceeded / Failed
./scripts/monitor-sff.sh --once --logs   # one snapshot + in-VM log tail
```

Success = the `SffProgress` tag reaches **`RoeSucceeded`**. Progress milestones:
`Initializing → HyperVInstalling → NetworkConfigured → AwaitingArtifacts → ArtifactsStaged
→ NestedVmCreated → RoeBooting → RoeSucceeded`.

## 6. Ownership voucher + portal provisioning

Follow [sff-runbook.md](sff-runbook.md) to download the ownership voucher (Configurator App
on the host), store it in Key Vault, and provision the machine from the Azure portal.

## Clean up

```bash
./scripts/cleanup-sff.sh            # delete rg-azlocal-sff-eus01, stop all billing
```

> [!WARNING]
> Disks, Bastion, and NAT Gateway bill **even when the VMs are stopped**. Deallocate the
> host between test runs to cut compute cost; delete the resource group to stop everything.

## Related documentation

- [SFF sizing](sff-sizing.md) — host SKU options, cost, and the LocalBox-vs-SFF comparison.
- [SFF runbook](sff-runbook.md) — ownership voucher download and Azure-portal machine provisioning.
- [SFF plan](sff-support-plan.md) — full engineering plan and milestone breakdown.
- [Azure Local deployment guide](deployment-quickstart.md) — the full nested-cluster profile.
