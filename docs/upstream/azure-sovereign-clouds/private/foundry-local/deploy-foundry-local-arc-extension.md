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
ms.date: 06/10/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to deploy Foundry Local as an Azure Arc extension so that I can run AI inference workloads on my Azure Arc–enabled Kubernetes cluster.
---

# Deploy Foundry Local as an Azure Arc extension

This article shows you how to set up Foundry Local as an extension on your Azure Kubernetes Service (AKS) cluster enabled by Azure Arc. Use the Azure portal or the Azure CLI to deploy Foundry Local as an extension on your Azure Arc-enabled Kubernetes cluster. Helm is also a supported deployment option, and installation instructions are provided during preview access onboarding.

If you plan to use models with [Agentic Retrieval in Foundry Local](/azure/azure-arc/edge-rag/overview), Entra ID authentication must remain enabled (the default) during this extension installation.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, make sure you have:

- Access to Foundry Local preview: Foundry Local on Azure Local is available by request during preview. Submit an access request at [aka.ms/FoundryLocalAzure_PreviewRequest](https://aka.ms/FoundryLocalAzure_PreviewRequest).
- A Kubernetes cluster (version 1.29 or later) connected to Azure Arc. For more information, see [Azure Arc–enabled Kubernetes](/azure/azure-arc/kubernetes/overview).
- Your Azure Arc-enabled Kubernetes cluster is located in a supported region. For available regions, see [Supported regions](overview.md#supported-regions).
- An app registration for enablement of authorization and authentication. See [Configure authentication for Foundry Local enabled by Azure Arc](how-to-configure-authentication.md).
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed and configured for your cluster.
- [Helm](https://helm.sh/) installed.
- For external endpoints: an NGINX ingress controller, such as [NGINX-Ingress](https://github.com/kubernetes/ingress-nginx).
- (Optional) A namespace strategy if you plan to deploy models outside the default `foundry-local-operator` namespace. You must set namespace configuration during installation. For more information, see [Namespace configuration for model deployments](concept-inference-operator.md#namespace-configuration-for-model-deployments).

> [!IMPORTANT]
> [Ingress-NGINX](https://github.com/kubernetes/ingress-nginx) is deprecated since March 2026. Microsoft currently supports NGINX annotations. The solution is tested with AKS's managed NGINX ingress controller.

### GPU prerequisites

If you plan to run GPU workloads, also make sure:

- Your cluster has NVIDIA GPU nodes with CUDA drivers installed on the nodes.
- The Kubernetes device plugin for NVIDIA is configured so the cluster can schedule GPU workloads.

For more information, see [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html).

## Step 1: Install cert-manager and trust-manager

Foundry Local on Azure Local requires cert-manager and trust-manager for automated certificate management.

Use the Azure CLI to create the cert-manager extension on your cluster. Choose the appropriate command for your shell environment:

#### [Bash](#tab/bash)

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

#### [PowerShell](#tab/powershell)

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

## Step 2: Install the Foundry Local extension

Install the Foundry Local extension by using the Azure portal or Azure CLI. Entra ID authentication is enabled by default. If you plan to use [Agentic Retrieval in Foundry Local](/azure/azure-arc/edge-rag/overview) later, keep this default during installation and include the Entra application ID. If you disable Entra ID authentication, you prevent Agentic Retrieval from connecting to your deployed models.

### Option 1: Command line

Use the Azure CLI in Bash or PowerShell to install the extension.

#### [Bash](#tab/bash)

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

#### [PowerShell](#tab/powershell)

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

**Additional installation parameters**

You can configure the following optional parameters during inference operator installation:

| Parameter | Description |
|-----------|-------------|
| `entraAuth.enabled` | Boolean. When enabled, the Entra Auth SDK sidecar and msi-adapter sidecar are injected into inference pods for JWT validation and ARM RBAC authorization. When disabled, `entraAuth.tenantId` and `entraAuth.clientId` parameters are optional. Default: `true`. For more information, see [Configure authentication for Foundry Local enabled by Azure Arc](how-to-configure-authentication.md). If you intend to use [Agentic Retrieval in Foundry Local](/azure/azure-arc/edge-rag/overview) later, you must enable Entra ID authentication for the Foundry Local extension.|
| `watch.namespaces` | Array of strings. Configure this parameter if you want the operator to manage resources across multiple namespaces. By default, the operator manages the `foundry-local-operator` namespace where models and inference workloads are deployed. Pass the installation command as: `--config watch.namespaces[0]="NS1" --config watch.namespaces[1]="NS2"`. For more information, see [Namespace configuration for model deployments](concept-inference-operator.md#namespace-configuration-for-model-deployments). |

### Option 2: Azure portal

Use the Azure portal to install the Foundry Local extension and configure required settings for your Arc-enabled Kubernetes cluster.

1. In the [Azure portal](https://portal.azure.com/), go to your Azure Arc–enabled Kubernetes cluster on Azure Local.
1. Select **Settings** > **Extensions** > **+ Add**.
1. From the list of available extensions, select **Foundry Local on Azure Local (Preview)**.
1. Select **Create**.
1. On the **Basics** tab, provide the following information:

   | Field | Value |
   |---|---|
   | Subscription | Select the subscription that contains your Arc–enabled Kubernetes cluster. |
   | Resource group | Select the resource group that contains your Azure Arc cluster. |
   | Region | Select the region where you want to deploy the extension. |
   | Connected K8S cluster | Select your Arc–enabled Kubernetes cluster. |
   | Extension name | Provide a name for the extension (for example, `foundry`). |

   :::image type="content" source="media/deploy-foundry-local-arc-extension/foundry-local-extension-basics.png" alt-text="Screenshot of the Basics tab where you select the subscription, resource group, region, connected cluster, and extension name.":::

1. Select **Next**.
1. On the **Configuration** tab, provide the following information:

   | Field | Value |
   |---|---|
   | Microsoft Entra ID | Choose **Enabled** or **Disabled**. When enabled, you must provide the Entra application ID for authentication. |
   | Entra application ID | Required only when Microsoft Entra ID is enabled. Enter the application ID from your enterprise application registration. |
   | Kubernetes namespaces | Optional. Enter a comma-separated list of Kubernetes namespaces where you want to allow model deployments. If left empty, models deploy only to the `foundry-local-operator` namespace. |

   :::image type="content" source="media/deploy-foundry-local-arc-extension/foundry-local-extension-configuration.png" alt-text="Screenshot of the Configuration tab where you enable Microsoft Entra ID and optionally specify Kubernetes namespaces for model deployments.":::

1. Select **Review + Create**.
1. Review and validate the parameters you provided.
1. Select **Create** to deploy the Foundry Local extension.
1. After the deployment completes, under **Extensions**, verify that the extension state is **Succeeded**.

## Step 3: Verify the operator

Verify that the inference operator extension is installed and that all pods are running. Use the following commands to check the operator status:

#### [Bash](#tab/bash)

```bash
kubectl get pods -n foundry-local-operator
kubectl get crd | grep foundry
```

#### [PowerShell](#tab/powershell)

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