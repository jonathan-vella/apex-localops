---
title: "Deploy Foundry Local as an Azure Arc extension in a Disconnected Environment"
description: "Install cert-manager, trust-manager, and the Foundry inference operator as an Azure Arc extension on your Azure Kubernetes Service (AKS) cluster enabled by Azure Arc in a disconnected environment."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 05/31/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to deploy Foundry Local as an Azure Arc extension so that I can run AI inference workloads on my Azure Arc–enabled Kubernetes cluster in a disconnected environment.
---

# Deploy Foundry Local as an Azure Arc extension in a disconnected environment

This article shows you how to set up Foundry Local as an extension on your Azure Kubernetes Service (AKS) cluster enabled by Azure Arc in a disconnected environment. Use the Azure CLI to deploy Foundry Local as an extension on your Azure Arc-enabled Kubernetes cluster. Use Helm to install the required Kubernetes prerequisites.

[!INCLUDE [foundry-local-preview](../includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, complete the steps in [Prepare to deploy Foundry Local on Azure Local in disconnected environments](how-to-prepare.md) to fulfill prerequisites and download and import the Foundry Local expansion pack.

## Install required Kubernetes prerequisites (Cert-Manager and Trust-Manager)

The Foundry Local expansion pack includes Helm charts and container images for `cert-manager` and `trust-manager`.
You can install those charts directly from `edgeartifacts` Container Registry.

```powershell
# Define the edgeartifacts container registry endpoint.
# All Helm charts and container images are pulled from this local registry.
$edgeartifactsAcrPath = "edgeartifacts.edgeacr.autonomous.cloud.private"

# Install or upgrade cert-manager from the local registry.
# cert-manager provides certificate issuance and lifecycle management for Kubernetes workloads.
helm upgrade --install cert-manager `
  "oci://$edgeartifactsAcrPath/jetstack/charts/cert-manager" `
  --version v1.19.2 `
  --namespace cert-manager `
  --create-namespace `
  --set crds.enabled=true `
  --set crds.keep=true `
  --set image.repository=$edgeartifactsAcrPath/jetstack/cert-manager-controller `
  --set image.tag=v1.19.2 `
  --set webhook.image.repository=$edgeartifactsAcrPath/jetstack/cert-manager-webhook `
  --set webhook.image.tag=v1.19.2 `
  --set cainjector.image.repository=$edgeartifactsAcrPath/jetstack/cert-manager-cainjector `
  --set cainjector.image.tag=v1.19.2 `
  --set startupapicheck.image.repository=$edgeartifactsAcrPath/jetstack/cert-manager-startupapicheck `
  --set startupapicheck.image.tag=v1.19.2 `
  --wait

# Install or upgrade trust-manager from the local registry.
# trust-manager distributes trusted CA bundles across Kubernetes namespaces and workloads.
helm upgrade --install trust-manager `
  "oci://$edgeartifactsAcrPath/jetstack/charts/trust-manager" `
  --version v0.20.3 `
  --namespace cert-manager `
  --set image.repository=$edgeartifactsAcrPath/jetstack/trust-manager `
  --set image.tag=v0.20.3 `
  --set defaultPackage.enabled=false `
  --set defaultPackageImage.repository=$edgeartifactsAcrPath/jetstack/trust-pkg-debian-bookworm `
  --set defaultPackageImage.tag=20230311-deb12u1.2 `
  --set secretTargets.enabled=true `
  --set secretTargets.authorizedSecretsAll=true `
  --wait
```

### Verify installation

Run the following commands to confirm the installation completed successfully and the required resources are healthy.

```powershell
helm list -n cert-manager
kubectl get pods -n cert-manager
kubectl get crd certificates.cert-manager.io
```

Expected result:

* `cert-manager` and `trust-manager` releases show `deployed` in `helm list`.
* Pods in `cert-manager` namespace are `Running`.
* `certificates.cert-manager.io` CRD exists.

## Install gateway API and Istio (Optional)

To expose Foundry Local services outside the Kubernetes cluster, deploy the required gateway API components and Istio.

Foundry Local automatically creates the gateway API resources required for routing and configures them during extension deployment. However, Foundry Local doesn't install the gateway API CRDs or Istio. You must deploy and manage these components separately.

The `edgeartifacts` container registry includes the required container images and Helm charts.

### Install gateway API CRDs

Install the gateway API Custom Resource Definitions (CRDs). Install these resources before Istio so that the control plane recognizes the gateway API resource types during startup.

```powershell
# Define the edgeartifacts container registry endpoint.
$edgeartifactsAcrPath = "edgeartifacts.edgeacr.autonomous.cloud.private"

helm upgrade --install gateway-api-crds `
  "oci://$edgeartifactsAcrPath/gateway-api/charts/gateway-api-crds" `
  --version 1.4.0 `
  --namespace gateway-system `
  --create-namespace `
  --wait
```

### Install gateway API Inference Extension CRDs

Install the gateway API Inference Extension CRDs required by Foundry Local for inference routing.

These resources extend the gateway API with inference-specific resource types, such as InferencePool, and must be installed before Istio.

```powershell
# Define the edgeartifacts container registry endpoint.
$edgeartifactsAcrPath = "edgeartifacts.edgeacr.autonomous.cloud.private"

helm upgrade --install inference-pool-crd `
  "oci://$edgeartifactsAcrPath/gateway-api-inference-extension/charts/inference-pool-crd" `
  --version v1.3.1 `
  --namespace gateway-system `
  --create-namespace `
  --wait
```

### Install Istio

Install the Istio base components and control plane.

Foundry Local uses Istio together with gateway API to expose services and route inference traffic. No separate ingress controller is required.

The following script installs the required Istio components from the local `edgeartifacts` container registry.

```powershell
# Define the edgeartifacts container registry endpoint.
$edgeartifactsAcrPath = "edgeartifacts.edgeacr.autonomous.cloud.private"

# Install Istio base CRDs.
helm upgrade --install istio-base `
  "oci://$edgeartifactsAcrPath/istio/charts/base" `
  --version 1.29.2 `
  --namespace istio-system `
  --create-namespace `
  --wait

# Install the Istio control plane.
helm upgrade --install istiod `
  "oci://$edgeartifactsAcrPath/istio/charts/istiod" `
  --version 1.29.2 `
  --namespace istio-system `
  --set global.hub=$edgeartifactsAcrPath/istio `
  --set global.tag=1.29.2 `
  --set pilot.env.ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true `
  --wait
```

### Verify installation

Run the following commands to confirm that the installation completed successfully and all required components are healthy.

```powershell
helm list -n gateway-system
helm list -n istio-system

kubectl get pods -n istio-system

kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd inferencepools.inference.networking.x-k8s.io
```

Expected result:

* `gateway-api-crds`, `inference-pool-crd`, `istio-base`, and `istiod` Helm releases show deployed.
* The `istiod` pod is `Running`.
* The gateway API and gateway API Inference Extension CRDs are installed in the cluster.

## Install the Foundry Local Azure Arc Extension

Install the Foundry Local extension on your Arc-enabled Kubernetes cluster. Replace placeholder values and then run the following command.

```powershell
$CLUSTER_NAME = "aldo-cluster"
$RESOURCE_GROUP = "developer"

# Optional. Required only when RBAC authentication is enabled (See in Configure authentication for Foundry Local Azure Arc extension deployment section)
$AZURE_LOCAL_DISCONNECTED_TENANT_ID = ""
$ENTRA_APP_ID = ""

# Optional. Required only when exposing Foundry Local services outside the Kubernetes cluster. Use "internal" to disable this feature.
$API_EXPOSURE = "external" 

az k8s-extension create `
  --name foundry `
  --cluster-name $CLUSTER_NAME `
  --resource-group $RESOURCE_GROUP `
  --cluster-type connectedClusters `
  --extension-type microsoft.foundry `
  --config entraAuth.tenantId=$AZURE_LOCAL_DISCONNECTED_TENANT_ID `
  --config entraAuth.clientId=$ENTRA_APP_ID
  --config api.exposure=$API_EXPOSURE
```

### Verify installation

Run the following commands to confirm the installation completed successfully and the required resources are healthy.

```powershell
az k8s-extension show `
  --name foundry `
  --cluster-name $CLUSTER_NAME `
  --resource-group $RESOURCE_GROUP `
  --cluster-type connectedClusters `
  --query "{name:name,state:provisioningState,version:version}" -o table

kubectl get pods -n foundry-local-operator
```

Expected result:

* Extension state is `Succeeded`.
* Pods in `foundry-local-operator` namespace are `Running`.

## Related content

* [Deployment overview for Foundry Local on Azure Local](../deploy-overview.md)
* [Troubleshoot Foundry Local on Azure Local in disconnected environments](how-to-troubleshoot.md)
* [Deploy your first model in a disconnected environment](how-to-deploy-first-model.md)
* [Configure authentication and authorization for Foundry Local on Azure Local in disconnected environments](how-to-authenticate.md)
