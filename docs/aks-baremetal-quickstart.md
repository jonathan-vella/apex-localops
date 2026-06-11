# AKS on bare metal (preview) — Quickstart

Deploy a single-node **Azure Kubernetes Service (AKS) on bare metal** cluster onto the
Arc-enabled **Small Form Factor (SFF)** machine produced by the [SFF profile](sff-quickstart.md).
AKS on bare metal runs Kubernetes **directly on the device — no hypervisor** — and is managed
through the same Azure plane (ARM/Bicep/portal) as AKS everywhere else.

> [!IMPORTANT]
> AKS on bare metal is in **PREVIEW**: **East US only**, **single-node**, **Cilium** CNI.
> The Kubernetes version is a **date-suffixed** string (e.g. `1.34.3-20260204`) — check the
> [create-cluster doc](https://learn.microsoft.com/azure/aks/aksarc/aks-bare-metal-create-cluster-bicep)
> for current values. Cluster resources are **zero-rated** during preview (the underlying
> Arc machine and any Azure services still bill). Not for production.

## Where this fits

```mermaid
flowchart LR
    A["SFF host builds<br/>nested ROE test VM<br/>(deploy-sff.sh)"] --> B["Operator provisions<br/>the machine via portal<br/>(sff-runbook.md)"]
    B --> C["Arc-enabled SFF<br/>EdgeMachine (Provisioned)"]
    C --> D["AKS on bare metal<br/>(deploy-aks-baremetal.sh)<br/>auto-creates DevicePool<br/>+ custom location"]
    D --> E["kubectl via Arc proxy<br/>(connect-aks-baremetal.sh)"]
end
```

The cluster is a **separate, post-provisioning deployment** because it needs the
**Provisioned EdgeMachine** (and a **control-plane IP**) that only exist once the SFF
machine is provisioned. The deploy **auto-creates the DevicePool and custom location**,
and the cluster resources are created **in the same resource group as the EdgeMachine**.

## Prerequisites

1. A **Provisioned** SFF edge machine (complete [sff-runbook.md](sff-runbook.md) §1–4).
2. **Owner**, or **Contributor + User Access Administrator**, on the resource group
   (Active + Permanent).
3. Providers registered — already handled by
   [check-providers-sff.sh](../scripts/check-providers-sff.sh) (`Microsoft.HybridContainerService`,
   `Microsoft.Kubernetes`, `Microsoft.KubernetesConfiguration`, `Microsoft.ExtendedLocation`,
   `Microsoft.HybridCompute`, `Microsoft.AzureStackHCI`).
4. The `connectedk8s` CLI extension (the deploy script installs it if missing).
5. A Microsoft **Entra security group** for cluster admins — **auto-created** by the deploy
   (idempotent: an existing same-named group is reused). Pass `--admin-group-name` to choose
   the name, or `--admin-group <object-id>` to use a specific existing group. Requires
   directory permission to create groups, otherwise supply an existing one.
6. An **SSH public key** (e.g. `~/.ssh/id_rsa.pub`).

## Gather the inputs

| Input | How to get it |
| --- | --- |
| **Edge machine name** | `az resource list --resource-type Microsoft.AzureStackHCI/edgeMachines -o table`. The cluster deploys into the **same resource group** as this machine. |
| **Control plane IP** | A free IP in the **same subnet** as the edge machine, **not** the machine's own IP. If the machine uses DHCP, **reserve** it so it never changes. |
| **Admin group** | Auto-created/reused (`ensure-admin-group.sh`). Override with `--admin-group-name` or `--admin-group <object-id>`. |
| **SSH public key** | `cat ~/.ssh/id_rsa.pub` (the deploy script reads this by default). |

Export them (kept out of the committed params; resolved at deploy time):

```bash
export AKSBM_EDGE_MACHINE_NAME="<edge-machine-name>"
export AKSBM_CONTROL_PLANE_IP="192.168.200.50"
# Admin group is auto-created; set this only to use a specific existing group:
# export AKSBM_ADMIN_GROUP_ID="<entra-group-object-id>"
# SSH key is read from ~/.ssh/id_rsa.pub automatically, or:
export AKSBM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
# Optional: container monitoring (skipped when unset):
# export AKSBM_LOG_ANALYTICS_WORKSPACE_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>"
# Optional: override the Kubernetes version:
# export AKSBM_KUBERNETES_VERSION="1.34.3-20260204"
```

## Deploy

```bash
./scripts/deploy-aks-baremetal.sh
```

The script installs `connectedk8s` if needed, runs preflight (region, input shape, providers,
custom-location resolution), previews with `what-if`, deploys, and prints the connect command.
Deployment takes **~20 minutes**.

Useful flags:

```bash
./scripts/deploy-aks-baremetal.sh --what-if-only          # preview only
./scripts/deploy-aks-baremetal.sh --ssh-key-file ~/.ssh/id_ed25519.pub
./scripts/deploy-aks-baremetal.sh -g rg-azlocal-sff-eus01 -l eastus
```

## Connect

Run from your **local machine / devcontainer** (not Cloud Shell — the proxy needs a local
token audience):

```bash
./scripts/connect-aks-baremetal.sh --name localsff-aks --resource-group rg-azlocal-sff-eus01 --get-nodes
```

That starts the Arc proxy, runs `kubectl get nodes`, and stops the proxy. Expected:

```
NAME            STATUS   ROLES           AGE   VERSION
localsff-aks    Ready    control-plane   1d    v1.34.3
```

For an interactive session, omit `--get-nodes` — it starts the proxy in the foreground; run
`kubectl` from a second terminal.

## Deploy a sample app

Once the cluster is up, deploy a sample nginx workload to verify it end-to-end:

```bash
./scripts/deploy-aks-sample-app.sh --name localsff-aks -g rg-azlocal-sff-eus01 --host-ip 192.168.200.50
```

It starts the Arc proxy, applies [artifacts/aks/sample-app/hello-app.yaml](../artifacts/aks/sample-app/hello-app.yaml)
(a Deployment + **NodePort** Service), waits for the rollout, and prints the access URL:

```
Sample app 'hello-app' is running on 'localsff-aks'.
  Service type : NodePort
  NodePort     : 31234
  Access URL   : http://192.168.200.50:31234
```

Browse to `http://<bare-metal-host-ip>:<nodeport>` from a machine on the device's network.
Remove it with `./scripts/deploy-aks-sample-app.sh --delete`.

### Single-node best practices (baked into the manifest)

- **NodePort, not LoadBalancer** — the `LoadBalancer` service type is **not supported** during
  the preview.
- **Set resource requests/limits** on every workload so it cannot starve the control plane.
  Reserve roughly **2 GB RAM + 1 CPU core** for the Kubernetes control plane on the single node.
- **Pull images from MCR** (`mcr.microsoft.com`) — the registry guaranteed reachable from the device.

### Troubleshooting

| Symptom | Fix |
| --- | --- |
| Pod stuck in `ErrImagePull` | Confirm the device can reach `mcr.microsoft.com`; check DNS and firewall rules. |
| Pod stuck in `Pending` | Check node resources: `kubectl describe node` — look for CPU/memory pressure. |
| Service not reachable | Verify the correct **NodePort + host IP**, and that the firewall allows the port. |
| `context deadline exceeded` on kubectl | The Arc proxy isn't running — start it (`connect-aks-baremetal.sh`) in another terminal. |

## What gets deployed

Mirrors the upstream `Azure/aksArc` Bicep template (portal-parity), in order:

| Resource | Role |
| --- | --- |
| `Microsoft.AzureStackHCI/devicePools` | Binds the EdgeMachine to a CMP instance; the HCI RP **auto-creates the custom location** during its provisioning |
| `Microsoft.Authorization/roleAssignments` (×2) | DevicePool MSI → Device Pool Manager (on the pool) + Edge Machine Contributor (on the machine), for CAPE operations |
| `Microsoft.AzureStackHCI/logicalNetworks` | **Placeholder** required by the provisioned-cluster webhook; not used for networking |
| `Microsoft.Kubernetes/connectedClusters` (kind `ProvisionedCluster`) | Arc projection; carries identity + the Entra admin group (Azure RBAC for Kubernetes) |
| `Microsoft.HybridContainerService/provisionedClusterInstances` (`default`) | The actual single-node cluster, pinned to the machine via `extendedLocation` (custom location) |
| `Microsoft.KubernetesConfiguration/extensions` (×2, optional) | Azure Policy + Container Monitoring (the latter only when a Log Analytics workspace is supplied) |

Template: [infra/bicep/aks-baremetal/main.bicep](../infra/bicep/aks-baremetal/main.bicep).
Defaults (overridable in [main.bicepparam](../infra/bicep/aks-baremetal/main.bicepparam)):
single control-plane node, Cilium, pod CIDR `10.244.0.0/16`, Azure Policy on, Container
Monitoring on (skipped without a workspace id).

## Clean up

The cluster resources live in the **same resource group as the SFF machine**, so do **NOT**
delete the whole resource group (that would also destroy the SFF host). Remove just the
cluster resources:

```bash
RG=rg-azlocal-sff-eus01
CL=localsff-aks
# Deleting the connected cluster removes its child provisioned-cluster instance too.
az resource delete -g "$RG" -n "$CL" --resource-type Microsoft.Kubernetes/connectedClusters
az resource delete -g "$RG" -n "$CL-lnet" --resource-type Microsoft.AzureStackHCI/logicalNetworks
az resource delete -g "$RG" -n "<edge-machine-name>" --resource-type Microsoft.AzureStackHCI/devicePools
```

Cluster resources are zero-rated in preview. The SFF resource group (`rg-azlocal-sff-eus01`) and its
host VM remain untouched.

## Preview-volatility note

The preview API versions are centralized at the top of
[main.bicep](../infra/bicep/aks-baremetal/main.bicep) (`devicePools`/`edgeMachines`
`2024-11-01-preview`, `logicalNetworks` `2024-09-01-preview`, `connectedClusters`
`2024-01-01`, `provisionedClusterInstances` `2024-09-01-preview`, `extensions`
`2023-05-01`). The template mirrors the upstream
[Azure/aksArc Bicep template](https://github.com/Azure/aksArc/tree/main/deploymentTemplates/aks-baremetal-bicep);
if a preview revision changes the contract, bump the versions there. Canonical docs are on
[Microsoft Learn](https://learn.microsoft.com/azure/aks/aksarc/aks-bare-metal-create-cluster-bicep)
(the AKS bare metal preview docs are not yet mirrored to a public GitHub repo, so unlike the
SFF docs they are not vendored here — refer to Learn directly).
