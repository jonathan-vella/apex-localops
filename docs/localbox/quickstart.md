# Deployment Quickstart

End-to-end deployment of Azure Local in an Azure VM using this repository. Infra defaults
to **`swedencentral`**; the Azure Local instance registers in **`westeurope`**. Sizing and
cost: [sizing-guidance.md](sizing-guidance.md).

## Prerequisites

- **Owner** (or Contributor + User Access Administrator) on the target subscription.
- **Azure CLI ≥ 2.65** (`az --version`) and Bicep (`az bicep upgrade`).
- **64 vCPUs** of `Standard_E64s_v6` quota in your infra region.
- A strong Windows admin password (14–123 chars; 3 of lower/upper/digit/special).
  **Avoid `$`** — it breaks the in-VM LogonScript.

## 1. Clone and sign in

```bash
git clone https://github.com/jonathan-vella/apex-localops.git
cd apex-localops
az login
az account set --subscription "<your-subscription>"
```

## 2. Register resource providers

The bundled script checks each required provider, registers the missing ones, polls to
completion, and prints the `spnProviderId` (the Azure Local resource-provider object id):

```bash
./scripts/check-providers.sh             # check + register
./scripts/check-providers.sh --check-only  # report only, no changes
```

`deploy.sh` resolves `spnProviderId` automatically, so you normally don't need to copy it
anywhere — but you can export it to override: `export LOCALBOX_SPN_PROVIDER_ID=<guid>`.

## 3. Check quota

```bash
az vm list-usage --location swedencentral -o table | grep -iE "ESv6"
```

You need **64** available vCPUs in the `Standard_ESv6` family. Request an increase before
deploying if needed.

## 4. Deploy

`deploy.sh` prompts for the Windows admin password (never written to disk), resolves your
`tenantId` and `spnProviderId`, runs preflight checks, previews with `what-if`, deploys,
then hands off to the monitor:

```bash
./scripts/deploy.sh                  # preflight -> what-if -> confirm -> deploy -> monitor
./scripts/deploy.sh --what-if-only   # preview only
./scripts/deploy.sh --no-monitor     # deploy without auto-launching the monitor
./scripts/deploy.sh -g rg-localbox -l swedencentral   # override RG / region
```

Preflight fails fast (before the ~18 min ARM deploy) on: `main.bicep` not compiling, an
unresolved `spnProviderId`, unregistered critical providers, and a **staging/witness
storage account in the wrong region** (see [troubleshooting.md](troubleshooting.md)).

### Manual deploy (without the script)

The committed parameters contain no GUIDs, so export the identity values and password
first:

```bash
export LOCALBOX_TENANT_ID=$(az account show --query tenantId -o tsv)
export LOCALBOX_SPN_PROVIDER_ID=$(az ad sp list \
  --display-name "Microsoft.AzureStackHCI Resource Provider" --query "[0].id" -o tsv)
read -rs LOCALBOX_ADMIN_PASSWORD && export LOCALBOX_ADMIN_PASSWORD

az group create -n rg-localbox -l swedencentral
az deployment group create -g rg-localbox \
  -f infra/bicep/azlocal-js/main.bicep -p infra/bicep/azlocal-js/main.bicepparam
```

### Deploy a different topology profile

The default is the **3-node** profile (no witness). To deploy the cheaper **2-node** profile
(cloud witness; only where shared-key storage is permitted) without editing files:

```bash
az deployment group create -g rg-localbox \
  -f infra/bicep/azlocal-js/main.bicep -p infra/bicep/azlocal-js/main.bicepparam \
  -p clusterNodeCount=2 -p vmSize=Standard_E32s_v6 -p dataDiskCount=8
```

Topology and sizing rationale: [sizing-guidance.md](sizing-guidance.md).

### Pin a release (reproducible deploys)

By default the VM fetches artifacts from the **`main`** branch. For a frozen, repeatable
build, pin to a release tag — the deploy then reads exactly the artifacts in that tag,
either in `infra/bicep/azlocal-js/main.bicepparam`:

```bicep
param githubBranch = 'v1.0.0'
```

or at deploy time without editing files:

```bash
az deployment group create -g rg-localbox -f infra/bicep/azlocal-js/main.bicep \
  -p infra/bicep/azlocal-js/main.bicepparam -p githubBranch=v1.0.0
```

### Defaults & customization

All of these are on by default and toggleable in
[main.bicepparam](../infra/bicep/azlocal-js/main.bicepparam):

| Feature | Default | Param |
| --- | --- | --- |
| P30 disk performance tier (12 × 256 GB) | on | `host/host.bicep` `dataDiskPerformanceTier` |
| Windows 11 management jumpbox | on | `deployManagementVm` |
| Bastion + NAT Gateway (no public IP) | on | `deployBastion` |
| Auto-build the cluster after VM setup | on | `autoDeployClusterResource` |
| Auto-login to start the in-VM build | on | `vmAutologon` |
| Client VM size | `Standard_E64s_v6` | `vmSize` |
| Azure Hybrid Benefit (Windows licensing) | on | `host/host.bicep` `licenseType: 'Windows_Server'` · `mgmt/managementVm.bicep` `licenseType: 'Windows_Client'` |

