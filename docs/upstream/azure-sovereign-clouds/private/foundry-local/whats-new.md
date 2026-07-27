---
title: "What's new in Foundry Local on Azure Local"
description: "Learn about new features, improvements, and updates for Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: whats-new
ms.author: cwatson
author: cwatson-cat
ms.date: 07/20/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to know what's new in Foundry Local on Azure Local so that I can plan upgrades and take advantage of new capabilities.
---

# What's new in Foundry Local on Azure Local

This article summarizes new features, improvements, and important updates for Foundry Local on Azure Local. Use this information to stay current with the latest capabilities and plan your deployments.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## July 2026

### Release of extension version `2606`

This release modernizes inference networking for Foundry Local on Azure Local by replacing the NGINX ingress data path with the Kubernetes Gateway API and adding intelligent, inference-aware request routing.

#### Kubernetes Gateway API for inference traffic

Foundry Local now routes all model traffic through the Kubernetes Gateway API (with Istio as the provider) instead of an NGINX ingress controller. A new `spec.endpoint.exposure` setting controls how each deployment is reached: `internal` (default) attaches an HTTPRoute to the cluster-internal gateway, `external` provisions an on-demand LoadBalancer gateway for outside access, and `none` leaves only the ClusterIP service. The legacy `endpoint.enabled` toggle and NGINX annotations remain accepted for backward compatibility but are mapped or ignored.

For more information, see [Deploy a model](how-to-deploy-model.md#expose-the-deployment).

#### Inference-aware routing with the Endpoint Picker (EPP)

Multireplica vLLM deployments now use an LLM-D-based Endpoint Picker (EPP) instead of basic round-robin load balancing. EPP scores each replica on live signals such as queue depth, KV-cache utilization, and prefix-cache locality, and then routes every request to the best-suited replica through the Gateway API Inference Extension. EPP is enabled by default when a deployment runs more than one replica, delivering measurable gains such as lower time-to-first-token and higher multi-turn throughput.

For more information, see [Inference-aware routing with the Endpoint Picker (EPP)](concept-inference-runtimes.md#inference-aware-routing-with-the-endpoint-picker-epp).

#### External endpoints with gateway TLS termination

You can now expose model endpoints outside the cluster through an external gateway that terminates TLS. Provide a customer-managed TLS secret for production, or let the operator auto-issue a certificate from the internal cluster CA. In-cluster traffic continues to use the internal CA bundle, and the operator adds a `BackendTLSPolicy` so the gateway validates backend service certificates.

For more information, see [Configure TLS and authentication](how-to-configure-tls-authentication.md#configure-external-access-through-gateway-api).

#### Gateway API support in disconnected environments

The Foundry Local expansion pack now bundles the new networking stack, Istio, Gateway API CRDs, Gateway API Inference Extension CRDs, and the EPP container image, and imports them into the local `edgeartifacts` registry. Disconnected clusters get inference-aware routing without outbound internet access. When you size a cluster, plan for one extra EPP pod per multireplica vLLM deployment.

For more information, see [Disconnected environments overview](disconnected-operations/concept-overview.md).

#### Configurable model cache job memory

The StoreModel cache job now ships with higher default memory (16 Gi request, 32 Gi limit) to reliably download and cache large models. You can lower these values at install time for smaller models or resource-constrained clusters.

For more information, see [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md#step-3-install-the-foundry-local-extension).

## June 2026

### Release of extension version `2605`

This release introduces foundational scale, performance, and deployment enhancements for Foundry Local on Azure Local.

#### Multinode Kubernetes deployment support

Foundry Local on Azure Local now supports deployment across multinode Kubernetes clusters. This capability enables concurrent AI inference at scale, so multiple users, applications, and agents can access models in parallel while maintaining predictable performance. Multinode support also enables larger and more demanding models, including high-parameter generative AI workloads, by distributing inference across GPU-capable nodes.

For more information, see [Multi-node Kubernetes deployment](concept-multi-node-deployment.md).

#### Disconnected environment operations

You can now deploy Foundry Local on Azure Local in disconnected environments where internet connectivity isn't available. The deployment model is largely consistent with connected scenarios, with specific guidance for extension availability, certificate management, and model catalog setup in disconnected environments.

For more information, see [Disconnected environments overview](disconnected-operations/concept-overview.md).

#### vLLM inference runtime

In addition to the default ONNX-GenAI engine, Foundry Local now supports the vLLM inference runtime for GPU-only high-throughput generative AI scenarios. The vLLM engine provides optimized serving for large language models with advanced batching and memory management.

For more information, see [Inference runtimes](concept-inference-runtimes.md).

#### Automatic GPU inference tuning

Foundry Local includes automatic GPU inference tuning that optimizes model serving parameters based on available GPU resources and workload characteristics.

For more information, see [Automatic GPU inference tuning](concept-gpu-inference-planner.md).

#### Model caching and StoreModel lifecycle

A new model caching mechanism reduces deployment times by storing model artifacts locally on cluster nodes. The StoreModel resource manages the lifecycle of cached models across the cluster.

For more information, see [Model caching and StoreModel lifecycle](concept-model-caching.md).

## Related content

- [What is Foundry Local on Azure Local?](overview.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Known issues for Foundry Local on Azure Local](known-issues.md)
