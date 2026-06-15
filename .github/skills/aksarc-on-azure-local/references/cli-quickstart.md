# AKS on Azure Local — Azure CLI quickstart cheat-sheet

> Grounded in the vendored Microsoft docs under [docs/upstream/aksarc/](../../../../docs/upstream/aksarc/),
> chiefly [aks-create-clusters-cli.md](../../../../docs/upstream/aksarc/aks-create-clusters-cli.md).
> Treat Microsoft Learn as canonical when the weekly mirror lags. Run these from a **client machine**,
> not an Azure Local node.

## 1. Install the Azure CLI extensions

```azurecli
az extension add -n aksarc --upgrade
az extension add -n customlocation --upgrade
az extension add -n stack-hci-vm --upgrade
az extension add -n connectedk8s --upgrade
```

## 2. Create the cluster

`--validate` first to check inputs, then re-run without it to create. `--generate-ssh-keys` is
required when no SSH key exists locally (save the private key for node access/log collection).

```azurecli
az aksarc create -n $aksclustername -g $resource_group --custom-location $customlocationID --vnet-ids $logicnetId --aad-admin-group-object-ids $aadgroupID --generate-ssh-keys
```

> Azure RBAC and workload identity must be set **at create time** — they cannot be enabled on an
> existing cluster. See `azure-rbac-local.md` / `workload-identity.md` in the upstream docs.

## 3. Connect (proxy + kubeconfig)

Keep the proxy running; open a second terminal for `kubectl`.

```azurecli
az connectedk8s proxy --name $aksclustername --resource-group $resource_group --file .\aks-arc-kube-config
```

```azurecli
kubectl get node -A --kubeconfig .\aks-arc-kube-config
```

## 4. Node pools

```azurecli
# Add a node pool (labels optional)
az aksarc nodepool add --resource-group myResourceGroup --cluster-name myAKSCluster --name labelnp --node-count 1 --labels dept=HR

# Add a GPU node pool (Linux)
az aksarc nodepool add --cluster-name <aks cluster name> -n <node pool name> -g <resource group name> --node-count 2 --node-vm-size Standard_NC4_A2 --os-type Linux

# Add a node pool with a taint
az aksarc nodepool add --cluster-name myAKSCluster --resource-group myResourceGroup --name taintnp --node-taints sku=gpu:NoSchedule

# List node pools
az aksarc nodepool list -g myResourceGroup --cluster-name myAKSCluster
```

## 5. Delete the cluster

```azurecli
az aksarc delete --name $aksclustername --resource-group $resource_group
```

## Related

- Cluster lifecycle (scale/upgrade), networking, storage, security: see the
  [aksarc-on-azure-local](../SKILL.md) Reference Index.
- IaC alternative: this repo ships an AKS-on-bare-metal Bicep deployment at
  [infra/bicep/aks-baremetal/](../../../../infra/bicep/aks-baremetal/)
  ([quickstart](../../../../docs/sff/aks-baremetal.md)); upstream Bicep cluster templates live in
  the [Azure/aksArc](https://github.com/Azure/aksArc/tree/main/deploymentTemplates/aksarc-bicep-azlocal/Cluster) repo.
