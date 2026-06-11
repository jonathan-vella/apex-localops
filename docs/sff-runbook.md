# Azure Local SFF — Ownership Voucher & Portal Provisioning Runbook

This runbook covers the **guided** steps after the host has built the nested SFF test VM
and `SffProgress` shows **`RoeSucceeded`**: downloading the ownership voucher and provisioning
the machine from the Azure portal. These steps are guided (not fully automated) because the
SFF preview's Configurator App and machine-provisioning experience are portal/GUI-centric.

> All actions are performed **inside Azure** — over Azure Bastion to the host/jumpbox, or via
> Azure Cloud Shell. Nothing is downloaded to a local laptop.

## Prerequisites

- `SffProgress = RoeSucceeded` (check `./scripts/monitor-sff.sh --once`).
- The **Configurator App** installed on the host (staged in step 4 of the quickstart; the
  watcher installs it best-effort, else run `C:\LocalSFF\Tools\configurator.msi`).
- A Microsoft **Entra ID security group** of machine operators.
- Subscription-level role for SSH later: **Virtual Machine Administrator Login** or
  **Virtual Machine User Login**.

## 1. Download the ownership voucher

> [!TIP]
> **This step is now automated.** After the nested VM boots ROE, the host extracts the
> ownership voucher over SSH and stores it in Key Vault for you (the tag reaches
> `SffProgress=VoucherStored`), so you can usually skip straight to §3. The manual steps
> below are the fallback if automatic extraction did not run (tag stuck at `RoeSucceeded`).
> For the fully chained, hands-off path see [sff-zero-touch.md](sff-zero-touch.md).

> [!NOTE]
> **Multiple nested VMs (`nestedVmCount > 1`).** The shipped params build **two** guests
> (`linuxsff-vm-1`, `linuxsff-vm-2`) reserved at `192.168.200.50`/`.51`, each storing its
> voucher to a distinct Key Vault secret: `sff-ownership-voucher-1` and
> `sff-ownership-voucher-2`. Provision one Azure Local machine per guest using its matching
> secret. With a single VM (`nestedVmCount = 1`) the bare name `sff-ownership-voucher` is used.

1. **RDP to `LocalSFF-Host`** over Azure Bastion (portal → the VM → Connect → Bastion).
2. Open **Hyper-V Manager** → connect to **`linuxsff-vm`** → confirm the console shows
   `[Succeeded] ROE setup completed successfully`. Note the VM IP (`192.168.200.x`).
3. Open the **Configurator App**:
   - Enter the nested VM **IP** → **Next**.
   - Username **`edgeuser`** → **Next**.
   - Authentication **Password**, value **`Password1`** → **Sign in**.

   > These are Microsoft's fixed maintenance-OS credentials for the **evaluation** image,
   > reachable only on the host's isolated `192.168.200.0/24` switch. Eval-only.
4. Select **Download Ownership Voucher** and save the `.pem` (e.g. to `Downloads`).

## 2. Store the voucher in Key Vault

On the host (PowerShell), persist the voucher so it never lingers on disk in the clear:

```powershell
C:\LocalSFF\Save-OwnershipVoucher.ps1 -Path C:\Users\arcdemo\Downloads\ownership-voucher.pem
```

This stores it as the secret `sff-ownership-voucher` (base64) in the SFF Key Vault using the
host managed identity and tags `SffProgress=VoucherStored`. Retrieve later with:

```bash
az keyvault secret show --vault-name <sffkv…> --name sff-ownership-voucher \
  --query value -o tsv | base64 -d > voucher.pem
```

## 3. Provision the machine from the Azure portal (preview)

> **Tip:** pre-create the Arc **site** first so you only **select** it in the wizard:
> ```bash
> ./scripts/ensure-arc-site.sh --resource-group rg-azlocal-sff-eus01 --location eastus --site-name local-sff
> ```
> This create-or-reuses the site (`az site`). The Arc **Gateway is optional** and not required
> for SFF machine provisioning (add `--with-gateway` only if your environment uses one). The
> site selection and voucher upload below remain a portal step in the preview.
> (`provision-machine.sh` runs this for you and then polls until the machine is Provisioned.)

