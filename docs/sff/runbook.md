# SFF runbook: ownership voucher and portal provisioning

[Documentation home](../README.md) / SFF / Runbook

This runbook covers the guided steps after the host has built the nested SFF test VM and
`SffProgress` shows **`RoeSucceeded`**: downloading the ownership voucher and provisioning the
machine from the Azure portal. These steps are guided rather than fully automated because the
SFF preview's Configurator App and machine-provisioning experience are portal-centric. To get
to this point, complete the [SFF quickstart](quickstart.md) first.

> [!NOTE]
> All actions are performed **inside Azure** — over Azure Bastion to the host or jumpbox, or
> through Azure Cloud Shell. Nothing is downloaded to a local laptop.

## In this guide

- [Prerequisites](#prerequisites)
- [1. Download the ownership voucher](#1-download-the-ownership-voucher)
- [2. Store the voucher in Key Vault](#2-store-the-voucher-in-key-vault)
- [3. Provision the machine from the portal](#3-provision-the-machine-from-the-portal)
- [4. Connect over SSH](#4-connect-over-ssh)
- [5. Run workloads (optional)](#5-run-workloads-optional)
- [6. Deploy AKS on bare metal (optional)](#6-deploy-aks-on-bare-metal-optional)
- [Troubleshooting](#troubleshooting)
- [Next steps](#next-steps)

## Prerequisites

- `SffProgress = RoeSucceeded` (check with `./scripts/monitor-sff.sh --once`).
- The **Configurator App** installed on the host (staged in step 4 of the quickstart; the
  watcher installs it best-effort, otherwise run `C:\LocalSFF\Tools\configurator.msi`).
- A Microsoft **Entra ID security group** of machine operators.
- A subscription-level role for SSH later: **Virtual Machine Administrator Login** or
  **Virtual Machine User Login**.

## 1. Download the ownership voucher

> [!TIP]
> **This step is now automated.** After the nested VM boots ROE, the host extracts the
> ownership voucher over SSH and stores it in Key Vault for you (the tag reaches
> `SffProgress=VoucherStored`), so you can usually skip straight to step 3. The manual steps
> below are the fallback if automatic extraction did not run (the tag is stuck at
> `RoeSucceeded`). For the fully chained, hands-off path, see
> [Zero-touch deployment](zero-touch.md).

> [!NOTE]
> **Multiple nested VMs (`nestedVmCount > 1`).** The shipped parameters build **two** guests
> (`linuxsff-vm-1`, `linuxsff-vm-2`) reserved at `192.168.200.50` and `.51`, each storing its
> voucher to a distinct Key Vault secret: `sff-ownership-voucher-1` and `sff-ownership-voucher-2`.
> Provision one Azure Local machine per guest, using its matching secret. With a single VM
> (`nestedVmCount = 1`), the bare name `sff-ownership-voucher` is used.

1. **RDP to `LocalSFF-Host`** over Azure Bastion (portal → the VM → Connect → Bastion).
2. Open **Hyper-V Manager**, connect to `linuxsff-vm`, and confirm the console shows
   `[Succeeded] ROE setup completed successfully`. Note the VM IP (`192.168.200.x`).
3. Open the **Configurator App**:
   1. Enter the nested VM **IP**, then select **Next**.
   2. Enter the username **`edgeuser`**, then select **Next**.
   3. Set authentication to **Password**, enter **`Password1`**, then select **Sign in**.

   > [!NOTE]
   > These are Microsoft's fixed maintenance-OS credentials for the evaluation image, reachable
   > only on the host's isolated `192.168.200.0/24` switch. They are for evaluation only.
4. Select **Download Ownership Voucher** and save the `.pem` file (for example, to `Downloads`).

## 2. Store the voucher in Key Vault

On the host (PowerShell), persist the voucher so it never lingers on disk in the clear:

```powershell
C:\LocalSFF\Save-OwnershipVoucher.ps1 -Path C:\Users\arcdemo\Downloads\ownership-voucher.pem
```

This stores it as the secret `sff-ownership-voucher` (base64) in the SFF Key Vault, using the
host managed identity, and tags `SffProgress=VoucherStored`. Retrieve it later with:

```bash
az keyvault secret show --vault-name <sffkv…> --name sff-ownership-voucher \
  --query value -o tsv | base64 -d > voucher.pem
```

## 3. Provision the machine from the portal

The portal wizard is the preview's machine-provisioning experience.

> [!TIP]
> Pre-create the Arc **site** first so you only **select** it in the wizard:
>
> ```bash
> ./scripts/ensure-arc-site.sh --resource-group rg-sff-azl-eus01 --location eastus --site-name local-sff
> ```
>
> This creates or reuses the site (`az site`). The Arc **Gateway is optional** and not required
> for SFF machine provisioning (add `--with-gateway` only if your environment uses one). The
> site selection and voucher upload below remain a portal step in the preview.
> `provision-machine.sh` runs this for you and then polls until the machine is Provisioned.

1. In the Azure portal, go to **Azure Arc → Operations → Machine provisioning (preview) →
   Provision**.
2. On **Basics**, select the pre-created **site** (or create one — name, subscription, resource
   group), then select **Create**.
3. On **Configure the site**, set the region, then select **Save**. (Using an Arc Gateway is
   optional — leave it off unless your environment requires one.)
4. On **SSH keys**, generate a new key pair in Azure (download the private `.pem`) or upload
   your public key.
5. On **Add the machine**, under **Provisioned machines → Add**, upload the **ownership
   voucher** `.pem`, choose OS **Azure Linux 2604**, name the SSH key, then select **Review +
   create**.
6. Wait until **Status = Provisioned** (up to ~25 minutes).

## 4. Connect over SSH

Assign yourself **Virtual Machine Administrator Login** or **Virtual Machine User Login** at the
subscription, then from Azure Cloud Shell:

```bash
chmod 600 /path/to/private-key.pem
# Use the SSH command shown under the provisioned machine's Settings → Connect, for example:
ssh -i /path/to/private-key.pem clouduser@<ip-address>
```

Or build a config for repeat use:

```bash
az ssh config -g <MANAGED_RG> -n <ARC_MACHINE> --file ./sshconfig -i /path/to/private-key.pem
ssh -F ./sshconfig <MANAGED_RG>-<ARC_MACHINE>-clouduser
```

## 5. Run workloads (optional)

Copy and run the vendored K3s/Arc bring-up on the provisioned machine:

```bash
scp -F ./sshconfig artifacts/sff/vendor/setup-k3s-arc.sh <MANAGED_RG>-<ARC_MACHINE>-clouduser:~
ssh -F ./sshconfig <MANAGED_RG>-<ARC_MACHINE>-clouduser 'bash ~/setup-k3s-arc.sh'
```

## 6. Deploy AKS on bare metal (optional)

Once the machine is **Provisioned**, you can deploy a managed, Arc-connected **AKS on bare
metal** cluster directly onto it (single-node, Cilium, zero-rated in preview). This is the
recommended path for a fully Azure-managed Kubernetes experience, versus the self-managed K3s
script above.

Provide the provisioned **EdgeMachine name** (the cluster deploys into its resource group), a
reserved control-plane IP in the machine's subnet, and your SSH public key, then deploy. The
Entra admin group is **created automatically** (or reused if one of the same name exists):

```bash
export AKSBM_EDGE_MACHINE_NAME="<edge-machine-name>"   # az resource list --resource-type Microsoft.AzureStackHCI/edgeMachines -o table
export AKSBM_CONTROL_PLANE_IP="192.168.200.50"
# Optional: export AKSBM_ADMIN_GROUP_ID="<guid>" to use a specific existing group instead.
./scripts/deploy-aks-baremetal.sh
./scripts/connect-aks-baremetal.sh --name localsff-aks -g rg-sff-azl-eus01 --get-nodes
```

Full walkthrough: [AKS on bare metal](aks-baremetal.md).

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Portal upload fails: *"not authorized to perform this operation using this permission"* or *"do not have permissions to list the data"* | You have a control-plane role (Owner/Contributor) but no data-plane role. `deploy-sff.sh` now grants the deploying user **Storage Blob Data Contributor** on the staging account automatically; for others, run `az role assignment create --assignee <objectId> --role "Storage Blob Data Contributor" --scope <staging-SA-id>` (wait 1–2 minutes). Or use the jumpbox `Publish-SffArtifacts.ps1` (managed-identity path, no user role needed). |
| `SffProgress=AwaitingArtifacts` forever | Confirm `roe.iso` and `configurator.msi` are in the `sff-artifacts` container; re-run `Publish-SffArtifacts.ps1`. |
| `SffProgress=RoeBooting` for several minutes | Expected. The builder waits for SSH (port 22) on the nested VM (`192.168.200.50`) as the authoritative readiness signal. ROE in nested Hyper-V intermittently needs one reboot to finish maintenance-environment setup — the builder performs a single automatic reboot after `RebootAfterMinutes` (default 8) if SSH is not up yet, so no manual reboot is required. |
| `SffProgress=RoeTimeout` | SSH (port 22) never came up within the timeout, even after the auto-reboot nudge. Open the Hyper-V console on the host; check `C:\LocalSFF\Logs\linuxsff-vm-serial.log`. You can manually `Restart-VM linuxsff-vm` and re-probe `Test-NetConnection 192.168.200.50 -Port 22`. |
| `SffProgress=Failed` (network) | Inspect `C:\LocalSFF\Logs\Stage-SffArtifacts.log`; re-run `C:\LocalSFF\set-network.ps1 -Mode WinNAT` (idempotent). |
| Configurator App cannot reach the VM | Ensure you used the `192.168.200.x` IP; the VM gets DHCP from the host's WinNAT scope. |
| Voucher store fails | Confirm the host identity has **Key Vault Secrets Officer**; check `az keyvault show`. |

See also: [Microsoft Learn — Connect a provisioned machine](https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-connect-portal)
and the vendored upstream docs under [azure-local-sff/](../azure-local-sff/README.md).

## Next steps

- Deploy Kubernetes onto the machine: [AKS on bare metal](aks-baremetal.md).
- Automate the whole chain instead: [Zero-touch deployment](zero-touch.md).

---

[Documentation home](../README.md) · [SFF overview](overview.md) · [Glossary](../glossary.md)
