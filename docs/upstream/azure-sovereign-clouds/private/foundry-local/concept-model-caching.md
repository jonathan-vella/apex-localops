---
title: "Model caching and StoreModel lifecycle in Foundry Local on Azure Local"
description: "Understand how the StoreModel CRD tracks model caching in the local OCI registry and how model artifacts are downloaded and served in Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: article
ms.author: cwatson
author: cwatson-cat
ms.date: 04/20/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to understand how model caching works in Foundry Local on Azure Local so that I can troubleshoot deployment issues and manage model storage effectively.
---

# Model caching and StoreModel lifecycle in Foundry Local

This article explains how the StoreModel custom resource definition (CRD) tracks model caching in the cluster's local OCI registry, how cache jobs download and store model artifacts, and how inference pods retrieve cached models.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## What StoreModel does

StoreModel is an internal CRD the operator uses to track whether model artifacts are downloaded and cached in the cluster's local OCI registry. You never create StoreModel resources directly. The inference operator creates and manages them as part of the ModelDeployment reconciliation process.

## StoreModel lifecycle

The StoreModel status phase shows where model caching is in its lifecycle and whether the model is ready for use.

| Phase | Description |
|-------|-------------|
| `Pending` | StoreModel created, cache job not yet started. |
| `Storing` | A Kubernetes Job is running to download model artifacts and push them to the local registry. |
| `Available` | Model artifacts are cached. The `status.storeRef` field contains the local OCI path. |
| `Error` | The cache job failed. The operator deletes the StoreModel so the next deployment attempt can retry. |

## How caching works

When the operator processes a ModelDeployment:

1. It generates a deterministic StoreModel name from the model source, alias, compute type, framework, and version.
1. It checks if a StoreModel CR with that name already exists.
1. If the StoreModel is `Available`, the operator reads the cached OCI path from `status.storeRef` and proceeds.
1. If no StoreModel exists, the operator creates one, which triggers a cache Job.
1. The operator raises a temporary retry (with a configurable poll interval) until the StoreModel reaches `Available`.
1. If the StoreModel enters `Error`, the operator deletes it and marks the ModelDeployment as failed.
1. A configurable timeout prevents indefinite waiting.

The inference pods use an init container (the model-store-retriever) that pulls model files from the local registry into the pod's filesystem before the main inference container starts.

## How caching fits into reconciliation

The caching step occurs early in the ModelDeployment reconciliation flow, after model resolution but before child resource creation:

1. The operator validates the ModelDeployment spec and resolves the model source.
1. The operator ensures the model is cached locally by creating a StoreModel CR and waiting for the cache job to complete.
1. Once the StoreModel is `Available`, the operator proceeds to select the container image, generate API key secrets, and create the remaining child resources (Deployment, Service, ConfigMap, and others).

For the full reconciliation flow, see [Inference operator and model lifecycle](concept-inference-operator.md).

## Related content

- [Inference operator and model lifecycle](concept-inference-operator.md)
- [Model catalog and sourcing](concept-model-catalog.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md)
