# Self-hosted end-to-end runbook

[Documentation home](../README.md) / Self-hosted / Runbook

One continuous path: empty subscription → a 3-node Azure Local cluster → workloads running on
it → back to $0. Each phase is a checkpoint you can stop at.

| Phase | What you get | Time |
| --- | --- | --- |
| [1. Build the cluster](#phase-1--build-the-cluster) | A `Succeeded` + `Connected` Azure Local instance | ~4 h (mostly unattended) |
| [2. Deploy workloads](#phase-2--deploy-workloads) | VMs, SQL, AVD, AKS + a sample app | ~1–3 h |
| [3. Verify](#phase-3--verify) | Evidence that each piece works | ~10 min |
| [4. Tear down](#phase-4--tear-down) | $0 | ~15 min |

> [!IMPORTANT]
> Every name and region below is an **example from the reference lab, not a requirement**.
> `rg-apexlocal`, `swedencentral`, `canadacentral`, `apexlocal.local` and the VM names are
> defaults you should change for your own subscription. See
> [Customize for your environment](#customize-for-your-environment).

## In this guide

- [Before you start](#before-you-start)
- [Customize for your environment](#customize-for-your-environment)
- [Phase 1 — Build the cluster](#phase-1--build-the-cluster)
- [Phase 2 — Deploy workloads](#phase-2--deploy-workloads)
- [Phase 3 — Verify](#phase-3--verify)
- [Phase 4 — Tear down](#phase-4--tear-down)
- [Troubleshooting](#troubleshooting)

## Before you start

| Requirement | Detail |
| --- | --- |
| Azure role | **Owner** on the subscription (the deployment creates role assignments; Contributor alone fails) |
| Quota | **64 vCPUs** of `standardESv6Family` in the infrastructure region |
| Tools | Azure CLI 2.65+ with Bicep, and `az login`. The dev container has everything |
| Licences | You accept the Azure Local and Windows Server evaluation terms (passed as explicit flags) |
| Cost | The host, its 8 Premium disks, Bastion, and NAT Gateway bill continuously — see [sizing](sizing.md) |

Preflight checks all of the above **before** creating any billable resource, and fails with the
exact blocker.

Store the lab password once. Every script reads `LOCALSELF_ADMIN_PASSWORD` first, then this
git-ignored file, so nothing has to be retyped or committed:

```bash
mkdir -p ~/.apex-localops
printf '%s' '<approved-lab-password>' > ~/.apex-localops/admin-password
chmod 600 ~/.apex-localops/admin-password
```

The same password becomes the local VM administrator and the domain join account. It must be
12–123 characters and must not contain `$`.

## Customize for your environment

| Flag / setting | Reference value | Yours |
| --- | --- | --- |
| `--resource-group` | `rg-apexlocal` | any new or empty resource group |
| `--location` | `swedencentral` | `swedencentral` or `germanywestcentral` (infrastructure) |
| `--cluster-name` | `apexlocal` | 3–15 characters |
| `--azure-local-location` | `canadacentral` | a supported Azure Local region |
| Domain, VM names, IPs | `apexlocal.local`, `apexws04`… | [Workloads-Config.psd1](../../artifacts/selfhosted/PowerShell/workloads/Workloads-Config.psd1) |

Deploying from a **fork**? Export `GITHUB_ACCOUNT` (and `GITHUB_REPO`) first so the in-VM
bootstrap pulls runtime artifacts from your fork instead of the upstream repo.

## Phase 1 — Build the cluster

Full detail, including what each step does, is in the
[Self-hosted quickstart](quickstart.md). The short path:

```bash
# 1. Register resource providers and resolve the Azure Local RP object id
./scripts/check-providers-selfhosted.sh

# 2. Deploy the infrastructure and stage both ISOs in one command
./scripts/deploy-selfhosted.sh --resource-group rg-apexlocal \
  --location swedencentral --cluster-name apexlocal \
  --accept-azure-local-license-terms \
  --accept-windows-server-evaluation-terms

# 3. Watch the in-VM build (ARM finishes in ~20 min; the nested build takes hours)
./scripts/monitor-selfhosted.sh --resource-group rg-apexlocal
```

Phase 1 is complete when the cluster reports `Succeeded` and `Connected`:

```bash
az stack-hci cluster list -g rg-apexlocal \
  --query "[].{name:name, state:provisioningState, status:status}" -o table
```

If the build fails, it fails at a **named stage** and can be resumed from that stage instead of
rebuilt — see [Resume a failed build](quickstart.md#resume-a-failed-build-at-its-stage).

## Phase 2 — Deploy workloads

Everything here runs from your client through
[deploy-workloads-selfhosted.sh](../../scripts/deploy-workloads-selfhosted.sh). Every stage is
**idempotent** (re-running skips what already exists) and supports `--what-if` for a dry run.

```bash
./scripts/deploy-workloads-selfhosted.sh --stage <stage> [--what-if] [--yes]
```

> [!WARNING]
> **Check capacity first.** The nested pool is thin provisioned, so CSV "free space" is
> misleading — a volume can report hundreds of free GB while writes fail because the pool is
> full. A full pool shows up as VMs paused with `Disk(s) encountered critical IO errors`.
> Budget with [Nested storage capacity](sizing.md#nested-storage-capacity): every 1 GB of guest
> data costs **3 GB** of pool, and a VM built from the SQL or Win11 image costs ~380 GB.

### Step 1 — Marketplace images

```bash
./scripts/deploy-workloads-selfhosted.sh --stage images
./scripts/deploy-workloads-selfhosted.sh --stage wait     # poll until all report Succeeded
```

Each image downloads for 30–120 minutes. The WS2025 **smalldisk** image is 30 GB; the SQL 2022
and Win11 AVD images are 127 GB fixed VHDs, so skip the ones you do not need.

> [!NOTE]
> Three more stages exist that this walkthrough does not use: `prereqs` (register
> `Microsoft.EdgeMarketplace` and assign the Arc Resource Manager role), `insights` (Azure Local
> Insights via the monitoring agent and a data collection rule), and `all-vms` (a shortcut for
> `images` + `network` + `wait` + `ws2025`). Run the script with `--help` for the full list.

### Step 2 — Tenant logical network

```bash
./scripts/deploy-workloads-selfhosted.sh --stage network
```

Creates the VM and AKS logical networks on the domain controller's subnet, derived at runtime
from the cluster's own `*-InfraLNET`. Tenant NICs are not allowed on the InfraLNET itself, and a
tagged VLAN with no router interface cannot reach the DC or Azure — hence the derivation.

### Step 3 — Windows Server 2025 VMs

```bash
./scripts/deploy-workloads-selfhosted.sh --stage ws2025
```

Creates two domain-joined VMs. Creation and domain join are decoupled, so a slow Arc agent never
blocks the VM, and re-running only completes what is missing.

### Step 4 — SQL Server VM (optional)

```bash
./scripts/deploy-workloads-selfhosted.sh --stage sql
```

Adds a SQL 2022 VM with separate data and tempdb disks.

### Step 5 — Azure Virtual Desktop (optional)

```bash
./scripts/deploy-workloads-selfhosted.sh --stage avd-cp     # host pool, workspace, app group
./scripts/deploy-workloads-selfhosted.sh --stage avd-host   # session host + AVD agent
```

`avd-host` pulls the registration token automatically. To let people actually sign in, assign
them the **Desktop Virtualization User** role on the application group — the deployment
intentionally does not guess who should have access.

### Step 6 — AKS enabled by Azure Arc, plus a sample app

```bash
./scripts/deploy-workloads-selfhosted.sh --stage aks --yes
```

This stage creates the cluster (~30 min) and then bootstraps
[cluster-connect service-account token authentication](https://learn.microsoft.com/azure/azure-arc/kubernetes/cluster-connect#service-account-token-authentication-option),
storing the token in `~/.apex-localops/aks-token` (mode `0600`). That token matters: Kubernetes
admin via `--aad-admin-group-object-ids` can **only** be granted at cluster creation, and it
needs Entra directory permissions that many tenants withhold. The token has neither limitation.

Deploy the sample workload:

```bash
./scripts/deploy-aks-sample-app.sh --name apexlocal-aks -g rg-apexlocal
```

It opens the Arc proxy, applies a NodePort nginx Deployment, waits for the rollout, and prints
the access URL. Add `--host-ip <node-ip>` for a complete URL, or `--port 47051` if the default
proxy port is busy.

To use `kubectl` yourself, open the proxy with the stored token and keep it running in its own
shell:

```bash
az connectedk8s proxy -n apexlocal-aks -g rg-apexlocal \
  --file /tmp/aks.kubeconfig --token "$(cat ~/.apex-localops/aks-token)"
```

```bash
kubectl --kubeconfig /tmp/aks.kubeconfig get nodes
```

## Phase 3 — Verify

| What | Command | Expected |
| --- | --- | --- |
| Cluster | `az stack-hci cluster list -g rg-apexlocal -o table` | `Succeeded` / `Connected` |
| Images | `az stack-hci-vm image list -g rg-apexlocal -o table` | each `Succeeded` |
| VMs | `az stack-hci-vm list -g rg-apexlocal -o table` | one row per VM |
| Domain join | `az rest --method get --url ".../machines/<vm>/extensions/joindomain?api-version=2024-07-10"` | `Succeeded` |
| AVD session host | `az rest --method get --url ".../hostPools/<pool>/sessionHosts?api-version=2024-04-03"` | status `Available` |
| AKS cluster | `az aksarc show -g rg-apexlocal -n apexlocal-aks` | `provisioningState: Succeeded` |
| AKS nodes | `kubectl --kubeconfig /tmp/aks.kubeconfig get nodes` | all `Ready` |
| Sample app | `curl http://<node-ip>:<nodeport>/` | `HTTP 200` |

Validate the AKS token itself — this proves the **token** authenticated, not your own identity:

```bash
kubectl --kubeconfig /tmp/aks.kubeconfig auth whoami
```

Expect `system:serviceaccount:default:apex-cluster-connect`. `Unauthorized` means a bad token;
`Forbidden` means it authenticated but has no rights.

Storage headroom is worth checking before adding more workloads. Query the **pool**, never the
volume:

```powershell
$pool = Get-StoragePool | Where-Object { -not $_.IsPrimordial }
'pool free GB: ' + [math]::Round(($pool.Size - $pool.AllocatedSize) / 1GB)
```

## Phase 4 — Tear down

Work from the smallest blast radius outwards. **Only deleting the resource group reaches $0** —
deallocating the host still leaves disks, Bastion, and the NAT Gateway billing.

Remove just the sample app:

```bash
./scripts/deploy-aks-sample-app.sh --delete --name apexlocal-aks -g rg-apexlocal
```

Remove the AKS cluster (frees the most nested storage after the VMs):

```bash
az aksarc delete -g rg-apexlocal -n apexlocal-aks --yes
```

Remove individual workload VMs, their NICs, and any data disks. Deleting VMs through this API is
also what actually returns storage slabs to the pool — deleting images alone barely does:

```bash
az stack-hci-vm delete --name apexws04 -g rg-apexlocal --yes
az stack-hci-vm network nic delete --name apexws04-nic -g rg-apexlocal --yes
az stack-hci-vm disk delete --name apexsql01-data -g rg-apexlocal --yes
```

Delete everything and stop all billing:

```bash
./scripts/cleanup-selfhosted.sh --resource-group rg-apexlocal
```

It asks you to type the resource-group name to confirm (`--yes` skips that, `--no-wait` returns
immediately). Deleting the resource group also removes the Arc-projected Azure Local cluster and
node resources, and destroys the lab Key Vault holding the stored password.

Confirm nothing is left:

```bash
az group exists --name rg-apexlocal          # false
az stack-hci cluster list -o table           # no rows for this lab
```

> [!NOTE]
> Nested Azure Local can leave resources that ARM cannot delete on its own — for example a VM
> whose underlying `moc` state is wedged. Deleting the resource group still removes the billing,
> which is what matters for teardown.

## Troubleshooting

| Symptom | Likely cause | Where to look |
| --- | --- | --- |
| Preflight fails before anything deploys | Quota, region, providers, or a stale pinned image | [quickstart](quickstart.md#1-register-providers-and-resolve-the-rp-object-id) |
| Build stalls for hours | The nested build is genuinely slow; check the stage tag | `monitor-selfhosted.sh` |
| VM paused, `critical IO errors` | The Storage Spaces Direct **pool** is full | [sizing](sizing.md#nested-storage-capacity) |
| AKS create fails `APIServerNotOnline` | Control-plane VM never started — usually storage, not networking | [troubleshooting](troubleshooting.md) |
| `kubectl` returns `Forbidden` | No Kubernetes admin binding | Re-run `--stage aks` to mint a token |
| Domain join `Failed` | The Arc agent has not connected yet | Re-run the stage; it is idempotent |

Full evidence and recovery decision tables: [Self-hosted troubleshooting](troubleshooting.md).

## Next steps

- Plan capacity and cost before scaling up: [Self-hosted sizing and cost](sizing.md).
- Understand the topology and RBAC model: [Self-hosted overview](overview.md).
- Release gate and evidence schema: [Self-hosted validation](validation.md).

---

[Documentation home](../README.md) · [Self-hosted overview](overview.md) · [Glossary](../glossary.md)
