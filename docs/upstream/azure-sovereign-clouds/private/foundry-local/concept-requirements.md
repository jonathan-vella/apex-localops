---
title: "Requirements for Foundry Local on Azure Local"
description: "Review the Azure, machine and storage, networking, and software requirements for deploying Foundry Local on Azure Local so you can prepare your infrastructure."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: concept-article
ms.author: cwatson
author: cwatson-cat
ms.date: 07/23/2026
ai-usage: ai-assisted
customer intent: As a system administrator or platform engineer, I want to review the Azure, hardware, software, and networking requirements for deploying Foundry Local on Azure Local so that I can prepare my infrastructure for a successful deployment.
---

# Requirements for Foundry Local on Azure Local

Foundry Local on Azure Local has specific Azure, infrastructure, networking, and software requirements for deployment. Use this article to verify prerequisites for connected and disconnected environments, including required resources, cluster and hardware baselines, software versions, and network requirements.

If you need help choosing a deployment path and planning phases, start with [Deployment overview for Foundry Local on Azure Local](deploy-overview.md).

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Deployment readiness factors

Foundry Local on Azure Local combines AI model serving, Kubernetes operations, and platform dependencies such as gateway routing, certificate management, and identity integration. Because of this combination, deployment readiness is more than minimum VM size or Kubernetes version.

You also need to account for model runtime behavior, endpoint exposure strategy, and operational dependencies that vary between connected and disconnected environments. These requirements help reduce common early issues such as failed extension installation, insufficient worker capacity for model replicas, and missing networking or certificate prerequisites.

## Resource requirements

To deploy Foundry Local on Azure Local, prepare the following Azure and on-premises resources.

### Azure resources

Before you deploy Foundry Local on Azure Local, verify that you have the following Azure resources and permissions in place:

