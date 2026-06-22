---
title: "What is Foundry Local on Azure Local?"
description: "Deploy and run AI models on Azure Local with Arc-enabled Kubernetes for secure, on-premises inference."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: overview
ms.author: cwatson
author: cwatson-cat
ms.date: 06/02/2026
ai-usage: ai-assisted
ms.custom: references_regions
customer intent: As a platform engineer or developer, I want to understand Foundry Local on Azure Local so that I can run and manage AI inference workloads on-premises.
---

# What is Foundry Local on Azure Local?

Foundry Local on Azure Local brings AI inference to your Azure Local environment. Deploy and run AI models on an Arc-enabled Kubernetes cluster with Kubernetes-native operations. Keep your data processing on-premises where your data is generated.

This deployment model is designed for organizations that need local control, low-latency inference, and integration with existing Kubernetes operations on Azure Local.

Foundry Local on Azure Local is one of two options to run AI models locally. It is built for organizations that need enterprise-scale inference on on-premises infrastructure, with Kubernetes-native operations and Azure Arc management. If you want to embed AI in a client app that runs on end-user hardware, see [Foundry Local](/azure/foundry-local/what-is-foundry-local). With that option, data stays on the device, the app can work offline, and you don't need an Azure subscription.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Request deployment access

Foundry Local on Azure Local deployment is currently available by request during preview. To get started, submit the access request form: [Request preview deployment access](https://aka.ms/FoundryLocalAzure_PreviewRequest).

## Key capabilities

The following capabilities highlight what you can do with Foundry Local on Azure Local.

- Run AI inference workloads on Azure Local with Kubernetes-native operations.
- Deploy and manage models through custom resources instead of manual service wiring.
- Use OpenAI-compatible REST patterns for application integration.
- Support CPU and GPU-backed deployments based on workload and hardware profile.
- Scale inference across multi-node Kubernetes clusters for concurrent usage and high-parameter model support.
- Operate in disconnected environments where internet connectivity isn't available, with a deployment model consistent with connected scenarios.
- Secure endpoint access using API keys, Microsoft Entra ID authentication, and TLS-enabled ingress patterns.
- Sync model catalog metadata so teams can discover and deploy supported models consistently.

## Architecture summary

Foundry Local on Azure Local runs on an Arc-enabled Kubernetes cluster and is deployed as an Azure Arc extension. It uses an operator-based control plane for model lifecycle management. At a high level:

- The **Kubernetes inference operator** watches cluster state and reconciles model resources.
- A **Model** resource defines model metadata. Models can come from the Foundry catalog or from your own registry.
- A **ModelDeployment** resource defines runtime intent, such as scaling profile and endpoint exposure.
- The platform can synchronize model catalog metadata into the cluster for discoverability and version consistency.
- Inference traffic is exposed through internal services or ingress, protected with API key, Entra ID token validation, and authentication and TLS.

The following diagram shows how these components work together. An Arc-enabled Kubernetes cluster runs the Foundry Local extension and inference operator, which manage model and model deployment resources. Applications call secured inference endpoints through ingress by using API keys or Entra ID tokens.

<!-- Art Library Source# ConceptualArt-0-000-211 -->

:::image type="content" source="media/overview/connected-architecture.svg" alt-text="Diagram of Foundry Local on Azure Local architecture with Arc-managed extension, inference operator and model resources, and app calls to secured inference endpoints." lightbox="media/overview/connected-architecture.svg" border="false":::

For Azure platform context, see [Azure Arc-enabled Kubernetes](/azure/azure-arc/kubernetes/overview) and [What is Azure Local?](/azure/azure-local/overview).

For architecture differences in disconnected deployments, see [Disconnected environment architecture](disconnected-operations/concept-overview.md#architecture-summary).

## How it works

Foundry Local on Azure Local is installed as an Azure Arc extension and includes these core components:

- **Inference operator**: Kubernetes operator that Foundry Local on Azure Local uses to install and manage inference components and reconcile model lifecycle changes.
- **Model and ModelDeployment CRDs**: Declarative resources that define available models and active serving deployments.
- **Catalog sync**: Brings model catalog metadata into the cluster so you can select and deploy supported models consistently.
- **API key authentication**: Protects inference endpoints by requiring bearer-token style API keys for requests.
- **Entra ID authentication**: Validates Azure Active Directory JSON web tokens through the Microsoft identity sidecar engine for identity-based access control, as an alternative to API keys.
- **TLS and ingress**: Secures traffic in transit and enables controlled external access through ingress.

For disconnected operations, see [Foundry Local on Azure Local in disconnected environments overview](disconnected-operations/concept-overview.md) for the components and behavior that differ from connected deployments.

Work with Foundry Local enabled by Azure Arc through REST APIs or directly through Kubernetes resources. For more information, see [Inference API endpoints and payload](reference-inference-api-endpoints-payload.md).

## Prerequisites scope

To use Foundry Local on Azure Local, plan for these prerequisites at a high level:

- Azure Local environment with Kubernetes cluster capacity sized for your target models.
- Arc connection for Kubernetes management and extension-based lifecycle operations.
- Appropriate compute profile (CPU-only or GPU-enabled nodes) and validated drivers and plugins for GPU scenarios.
- Kubernetes operational access and cluster-level permissions for installing the Azure Arc extension and managing custom resources.
- Network and security posture for ingress, certificate management, and API key handling.

For disconnected environments, use the dedicated prerequisites and setup instructions in [Plan to deploy Foundry Local on Azure Local in disconnected environments](disconnected-operations/how-to-prepare.md) and [Deploy Foundry Local as an Azure Arc extension in a disconnected environment](disconnected-operations/deploy-platform.md).

## Supported regions

Foundry Local is available as an Azure Arc extension in the following regions:

- Australia East
- Canada Central
- Central India
- Central US
- Central US EUAP
- East US
- East US 2
- East US 2 EUAP
- Japan East
- Korea Central
- North Europe
- South Central US
- Southeast Asia
- UK South
- West Europe
- West US
- West US 2
- West US 3

## Supported workloads

Foundry Local on Azure Local supports AI inference workloads such as:

- **Generative AI inference**: Chat-style and text generation scenarios through OpenAI-compatible request patterns, using either the default ONNX-GenAI engine (CPU or GPU) or the vLLM engine (GPU only) for high-throughput scenarios.
- **Predictive AI inference**: Non-generative model serving for classification, scoring, or other deterministic prediction tasks.
- **CPU and GPU execution**: Flexible deployment targets based on performance and cost requirements.
- **Multi-model serving patterns**: Multiple model deployments managed declaratively within the same cluster.

## When to use

Use Foundry Local on Azure Local when you need to:

- Keep inference and data processing on-premises for sovereignty or regulatory requirements.
- Reduce round-trip latency by serving models near applications and data sources.
- Standardize AI serving with Kubernetes-native operations in existing platform workflows.
- Use Azure-connected management patterns while running inference on local infrastructure.
- Scale AI inference across multiple nodes in a Kubernetes cluster for concurrent access and larger models.
- Run AI inference in disconnected or air-gapped environments without internet connectivity.

## Related content

- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Multi-node Kubernetes deployment](concept-multi-node-deployment.md)
- [Disconnected environments overview](disconnected-operations/concept-overview.md)
- [Known issues for Foundry Local on Azure Local](known-issues.md)
- [Azure Arc-enabled Kubernetes overview](/azure/azure-arc/kubernetes/overview)
- [Azure Local overview](/azure/azure-local/overview)