1. Azure portal → **Azure Arc → Operations → Machine provisioning (preview) → Provision**.
2. **Basics**: select the pre-created **site** (or create one — name, subscription, resource
   group) → **Create**.
3. **Configure the site**: set the Region → **Save**. (Using an Arc Gateway is optional — leave
   it off unless your environment requires one.)
4. **SSH keys**: generate a new key pair in Azure (download the private `.pem`) or upload your
   public key.
5. **Add the machine**: under **Provisioned machines → Add**, upload the **ownership voucher**
   `.pem`, choose OS **Azure Linux 2604**, name the SSH key → **Review + create**.
6. Wait until **Status = Provisioned** (up to ~25 min).

## 4. Connect over SSH

Assign yourself **Virtual Machine Administrator/User Login** at the subscription, then from
Azure Cloud Shell:

```bash
chmod 600 /path/to/private-key.pem
# Use the SSH command shown under the provisioned machine's Settings → Connect, e.g.:
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
recommended path for a fully Azure-managed Kubernetes experience versus the self-managed K3s
script above.

Provide the **Provisioned EdgeMachine name** (the cluster deploys into its resource group), a
reserved control-plane IP in the machine's subnet, and your SSH public key, then deploy. The
Entra admin group is **created automatically** (or reused if one of the same name exists):

```bash
export AKSBM_EDGE_MACHINE_NAME="<edge-machine-name>"   # az resource list --resource-type Microsoft.AzureStackHCI/edgeMachines -o table
export AKSBM_CONTROL_PLANE_IP="192.168.200.50"
# Optional: export AKSBM_ADMIN_GROUP_ID="<guid>" to use a specific existing group instead.
./scripts/deploy-aks-baremetal.sh
./scripts/connect-aks-baremetal.sh --name localsff-aks -g rg-azlocal-sff-eus01 --get-nodes
```

Full walkthrough: [aks-baremetal-quickstart.md](aks-baremetal-quickstart.md).

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Portal upload fails: *"not authorized to perform this operation using this permission"* / *"do not have permissions to list the data"* | You have a **control-plane** role (Owner/Contributor) but no **data-plane** role. `deploy-sff.sh` now grants the deploying user **Storage Blob Data Contributor** on the staging account automatically; for others, run `az role assignment create --assignee <objectId> --role "Storage Blob Data Contributor" --scope <staging-SA-id>` (wait ~1-2 min). Or just use the jumpbox `Publish-SffArtifacts.ps1` (managed-identity path, no user role needed). |
| `SffProgress=AwaitingArtifacts` forever | Confirm `roe.iso` + `configurator.msi` are in the `sff-artifacts` container; re-run `Publish-SffArtifacts.ps1`. |
| `SffProgress=RoeBooting` for several minutes | Expected. The builder waits for **SSH(22)** on the nested VM (`192.168.200.50`) as the authoritative readiness signal. ROE in nested Hyper-V intermittently needs one reboot to finish maintenance-env setup — the builder now performs a **single automatic reboot** after `RebootAfterMinutes` (default 8) if SSH isn't up yet, so no manual reboot is required. |
| `SffProgress=RoeTimeout` | SSH(22) never came up within the timeout even after the auto-reboot nudge. Open the Hyper-V console on the host; check `C:\LocalSFF\Logs\linuxsff-vm-serial.log`. You can manually `Restart-VM linuxsff-vm` and re-probe `Test-NetConnection 192.168.200.50 -Port 22`. |
| `SffProgress=Failed` (network) | Inspect `C:\LocalSFF\Logs\Stage-SffArtifacts.log`; re-run `C:\LocalSFF\set-network.ps1 -Mode WinNAT` (idempotent). |
| Configurator App can't reach the VM | Ensure you used the `192.168.200.x` IP; the VM gets DHCP from the host's WinNAT scope. |
| Voucher store fails | Confirm the host identity has **Key Vault Secrets Officer**; check `az keyvault show`. |

See also: [Microsoft Learn — Connect a provisioned machine](https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-connect-portal)
and the vendored upstream docs under [azure-local-sff/](azure-local-sff/).