> [!NOTE]
> **Azure Hybrid Benefit (AHB)** is applied to both VMs to remove the per-core Windows
> licensing surcharge: `Windows_Server` on the `LocalBox-Client` host and `Windows_Client`
> on the Windows 11 jumpbox. Setting these asserts you hold eligible licenses —
> Windows Server with active **Software Assurance** (or a qualifying subscription) for the
> host, and **Windows 10/11 E3/E5 or Windows VDA** per-user licenses for the jumpbox. If
> you are not entitled, remove the `licenseType` line(s) before deploying. `licenseType`
> is also updatable in place, e.g. `az vm update -g rg-localbox -n LocalBox-Client --set licenseType=Windows_Server`.

Identity values (`tenantId`, `spnProviderId`) and the admin password are **never stored** in
the repo — `deploy.sh` resolves the GUIDs at runtime and reads the password from the
`LOCALBOX_ADMIN_PASSWORD` environment variable.

## 5. The in-VM build starts automatically (no manual login)

After the ARM deploy, the client VM runs `Bootstrap.ps1`, installs Hyper-V, and reboots.
Because `vmAutologon = true` (the default), the VM then **auto-logs-in as the admin user and
the cluster-build script starts on its own** — you do **not** need to RDP/Bastion in and
sign in to kick it off. The build runs **~4–5 hours** (add ~1 hour if Azure Local updates
are available), then the script window closes itself.

> The `LocalBox-Client` VM is a standalone **workgroup** machine — it is never domain-joined.
> The auto-logon uses the **local** admin account, so `DefaultDomainName` is the VM's own
> computer name (not a domain). The nested `jumpstart.local` Active Directory exists only
> inside the cluster's management VM (`AzLMGMT`) and never involves this host.

> Security note: while `vmAutologon` is on, the admin password sits in the Winlogon registry
> in plaintext for the duration of the build. The logon script **removes** the autologon
> registry keys (`AutoAdminLogon`, `DefaultUserName`, `DefaultPassword`, `DefaultDomainName`)
> as soon as the build completes. To disable auto-login entirely, deploy with
> `-p vmAutologon=false` — but then you must connect and sign in once to start the build.

### What the build downloads from Microsoft

The **orchestration** is fully vendored in this repo — the Bicep templates and the entire
in-VM `artifacts/` tree (PowerShell, DSC, ARM JSON, config) — so there is no
`microsoft/azure_arc` dependency at deploy time. A few large or Microsoft-owned binaries are
fetched from their official sources **at build time**:

- Azure Local / Windows Server **OS VHDX images** (multi-GB, from Microsoft blob storage).
- **PowerShell 7** and **Windows Admin Center** MSIs (official Microsoft download URLs).
- The desktop **wallpaper** PNG (from `Azure/arc_jumpstart_docs`).

## 6. Monitor the in-VM cluster build

The ARM deploy finishes in ~18 min, but the nested cluster then builds **inside the VM for
2–4 hours** with no Azure-visible deployment state. Track it from outside the VM (no login
required):

```bash
./scripts/monitor.sh                 # poll until a terminal state
./scripts/monitor.sh --once          # one snapshot and exit
./scripts/monitor.sh --once --logs   # snapshot + tail the in-VM log (no RDP needed)
```

`monitor.sh` reads three independent signals without Bastion/RDP: the `DeploymentProgress` /
`DeploymentStatus` **resource-group tags** the in-VM scripts emit at each milestone, the
`Microsoft.AzureStackHCI/clusters` **resource** (authoritative proof the cluster formed),
and — with `--logs` — a live tail of `C:\LocalBox\Logs` via `az vm run-command`.

Success = the `Microsoft.AzureStackHCI/clusters` resource reaches
`provisioningState = Succeeded` (or the resource-group `DeploymentProgress` tag becomes
`Completed`).

## 7. Connect

Once the cluster is up, **connect over Azure Bastion** in the portal — the client VM has no
public IP. You can Bastion into either `LocalBox-Client` or the Windows 11 jumpbox
(`LocalBox-Mgmt`). Windows Admin Center runs inside the nested `AzLMGMT` host.

## 8. Clean up (stops billing)

Disks, Bastion, and NAT bill even when the VM is deallocated. To stop **all** charges,
delete the resource group:

```bash
az group delete --name rg-localbox --yes
```

To pause more cheaply without losing state, deallocate the VMs instead — but disks,
Bastion, and NAT keep billing (~$1,500/mo floor).

## Related documentation

- [Sizing guidance](sizing-guidance.md) — VM/disk sizing, the full cost breakdown, and the 2- vs 3-node topology rationale.
- [Troubleshooting](troubleshooting.md) — common failures and recovery (witness-location mismatch, preflight blocks, and more).
- [SFF deployment guide](sff-quickstart.md) — the lighter Small Form Factor test profile.
