---
title: Foundry Local on Azure Local Multi-Node Kubernetes Deployment
description: Multi-node Foundry Local deployments enable concurrent AI inference, mixed workloads, and horizontal scaling on Azure Arc Kubernetes clusters. 
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
author: cwatson-cat
ms.author: cwatson
ms.reviewer: cwatson
ms.date: 05/11/2026
ms.topic: concept-article
ai-usage: ai-assisted
#customer intent: As an AI platform engineer, I want to understand how Foundry Local distributes models across nodes, so that I can plan capacity for high-parameter generative AI workloads.
---

# Foundry Local multiple node deployment

Foundry Local on Azure Local supports deployment on multi-node Kubernetes clusters, extending AI inference from single-node development to production-scale deployments. When deployed as an Azure Arc extension, it installs on Azure Arc-enabled Kubernetes clusters and uses a Kubernetes-native operator to manage model lifecycle operations across nodes, including model caching, deployment, and serving.

## Scaling with multiple nodes

Multi-node Foundry Local enables concurrent usage at scale, so multiple users, applications, and agents can access models in parallel while maintaining predictable performance. Kubernetes schedules workloads to nodes that meet their CPU, memory, and GPU requirements by using standard controls such as resource requests and limits, node selectors, and affinity rules. This architecture supports heterogeneous clusters where some nodes are CPU-only and others are GPU-capable.

Multi-node support also enables larger and more demanding models, including high-parameter generative AI workloads, by distributing inference across GPU-capable nodes. Combined with local model caching and cluster-aware orchestration, organizations can scale capacity horizontally by adding nodes, without changing application architecture.

## Mixed workload support

On Foundry Local on Azure Local, you can run both generative and predictive inference under a unified operational model. The platform validates GPU-based models and schedules them to GPU-capable nodes, while it places CPU-based models on nodes with sufficient compute capacity. This consistency allows teams to run diverse workloads side by side from traditional ML to large language models within the same cluster.

## Industrial and sovereign AI scenarios

The multi-node Foundry Local architecture is particularly critical for industrial and sovereign AI scenarios, where AI must run reliably on-premises, support high-throughput workloads, and operate under strict data and regulatory constraints. It enables organizations to deliver AI services locally with full control over data, infrastructure, and operations.

## Model delivery options

Foundry Local supports both customer-managed models (Models-as-a-Platform) and Microsoft-managed endpoints (Models-as-a-Service), including proprietary and frontier models delivered through secured, local deployments. Deploy and scale these models across the cluster, to provide flexible model choice while maintaining local inference and governance boundaries.

## Related content

- [Inference operator and model lifecycle](concept-inference-operator.md)
- [Inference runtimes in Foundry Local on Azure Local](concept-inference-runtimes.md)
- [ModelDeployment and operator configuration reference for Foundry Local](reference-model-deployment-operator.md)
