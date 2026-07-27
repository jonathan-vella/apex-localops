---
title: "Deployment Overview for Foundry Local on Azure Local"
description: "Understand deployment paths, architecture, key design decisions, and end-to-end deployment phases for Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: concept-article
ms.author: cwatson
author: cwatson-cat
ms.date: 07/23/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or cloud architect, I want a high-level overview of deploying Foundry Local on Azure Local so I can choose the right deployment path and understand the phases before implementation.
---

# Deployment overview for Foundry Local on Azure Local

Foundry Local on Azure Local is a deployment model that runs AI inference on an Azure Arc-enabled Kubernetes cluster with Kubernetes-native operations. Azure Local is the validated and supported platform for this deployment type.

This article helps platform engineers and architects evaluate connected and disconnected deployment paths, understand core platform components, and plan end-to-end deployment phases before implementation.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Availability during preview

Foundry Local on Azure Local is available by request during preview. Access is provided through the preview request form: [Request preview deployment access](https://aka.ms/FoundryLocalAzure_PreviewRequest).

## Deployment paths

Choose the deployment path that matches your connectivity model and operating environment.

| Deployment path | Best fit | Learn more |
|---|---|---|
| Connected deployment (Azure Arc extension) | Standard connected environments where you install prerequisites from online sources and deploy through Azure Arc. | [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md) |
| Connected deployment (Helm onboarding path) | Teams using direct Helm-based installation provided during preview onboarding. | Provided during onboarding |
| Disconnected deployment (Azure Local Disconnected Operations) | Disconnected Azure Local environments where dependencies are imported through expansion packs and installed from local registries. | [Foundry Local on Azure Local in disconnected environments overview](disconnected-operations/concept-overview.md) |

In connected deployments, networking and certificate dependencies are installed from online sources. In disconnected deployments, these dependencies are bundled through expansion packs and installed locally. For details, see [Foundry Local on Azure Local in disconnected environments overview](disconnected-operations/concept-overview.md).

## What you set up

At a high level, deployment sets up three layers:

- Control plane: Azure Arc extension and inference operator that manage model resources and lifecycle changes.
- Data plane: Model serving endpoints and traffic routing through Kubernetes Gateway API with Istio as the provider.
- Platform services: Catalog synchronization, certificate management, and authentication and authorization integration.

For disconnected deployments, how you set up your gateway and Istio depends on your endpoint exposure strategy. Use the disconnected deployment guide as the primary reference for what you must install in your environment.

For architecture details and diagrams, see [Architecture summary](overview.md#architecture-summary) and [Disconnected environment architecture](disconnected-operations/concept-overview.md#architecture-summary).

## Deployment decisions to make before installation

Before you begin implementation, make these design decisions:

| Decision area | What to decide | Learn more |
|---|---|---|
| Identity | Connected deployments typically use Microsoft Entra ID authentication, while disconnected deployments use local Active Directory-based authentication. | [Configure Entra ID authentication](how-to-configure-authentication.md), [Configure authentication and authorization for Foundry Local in disconnected environments](disconnected-operations/how-to-authenticate.md) |
| Connectivity | Choose connected deployment or disconnected deployment with expansion packs. | [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md), [Foundry Local on Azure Local in disconnected environments overview](disconnected-operations/concept-overview.md) |
| Endpoint exposure | Decide whether endpoints stay internal or are exposed externally based on security and access needs. | [Configure TLS authentication](how-to-configure-tls-authentication.md), [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md) |
| Hardware and model fit | Determine which models you plan to run, expected concurrency, latency targets, and whether CPU-only deployment is sufficient. If GPUs are required, select hardware that aligns with model size, throughput needs, and supported deployment configurations. | [Requirements for Foundry Local on Azure Local](concept-requirements.md#cluster-and-hardware-requirements), [Automatic GPU inference tuning](concept-gpu-inference-planner.md) |
| Model strategy | Choose the models that best fit your workload requirements and target hardware. Model selection drives GPU and CPU requirements, expected throughput and latency, deployment architecture, and overall operational scale. | [Foundry Local model catalog](https://aka.ms/FL_Models), [Deploy your first model and run inference](deploy-run-first-model.md) |
| Deployment topology | Decide whether a single-node setup is enough, or if you need multi-node for scale and reliability. | [Multi-node deployment support](concept-multi-node-deployment.md) |
| Namespace | Decide whether to run only in the default operator namespace or across multiple namespaces for team and workload separation. | [Inference operator and model lifecycle](concept-inference-operator.md#namespace-configuration-for-model-deployments) |

## Planning by project stage

Use the stage that matches where your project is today.

| Stage | Main goal | What to check next |
|---|---|---|
| Explore | Learn what is possible and pick one test workload. | Confirm basic deployment path, model availability, and first inference success. |
| Proof of concept | Test model fit and basic performance with representative requests. | Review model quality, response times, and resource usage in your environment. |
| Pilot | Test with a real app path or a small user group. | Check authentication flow, monitoring, update process, and operational ownership. |
| Production planning | Prepare for reliable operation at expected scale. | Finalize capacity, topology, reliability approach, security controls, and support process. |

## End-to-end deployment phases

Use these phases to plan delivery from platform setup to first inference workload.

| Phase | What happens | Learn more |
|---|---|---|
| 1. Plan | Confirm region support, cluster baseline, connectivity mode, and target workload needs. | [What is Foundry Local on Azure Local?](overview.md), [Requirements for Foundry Local on Azure Local](concept-requirements.md), [Plan to deploy Foundry Local on Azure Local in disconnected environments](disconnected-operations/how-to-prepare.md) |
| 2. Prepare platform prerequisites | Set up traffic routing and certificate management dependencies that the platform requires. | [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md), [Deploy Foundry Local as an Azure Arc extension in a disconnected environment](disconnected-operations/deploy-platform.md) |
| 3. Install platform | Install the Foundry Local extension and apply core platform settings such as identity and namespace strategy. | [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md), [Deploy Foundry Local as an Azure Arc extension in a disconnected environment](disconnected-operations/deploy-platform.md) |
| 4. Validate and onboard first workload | Verify platform health, deploy your first model, and run inference tests. Record quality, response time, throughput, and resource results, and then decide whether to move to pilot or production planning. | [Deploy your first model and run inference](deploy-run-first-model.md) |

## Next steps

Use this overview to choose your deployment path, then continue with the implementation guide for your environment:

- Connected: [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- Disconnected: [Deploy Foundry Local as an Azure Arc extension in a disconnected environment](disconnected-operations/deploy-platform.md)

## Related content

- [What is Foundry Local on Azure Local?](overview.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Deploy your first model and run inference](deploy-run-first-model.md)
- [Foundry Local on Azure Local in disconnected environments overview](disconnected-operations/concept-overview.md)
- [Multi-node deployment support](concept-multi-node-deployment.md)
- [Known issues for Foundry Local on Azure Local](known-issues.md)
