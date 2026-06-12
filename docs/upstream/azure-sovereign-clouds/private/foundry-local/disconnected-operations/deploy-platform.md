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

## Install an Ingress Controller (Optional)

To expose Foundry Local services outside the Kubernetes cluster, deploy an ingress controller such as NGINX Ingress Controller.

Foundry Local automatically creates ingress resources and applies the required NGINX annotations to enable secure communication. However, Foundry Local doesn't install an ingress controller as part of the extension deployment. You must deploy and manage the ingress controller separately.

The `edgeartifacts` container registry includes the required container images and Helm charts.

The current release uses NGINX Ingress Controller for ingress management. NGINX support is planned to be deprecated in a future release and replaced with an alternative ingress solution. Review future release notes for updated guidance and migration instructions.

The following script installs NGINX Ingress Controller from the local `edgeartifacts` container registry.

```powershell
# Define the edgeartifacts container registry endpoint.
$edgeartifactsAcrPath = "edgeartifacts.edgeacr.autonomous.cloud.private"

# Install or upgrade the NGINX Ingress Controller Helm release.
helm upgrade --install ingress-nginx `
  "oci://$edgeartifactsAcrPath/ingress-nginx/charts/ingress-nginx" `
  --version 4.15.1 `
  --namespace ingress-nginx `
  --create-namespace `
  --set global.image.registry=$edgeartifactsAcrPath `
  --set controller.image.image=ingress-nginx/controller `
  --set controller.image.tag=v1.15.1 `
  --set controller.image.digest="" `
  --set controller.admissionWebhooks.patch.image.image=ingress-nginx/kube-webhook-certgen `
  --set controller.admissionWebhooks.patch.image.tag=v1.6.9 `
  --set controller.admissionWebhooks.patch.image.digest="" `
  --wait
```

### Verify installation

Run the following commands to confirm the installation completed successfully and the required resources are healthy.

```powershell
helm list -n ingress-nginx
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

Expected result:

* `ingress-nginx` release shows `deployed`.
* Controller pod is `Running`.
* Ingress controller service is present in the namespace.

## Install the Foundry Local Azure Arc Extension

Install the Foundry Local extension on your Arc-enabled Kubernetes cluster. Replace placeholder values and then run the following command.

```powershell
$CLUSTER_NAME = "aldo-cluster"
$RESOURCE_GROUP = "developer"

# Optional. Required only when RBAC authentication is enabled (See in Configure authentication for Foundry Local Azure Arc extension deployment section)
$AZURE_LOCAL_DISCONNECTED_TENANT_ID = ""
$ENTRA_APP_ID = ""

az k8s-extension create `
  --name foundry `
  --cluster-name $CLUSTER_NAME `
  --resource-group $RESOURCE_GROUP `
  --cluster-type connectedClusters `
  --extension-type microsoft.foundry `
  --config entraAuth.tenantId=$AZURE_LOCAL_DISCONNECTED_TENANT_ID `
  --config entraAuth.clientId=$ENTRA_APP_ID
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

* [Troubleshoot Foundry Local on Azure Local in disconnected environments](how-to-troubleshoot.md)
* [Deploy your first model in a disconnected environment](how-to-deploy-first-model.md)
* [Configure authentication and authorization for Foundry Local on Azure Local in disconnected environments](how-to-authenticate.md)
