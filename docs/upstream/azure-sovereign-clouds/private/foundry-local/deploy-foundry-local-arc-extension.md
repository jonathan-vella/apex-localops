---
title: "Deploy Foundry Local as an Azure Arc extension"
description: "Install cert-manager, trust-manager, and the Foundry inference operator as an Azure Arc extension on your Azure Kubernetes Service (AKS) cluster enabled by Azure Arc."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 04/30/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to deploy Foundry Local as an Azure Arc extension so that I can run AI inference workloads on my Azure Arc–enabled Kubernetes cluster.
---

# Deploy Foundry Local as an Azure Arc extension

This article shows you how to set up Foundry Local as an extension on your Azure Kubernetes Service (AKS) cluster enabled by Azure Arc. Use the Azure CLI to deploy Foundry Local as an extension on your Azure Arc-enabled Kubernetes cluster. Helm is also a supported deployment option, and installation instructions are provided during preview access onboarding.

If you plan to use models with [Agentic Retrieval in Foundry Local](/azure/azure-arc/edge-rag/overview), Entra ID authentication must remain enabled (the default) during this extension installation.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, make sure you have:

- Access to Foundry Local preview: Foundry Local on Azure Local is available by request during preview. Submit an access request at [aka.ms/FoundryLocalAzure_PreviewRequest](https://aka.ms/FoundryLocalAzure_PreviewRequest). After approval, you'll receive guidance on next steps for deployment.
- A Kubernetes cluster (version 1.29 or later) connected to Azure Arc. For more information, see [Azure Arc–enabled Kubernetes](/azure/azure-arc/kubernetes/overview).
- Your Azure Arc-enabled Kubernetes cluster is located in a supported region. For available regions, see [Supported regions](overview.md#supported-regions).
- An app registration for enablement of authorization and authentication. See [Configure authentication for Foundry Local enabled by Azure Arc](how-to-configure-authentication.md).
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed and configured for your cluster.
- [Helm](https://helm.sh/) installed.
- For external endpoints: an NGINX ingress controller, such as [NGINX-Ingress](https://github.com/kubernetes/ingress-nginx).
- (Optional) A namespace strategy if you plan to deploy models outside the default `foundry-local-operator` namespace. Namespace configuration must be set during installation. For more information, see [Namespace configuration for model deployments](concept-inference-operator.md#namespace-configuration-for-model-deployments).

> [!IMPORTANT]
> [Ingress-NGINX](https://github.com/kubernetes/ingress-nginx) is deprecated since March 2026. Microsoft currently supports NGINX annotations. The solution is tested with AKS's managed NGINX ingress controller.

### GPU prerequisites

If you plan to run GPU workloads, also make sure:

- NVIDIA GPU nodes are available in your cluster with CUDA drivers installed on the nodes.
- The Kubernetes device plugin for NVIDIA is configured so the cluster can schedule GPU workloads.

For more information, see [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html).

## Step 1: Install cert-manager and trust-manager

Foundry Local on Azure Local requires cert-manager and trust-manager for automated certificate management.

Use the Azure CLI to create the cert-manager extension on your cluster. Choose the appropriate command for your shell environment:

#### [Bash](#tab/install-bash)

```bash
az k8s-extension create \
    --cluster-name <your_arc_cluster_name> \
    --name "azure-cert-manager" \
    --resource-group <resource_group_of_the_arc_cluster> \
    --cluster-type connectedClusters \
    --extension-type Microsoft.CertManagement \
    --scope cluster \
    --release-train stable \
    --config config.enableGatewayAPI=true \
    --config cert-manager.crds.keep=true \
    --config trust-manager.defaultPackage.enabled=false \
    --config trust-manager.secretTargets.enabled=true \
    --config trust-manager.secretTargets.authorizedSecretsAll=true
```

#### [PowerShell](#tab/install-powershell)

```powershell
az k8s-extension create `
    --cluster-name <your_arc_cluster_name> `
    --name "azure-cert-manager" `
    --resource-group <resource_group_of_the_arc_cluster> `
    --cluster-type connectedClusters `
    --extension-type Microsoft.CertManagement `
    --scope cluster `
    --release-train stable `
    --config config.enableGatewayAPI=true `
    --config cert-manager.crds.keep=true `
    --config trust-manager.defaultPackage.enabled=false `
    --config trust-manager.secretTargets.enabled=true `
    --config trust-manager.secretTargets.authorizedSecretsAll=true
```

---

## Step 2: Install the inference operator

Use the Azure CLI to deploy the inference operator extension. Choose the appropriate command for your shell environment:

#### [Bash](#tab/operator-bash)

```bash
az k8s-extension create \
    --resource-group <resource_group_of_the_arc_cluster> \
    --cluster-name <arc_cluster_name> \
    --name "inference-operator" \
    --extension-type Microsoft.Foundry \
    --scope cluster \
    --release-namespace "foundry-local-operator" \
    --cluster-type connectedClusters \
    --auto-upgrade-minor-version true \
    --release-train stable \
    --config entraAuth.tenantId="<azure_tenant_id>" \
    --config entraAuth.clientId="<the_client_id_of_the_app_registration>"
```

#### [PowerShell](#tab/operator-powershell)

```powershell
az k8s-extension create `
    --resource-group <resource_group_of_the_arc_cluster> `
    --cluster-name <arc_cluster_name> `
    --name "inference-operator" `
    --extension-type Microsoft.Foundry `
    --scope cluster `
    --release-namespace "foundry-local-operator" `
    --cluster-type connectedClusters `
    --auto-upgrade-minor-version true `
    --release-train stable `
    --config entraAuth.tenantId="<azure_tenant_id>" `
    --config entraAuth.clientId="<the_client_id_of_the_app_registration>"
```

---

### Additional installation parameters

Entra ID authentication is enabled by default. If you intend to use [Agentic Retrieval in Foundry Local](/azure/azure-arc/edge-rag/overview) later, keep `entraAuth.enabled` set to `true` (the default) during installation. Disabling Entra ID authentication prevents agentic retrieval from connecting to your deployed models.

You can configure the following optional parameters during inference operator installation:

| Parameter | Description |
|-----------|-------------|
| `entraAuth.enabled` | Boolean. When enabled, the Entra Auth SDK sidecar and msi-adapter sidecar are injected into inference pods for JWT validation and ARM RBAC authorization. When disabled, `entraAuth.tenantId` and `entraAuth.clientId` parameters are optional. Default: `true`. For more information, see [Configure authentication for Foundry Local enabled by Azure Arc](how-to-configure-authentication.md). |
| `watch.namespaces` | Array of strings. Configure this parameter if you want the operator to manage resources across multiple namespaces. By default, the operator manages the `foundry-local-operator` namespace where models and inference workloads are deployed. Pass the installation command as: `--config watch.namespaces[0]="NS1" --config watch.namespaces[1]="NS2"`. For more information, see [Namespace configuration for model deployments](concept-inference-operator.md#namespace-configuration-for-model-deployments). |

## Step 3: Verify the operator

Verify that the inference operator extension is installed and that all pods are running. Use the following commands to check the operator status:

#### [Bash](#tab/verify-bash)

```bash
kubectl get pods -n foundry-local-operator
kubectl get crd | grep foundry
```

#### [PowerShell](#tab/verify-powershell)

```powershell
kubectl get pods -n foundry-local-operator
kubectl get crd | Select-String -Pattern "foundry"
```

---

Wait until all pods show a `Running` status before you proceed.

The following screenshots show an example of the expected output:

:::image type="content" source="media/deploy-foundry-local-arc-extension/verify-operator-pods.png" alt-text="Screenshot of terminal output from kubectl get pods command showing five pods in the foundry-local-operator namespace with Running or Completed status.":::

:::image type="content" source="media/deploy-foundry-local-arc-extension/verify-operator-custom-resource-definitions.png" alt-text="Screenshot of terminal output from kubectl get crd command showing four Foundry Local custom resource definitions registered in the cluster.":::

## Troubleshoot your deployment

Use the following commands to troubleshoot issues with your deployment.

Check ModelDeployment status and events:

```bash
kubectl describe mdep <name>
```

Check operator logs:

```bash
kubectl logs -f deployment/inference-operator -n foundry-local-operator
```

Check pod status:

```bash
kubectl get pods -l app.kubernetes.io/managed-by=inference-operator
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

List all resources created by a deployment:

```bash
kubectl get deploy,svc,ing -l foundry.azure.com/deployment=<name>
```

Check the catalog ConfigMap:

```bash
kubectl get configmap foundry-local-catalog -n foundry-local-operator -o yaml
```

Verify a Model CR exists:

```bash
kubectl get models
kubectl describe model <name>
```

## Next step

> [!div class="nextstepaction"]
> [Deploy your first model and run inference](deploy-run-first-model.md)

## Related content

- [Package and deploy a bring-your-own model on Foundry Local](how-to-deploy-custom-model.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [Update the Foundry Local Azure Arc extension in connected environments](how-to-update-arc-extension.md)