| **Resource** | **Description** |
|---|---|
| Azure subscription | An active [Azure subscription](https://azure.microsoft.com/free/). |
| Preview deployment access | Foundry Local on Azure Local is available by request during preview. Submit the access request form: [Request preview deployment access](https://aka.ms/FoundryLocalAzure_PreviewRequest). |
| Microsoft Entra ID permissions | Permissions to create a Microsoft Entra [application registration](/entra/identity/enterprise-apps/add-application-portal) and to add [users and groups](/entra/identity/enterprise-apps/add-application-portal-assign-users) to the application. Microsoft Entra ID authentication is enabled by default, but it's optional. You can deploy the Foundry Local extension without it, and it isn't available for the Helm chart deployment channel. If you plan to use Foundry Local models with [Agentic Retrieval](/azure/azure-arc/agents-tools-foundry-local/requirements), you must keep Entra ID authentication enabled. When you install the Foundry Local extension, you [configure Entra ID authentication](how-to-configure-authentication.md). |
| Permissions for AKS enabled by Azure Arc | Permissions to deploy [AKS Arc Kubernetes clusters](/azure/aks/hybrid/aks-create-clusters-portal), create [node pools](/azure/aks/hybrid/manage-node-pools), and install [extensions](/azure/azure-arc/kubernetes/extensions-release). |
| Supported region | Your Azure Arc-enabled Kubernetes cluster must be located in a [supported region](overview.md#supported-regions). |
| Transport Layer Security (TLS) termination certificate | A certificate signed by a company-specific certification authority (CA) or a well-known public CA for secure endpoint access. For more information, see [Configure TLS](how-to-configure-tls-authentication.md). |

### On-premises resources

Foundry Local on Azure Local supports the following on-premises resources:

| **Resource** | **Description** |
|---|---|
| Azure Local infrastructure* | An instance of [Azure Local](/azure/azure-local/overview) infrastructure. For disconnected deployments, Azure Local Disconnected Operations minimum version `2604.3.0` is required. See [Prepare to deploy Foundry Local on Azure Local in disconnected environments](disconnected-operations/how-to-prepare.md). |
| AKS Arc cluster on Azure Local* | An [AKS Arc cluster](/azure/aks/hybrid/aks-create-clusters-portal) (Kubernetes version 1.29 or later) running on the Azure Local instance and registered with Azure Arc as a `connectedClusters` resource. Use [GPUs](/azure/aks/hybrid/deploy-gpu-node-pool) for better performance with generative AI workloads. |
| Gateway API provider | Foundry Local routes model traffic through the Kubernetes Gateway API. Install Istio (istio-base + istiod, version 1.29 or later) as the Gateway API provider, the [Gateway API CRDs](https://github.com/kubernetes-sigs/gateway-api) (v1.4.0 or later), and the Gateway API Inference Extension CRDs (v1.5.0 or later). In disconnected deployments, these dependencies ship in the Foundry Local expansion pack. |
| Certificate management | cert-manager and trust-manager for automated certificate management. In connected environments, use the `azure-cert-manager` extension. In disconnected environments, install `cert-manager` and `trust-manager` from the expansion pack. |
| Management machine (optional) | A machine to manage the Azure Arc-enabled Kubernetes cluster with [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Helm](https://helm.sh/) installed. |

\* Azure Local is the validated and supported platform for Foundry Local on Azure Local.

Plan your cluster storage around the models you deploy. The model cache persistent volume claim (PVC) defaults to 100 GiB, which is enough for most models. To deploy large models such as `magistral`, allocate more storage by setting `spec.vllm.modelCacheStorageGi` on the deployment. For more information, see [Configure model cache storage](reference-model-deployment-operator.md#configure-model-cache-storage).

## Workload, capacity, and topology planning

Before you choose node sizes and counts, decide which outcome matters most in your environment.

- Lower latency and higher throughput: Prefer GPU-backed deployment and size for peak inference demand.
- Lower infrastructure cost for lighter workloads: CPU-backed deployment can be suitable when selected models support CPU inference.
- Higher resiliency and scale flexibility: Use multiple worker nodes and separate pools when needed for production reliability.
- Simpler initial validation: Start with a minimal topology for proof of concept, then scale based on measured latency, throughput, and concurrency.

Use these tradeoffs to choose requirements intentionally instead of treating all minimum values as one-size-fits-all targets.

## Cluster and hardware requirements

Foundry Local on Azure Local supports CPU-backed and GPU-backed deployments. Size your cluster based on the models you plan to run, the expected concurrency and latency requirements, and the hardware needed to achieve the desired performance. Different models might require different CPU, GPU, storage, and cluster configurations.

### Worker node capacity

The following table lists the minimum and recommended worker node capacity. Use GPU-backed deployments when the workload needs lower latency, higher throughput, larger model support, or higher concurrency. Use CPU-backed deployments when the selected model supports CPU inference and meets your performance expectations.

| Requirement | Minimum | Recommended |
|---|---|---|
| Worker node VM size | Standard_D4s_v3 (4 vCPU / 16 GiB) | Standard_D8s_v3 (8 vCPU / 32 GiB) |
| Allocatable memory per node | >= 14 GiB | >= 28 GiB |
| Worker node count | 1 | 2+ (high availability or GPU pool separation) |

Don't use the `az aksarc create` default worker size `Standard_A4_v2` (8 GiB). Use at least `Standard_D4s_v3`.

If you run multireplica `vLLM` deployments, reserve extra capacity for one Endpoint Picker (EPP) pod per ModelDeployment (about 512 MiB request and 2 GiB limit). For more information, see [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md) and [Multi-node deployment support](concept-multi-node-deployment.md).

### GPU requirements

You need a GPU node pool only for GPU model variants such as `*-cuda-gpu` and deployments that use `vLLM`. For GPU workloads, verify that:

- Your cluster has NVIDIA GPU nodes with CUDA drivers installed. Supported NVIDIA DDA-passthrough SKUs include `Standard_NC*_A2`, `Standard_NC*_L4_*`, `Standard_NC*_L40_*`, `Standard_NC*_L40S_*`, `Standard_NC*_RTX6000Pro_*`, and Tesla T4 `Standard_NK*`. AMD GPUs aren't supported.
- The Kubernetes device plugin for NVIDIA is configured so the cluster can schedule GPU workloads.

For more information, see [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html) and [Automatic GPU inference tuning](concept-gpu-inference-planner.md). Foundry Local validates GPU compatibility at deployment time and returns a clear error if resources are insufficient. Test in a non-production environment first.

## Software requirements

The following table lists the minimum software requirements for Foundry Local on Azure Local.

| **Component** | **Minimum requirements** |
|---|---|
| Kubernetes | AKS Arc cluster running Kubernetes version 1.29 or later. |
| Azure CLI | For Azure Local deployments, use the version shipped with Azure Local, with the `k8s-extension` extension. |
| kubectl | [kubectl](https://kubernetes.io/docs/tasks/tools/) installed and configured for your cluster. |
| Helm | [Helm](https://helm.sh/) installed. |
| Azure Local (disconnected) | For disconnected deployments, Azure Local Disconnected Operations minimum version `2604.3.0`. |

## Network requirements

For Azure Local deployments, follow the current [Azure Local](/azure/azure-local/concepts/firewall-requirements) and [AKS on Azure Local](/azure/aks/hybrid/aks-hci-network-system-requirements) network requirements.

You can expose the Inference API and individual model endpoints internally within the cluster or externally through the LoadBalancer Gateway. Decide your endpoint exposure strategy based on your security and access needs. For more information, see [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md#step-3-install-the-foundry-local-extension) and [Configure TLS](how-to-configure-tls-authentication.md).

## Supported regions

Foundry Local is available as an Azure Arc extension in specific regions. For the current list, see [Supported regions](overview.md#supported-regions).

## Connected and disconnected implications

Connected and disconnected deployments share the same core platform model, but operational assumptions differ.

- Connected deployments assume online dependency retrieval through Azure Arc and online model and catalog access.
- Disconnected deployments assume expansion-pack based dependency delivery, local artifact sourcing, and disconnected-specific authentication and platform preparation.
- Disconnected deployments also require Azure Local Disconnected Operations minimum version `2604.3.0` or later.

Use the environment-specific table in the next section to map these differences to concrete prerequisites before deployment.

## Requirements by environment

Foundry Local on Azure Local supports both connected and disconnected (Azure Local Disconnected Operations) environments. The following table summarizes the key differences.

| **Requirement** | **Connected** | **Disconnected (ALDO)** |
|---|---|---|
| Extension availability | Installed from online sources through Azure Arc. | Imported through the Foundry Local expansion pack into the `edgeartifacts` registry. |
| Networking dependencies (Istio, Gateway API CRDs) | Installed from online sources. | Bundled in the expansion pack; no outbound internet required at deployment time. |
| Certificate management | `azure-cert-manager` extension. | `cert-manager` and `trust-manager` from the expansion pack. |
| Model artifacts | Pulled from the online Foundry catalog. | Pulled from the local `edgeartifacts` registry, populated by model expansion packs. |
| Identity | Microsoft Entra ID authentication. | Local authentication for disconnected environments. See [Configure authentication and authorization for Foundry Local on Azure Local in disconnected environments](disconnected-operations/how-to-authenticate.md). |
| Azure Local minimum version | Recommended for connected deployments: current supported Azure Local release. | Azure Local Disconnected Operations `2604.3.0` or later. |

For disconnected architecture and bundled dependency details, see [Foundry Local on Azure Local in disconnected environments overview](disconnected-operations/concept-overview.md).

## Related content

- [What is Foundry Local on Azure Local?](overview.md)
- [Deployment overview for Foundry Local on Azure Local](deploy-overview.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Multi-node deployment support](concept-multi-node-deployment.md)
- [Foundry Local on Azure Local in disconnected environments overview](disconnected-operations/concept-overview.md)
