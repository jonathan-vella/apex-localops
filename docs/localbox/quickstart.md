# Deploy the LocalBox profile

[Documentation home](../README.md) / LocalBox / Quickstart

This guide deploys a nested Azure Local cluster inside a single Azure VM using the LocalBox
profile, then shows you how to monitor the in-VM build, connect, and clean up. New to this
profile? Read the [LocalBox overview](overview.md) first.

The infrastructure deploys to **`swedencentral`** by default, and the Azure Local instance
registers in **`westeurope`**. For sizing and cost, see [LocalBox sizing and cost](sizing.md).

> [!NOTE]
> apex-localops is a **draft release** under active development — templates, scripts, and docs
> may change. See [Project status](../../README.md#project-status) and the
> [roadmap](../roadmap.md).

## In this guide

- [Prerequisites](#prerequisites)
- [1. Clone the repo and sign in](#1-clone-the-repo-and-sign-in)
- [2. Register resource providers](#2-register-resource-providers)
- [3. Check your quota](#3-check-your-quota)
- [4. Deploy the infrastructure](#4-deploy-the-infrastructure)
- [5. Let the in-VM build run](#5-let-the-in-vm-build-run)
- [6. Monitor the cluster build](#6-monitor-the-cluster-build)
- [7. Connect to the environment](#7-connect-to-the-environment)
- [8. Clean up](#8-clean-up)
- [Next steps](#next-steps)

## Prerequisites

- The **Owner** role (or **Contributor** plus **User Access Administrator**) on the target
  subscription. See [RBAC](../glossary.md#identity-and-access).
- **Azure CLI 2.65 or later** (`az --version`) with Bicep (`az bicep upgrade`).
- **64 vCPUs** of `Standard_E64s_v6` quota in your infrastructure region.
- A strong Windows admin password: 14–123 characters, with three of lowercase, uppercase,
  digit, and special. **Avoid `$`** — it breaks the in-VM logon script.

## 1. Clone the repo and sign in

```bash
git clone https://github.com/jonathan-vella/apex-localops.git
cd apex-localops
az login
az account set --subscription "<your-subscription>"
```

## 2. Register resource providers

The bundled script checks each required provider, registers the missing ones, waits for
completion, and prints the Azure Local resource-provider object ID:

```bash
./scripts/check-providers.sh             # check and register
./scripts/check-providers.sh --check-only  # report only, no changes
```

`deploy.sh` resolves this object ID automatically, so you do not normally need to copy it. To
override it, export it instead:

```bash
export LOCALBOX_SPN_PROVIDER_ID=<guid>
```

## 3. Check your quota

```bash
az vm list-usage --location swedencentral -o table | grep -iE "ESv6"
```

You need **64** available vCPUs in the `Standard_ESv6` family. Request an increase before you
deploy if you are short.

## 4. Deploy the infrastructure

`deploy.sh` prompts for the Windows admin password (never written to disk), resolves your
tenant ID and the provider object ID, runs preflight checks, previews the changes with
what-if, deploys, then hands off to the monitor:

```bash
./scripts/deploy.sh                  # preflight → what-if → confirm → deploy → monitor
./scripts/deploy.sh --what-if-only   # preview only
./scripts/deploy.sh --no-monitor     # deploy without auto-launching the monitor
./scripts/deploy.sh -g rg-localbox -l swedencentral   # override resource group / region
```

Preflight fails fast — before the ~18-minute ARM deployment — if `main.bicep` does not compile,
the provider object ID does not resolve, a critical provider is unregistered, or the
staging/witness storage account is in the wrong region. See [Troubleshooting](troubleshooting.md).

### Deploy without the script

The committed parameters contain no GUIDs, so export the identity values and password first:

```bash
export LOCALBOX_TENANT_ID=$(az account show --query tenantId -o tsv)
export LOCALBOX_SPN_PROVIDER_ID=$(az ad sp list \
  --display-name "Microsoft.AzureStackHCI Resource Provider" --query "[0].id" -o tsv)
read -rs LOCALBOX_ADMIN_PASSWORD && export LOCALBOX_ADMIN_PASSWORD

az group create -n rg-localbox -l swedencentral
az deployment group create -g rg-localbox \
  -f infra/bicep/azlocal-js/main.bicep -p infra/bicep/azlocal-js/main.bicepparam
```

### Deploy a different topology

The default is the 3-node profile (no witness). To deploy the cheaper 2-node profile (cloud
witness, only where shared-key storage is permitted) without editing files:

```bash
az deployment group create -g rg-localbox \
  -f infra/bicep/azlocal-js/main.bicep -p infra/bicep/azlocal-js/main.bicepparam \
  -p clusterNodeCount=2 -p vmSize=Standard_E32s_v6 -p dataDiskCount=8
```

For the topology and sizing rationale, see [LocalBox sizing and cost](sizing.md).

### Pin a release for reproducible deploys

By default the VM fetches artifacts from the `main` branch. For a frozen, repeatable build,
pin to a release tag — the deploy then reads exactly the artifacts in that tag. Either set it
in [main.bicepparam](../../infra/bicep/azlocal-js/main.bicepparam):

```bicep
param githubBranch = 'v1.0.0'
```

or pass it at deploy time without editing files:

```bash
az deployment group create -g rg-localbox -f infra/bicep/azlocal-js/main.bicep \
  -p infra/bicep/azlocal-js/main.bicepparam -p githubBranch=v1.0.0
```

### Defaults and customization

All of these are on by default and toggleable in
[main.bicepparam](../../infra/bicep/azlocal-js/main.bicepparam):

| Feature | Default | Parameter |
| --- | --- | --- |
| P30 disk performance tier (12 × 256 GB) | on | `host/host.bicep` `dataDiskPerformanceTier` |
| Windows 11 management jumpbox | on | `deployManagementVm` |
| Bastion + NAT Gateway (no public IP) | on | `deployBastion` |
| Auto-build the cluster after VM setup | on | `autoDeployClusterResource` |
| Auto-login to start the in-VM build | on | `vmAutologon` |
| Client VM size | `Standard_E64s_v6` | `vmSize` |
| Azure Hybrid Benefit | on | `host/host.bicep` `licenseType: 'Windows_Server'` · `mgmt/managementVm.bicep` `licenseType: 'Windows_Client'` |

> [!IMPORTANT]
> **Azure Hybrid Benefit (AHB)** is applied to both VMs to remove the per-core Windows
> licensing surcharge: `Windows_Server` on the `LocalBox-Client` host and `Windows_Client` on
> the Windows 11 jumpbox. Setting these asserts that you hold eligible licenses — Windows
> Server with active Software Assurance (or a qualifying subscription) for the host, and
> Windows 10/11 E3/E5 or Windows VDA per-user licenses for the jumpbox. If you are not
> entitled, remove the `licenseType` line(s) before you deploy. You can also update
> `licenseType` in place:
>
> ```bash
> az vm update -g rg-localbox -n LocalBox-Client --set licenseType=Windows_Server
> ```

Identity values (tenant ID and provider object ID) and the admin password are **never stored**
in the repo. `deploy.sh` resolves the GUIDs at runtime and reads the password from the
`LOCALBOX_ADMIN_PASSWORD` environment variable.

## 5. Let the in-VM build run

After the ARM deployment, the client VM runs `Bootstrap.ps1`, installs Hyper-V, and reboots.
Because `vmAutologon` is on by default, the VM then auto-logs-in as the admin user and the
cluster-build script starts on its own — you do **not** need to connect and sign in to start it.
The build runs for about 4–5 hours (add about an hour if Azure Local updates are available),
then the script window closes itself.

> [!NOTE]
> The `LocalBox-Client` VM is a standalone workgroup machine and is never domain-joined. The
> auto-logon uses the local admin account, so the logon domain is the VM's own computer name.
> The nested `jumpstart.local` Active Directory exists only inside the management VM
> (`AzLMGMT`) and never involves this host.

> [!WARNING]
> While `vmAutologon` is on, the admin password sits in the Winlogon registry in plaintext for
> the duration of the build. The logon script removes the auto-logon registry keys
> (`AutoAdminLogon`, `DefaultUserName`, `DefaultPassword`, `DefaultDomainName`) as soon as the
> build completes. To disable auto-login entirely, deploy with `-p vmAutologon=false` — but
> then you must connect and sign in once to start the build.

### What the build downloads from Microsoft

The orchestration is fully vendored in this repo — the Bicep templates and the entire in-VM
`artifacts/` tree — so there is no `microsoft/azure_arc` dependency at deploy time. A few large
or Microsoft-owned binaries are fetched from their official sources at build time:

- Azure Local and Windows Server **OS VHDX images** (multi-GB, from Microsoft blob storage).
- **PowerShell 7** and **Windows Admin Center** installers (official Microsoft URLs).
- The desktop **wallpaper** image (from `Azure/arc_jumpstart_docs`).

## 6. Monitor the cluster build

The ARM deployment finishes in about 18 minutes, but the nested cluster then builds inside the
VM for 2–4 hours with no Azure-visible deployment state. Track it from outside the VM, with no
sign-in:

```bash
./scripts/monitor.sh                 # poll until a terminal state
./scripts/monitor.sh --once          # one snapshot and exit
./scripts/monitor.sh --once --logs   # snapshot plus tail of the in-VM log
```

`monitor.sh` reads three independent signals without Bastion or RDP: the `DeploymentProgress`
and `DeploymentStatus` resource-group tags that the in-VM scripts emit at each milestone, the
`Microsoft.AzureStackHCI/clusters` resource (authoritative proof the cluster formed), and —
with `--logs` — a live tail of `C:\LocalBox\Logs` through `az vm run-command`.

The build has succeeded when the `Microsoft.AzureStackHCI/clusters` resource reaches
`provisioningState = Succeeded` (or the `DeploymentProgress` tag becomes `Completed`).

## 7. Connect to the environment

Once the cluster is up, connect over **Azure Bastion** in the portal — the client VM has no
public IP. You can Bastion into either `LocalBox-Client` or the Windows 11 jumpbox
(`LocalBox-Mgmt`). Windows Admin Center runs inside the nested `AzLMGMT` host.

## 8. Clean up

Disks, Bastion, and NAT bill even when the VM is deallocated. To stop **all** charges, delete
the resource group:

```bash
az group delete --name rg-localbox --yes
```

To pause more cheaply without losing state, deallocate the VMs instead — but disks, Bastion,
and NAT keep billing (about a $1,500/month floor). See [LocalBox sizing and cost](sizing.md)
for the cost-control scenarios.

## Next steps

- Understand the sizing and cost: [LocalBox sizing and cost](sizing.md).
- Resolve a failed deploy or build: [LocalBox troubleshooting](troubleshooting.md).
- Evaluate the lighter edge profile instead: [SFF quickstart](../sff/quickstart.md).

---

[Documentation home](../README.md) · [LocalBox overview](overview.md) · [Glossary](../glossary.md)
