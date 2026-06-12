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
ms.date: 05/30/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to know what's new in Foundry Local on Azure Local so that I can plan upgrades and take advantage of new capabilities.
---

# What's new in Foundry Local on Azure Local

This article summarizes new features, improvements, and important updates for Foundry Local on Azure Local. Use this information to stay current with the latest capabilities and plan your deployments.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## June 2026

June 2026 introduces foundational scale, performance, and deployment enhancements for Foundry Local on Azure Local.

### Multi-node Kubernetes deployment support

Foundry Local on Azure Local now supports deployment across multinode Kubernetes clusters. This capability enables concurrent AI inference at scale, so multiple users, applications, and agents can access models in parallel while maintaining predictable performance. Multinode support also enables larger and more demanding models, including high-parameter generative AI workloads, by distributing inference across GPU-capable nodes.

For more information, see [Multi-node Kubernetes deployment](concept-multi-node-deployment.md).

### Disconnected environment operations

You can now deploy Foundry Local on Azure Local in disconnected environments where internet connectivity isn't available. The deployment model is largely consistent with connected scenarios, with specific guidance for extension availability, certificate management, and model catalog setup in air-gapped environments.

For more information, see [Disconnected environments overview](disconnected-operations/concept-overview.md).

### vLLM inference runtime

In addition to the default ONNX-GenAI engine, Foundry Local now supports the vLLM inference runtime for GPU-only high-throughput generative AI scenarios. The vLLM engine provides optimized serving for large language models with advanced batching and memory management.

For more information, see [Inference runtimes](concept-inference-runtimes.md).

### Automatic GPU inference tuning

Foundry Local includes automatic GPU inference tuning that optimizes model serving parameters based on available GPU resources and workload characteristics.

For more information, see [Automatic GPU inference tuning](concept-gpu-inference-planner.md).

### Model caching and StoreModel lifecycle

A new model caching mechanism reduces deployment times by storing model artifacts locally on cluster nodes. The StoreModel resource manages the lifecycle of cached models across the cluster.

For more information, see [Model caching and StoreModel lifecycle](concept-model-caching.md).

## Related content

- [What is Foundry Local on Azure Local?](overview.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Known issues for Foundry Local on Azure Local](known-issues.md)
