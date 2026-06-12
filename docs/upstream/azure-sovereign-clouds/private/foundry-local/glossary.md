---
title: "Glossary for Foundry Local on Azure Local"
description: "Definitions of key terms used in Foundry Local on Azure Local documentation."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: reference
ms.author: cwatson
author: cwatson-cat
ms.date: 04/29/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want definitions for Foundry Local on Azure Local terminology so that I can understand the documentation and configure the platform correctly.
---

# Glossary for Foundry Local on Azure Local

This article defines key terms used throughout Foundry Local on Azure Local documentation.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## A

### API key

A credential used to authenticate requests to a deployed model endpoint. Each deployment has a primary and secondary key, so you can rotate keys without downtime.

### Azure Arc extension

A Kubernetes extension installed through Azure Arc that deploys and manages Foundry Local components on an Arc-connected cluster.

## B

### Bring Your Own Model (BYO)

A deployment pattern where you package and deploy a model from your own OCI-compatible registry instead of using a model from the Foundry catalog.

## C

### Catalog

The set of prepackaged models provided by the Foundry catalog that you can deploy through Foundry Local. These models are containerized and stored in a registry. For metadata and availability in your cluster, see [model catalog](#model-catalog).

### Catalog-sync

A Foundry Local component that regularly pulls model metadata from the Foundry catalog API and writes it to the `foundry-local-catalog` ConfigMap in the cluster.

### Custom Resource Definition (CRD)

A Kubernetes API extension that defines a custom resource type. Foundry Local uses CRDs such as Model, ModelDeployment, and StoreModel to represent model lifecycle and serving state.

## D

### Disconnected environment

A deployment environment without internet connectivity, where Foundry Local runs by using locally imported extensions, registries, certificates, and supporting components.

## E

### Expansion pack

A package of required container images, Helm charts, and artifacts used to install or operate Foundry Local in disconnected environments.

## F

### Foundry Local

The underlying on-device AI inference runtime that runs models on local hardware. In this context, it refers to the core technology that enables AI model serving outside the cloud. Foundry Local is the engine that Foundry Local on Azure Local uses to run models on your infrastructure.

## G

### Generative model

An AI model that generates content, typically free-form text, in response to prompts. These models produce novel output rather than selecting from predefined categories. Examples include language models used for chat, question answering, and text generation.

## I

### Ingress

A Kubernetes routing layer that can expose model endpoints externally, typically with TLS and host or path-based routing.

### Inference operator

A Kubernetes operator that reconciles Model and ModelDeployment resources and creates the Kubernetes resources needed to deploy and run inference endpoints.

## L

### Lazy registration

The automatic creation of a Model CR from the catalog when a ModelDeployment first references it. If the operator doesn't find an existing Model CR for a catalog model, it creates one automatically from the catalog ConfigMap. This process means you don't need to create Model CRs manually for standard catalog models. Lazy registration is enabled by default and can be turned off in the operator configuration.

## M

### Microsoft Entra ID authentication

An identity-based authentication mode where clients send a JWT issued by Microsoft Entra ID. Authorization is then evaluated by using Azure role-based access control (Azure RBAC).

### Model

A custom resource (CR) that defines a model available for deployment. A Model resource describes where the model comes from (catalog or custom registry), its metadata, and any hardware-specific variants.

### Model catalog

The set of prepackaged models from the Azure AI Foundry catalog that you can deploy through Foundry Local. In your cluster, the catalog appears as a ConfigMap (`foundry-local-catalog`). The catalog-sync component keeps this ConfigMap up to date with metadata from the Foundry catalog API.

### ModelDeployment

A custom resource (CR) that defines how a model runs, including runtime, compute, scaling, and endpoint settings. When you create a ModelDeployment, you create a runnable inference endpoint.

### Multi-node deployment

A Foundry Local deployment pattern that runs across multiple Kubernetes nodes to scale concurrent inference and place CPU and GPU workloads appropriately.

## N

### NGINX

A high-performance web server and reverse proxy. In Foundry Local deployments, each ModelDeployment pod includes an NGINX sidecar container for TLS termination and request proxying to the model server. The application middleware enforces authentication.

## O

### ONNX

Open Neural Network Exchange (ONNX), an open model format for interoperability across machine learning frameworks and runtimes.

### ONNX Runtime

The runtime used to execute ONNX-based generative and predictive workloads, including CPU and GPU scenarios based on model and runtime selection.

### ONNX-GenAI

The default Foundry Local runtime option for generative and predictive ONNX workloads. Select this option as `onnx-genai` in ModelDeployment runtime settings.

### Open Web UI

A web-based user interface accessible from a browser that you use to select a deployed model and interact with it. It's not enabled by default and is primarily intended for convenience during development - not as an end-user production application.

### ORAS

OCI Registry As Storage - a protocol for storing and distributing model artifacts in OCI-compatible container registries, such as Azure Container Registry, GitHub Container Registry, or Docker Hub. Foundry Local uses ORAS for BYO predictive model scenarios.

## P

### PagedAttention

A vLLM memory-management technique that improves GPU utilization and throughput for concurrent generative inference.

### Predictive model

A machine learning model that returns structured predictions, such as labels, scores, or numeric outputs, from input features. Examples include image classifiers, regression models, and anomaly detection models.

## S

### StoreModel

An internal custom resource that the inference operator uses to track model artifact caching status in the local OCI registry.

## T

### trust-manager

A Kubernetes trust distribution component that publishes CA bundles to namespaces so workloads can trust internal service certificates.

## V

### vLLM

A GPU-optimized inference runtime used for high-throughput generative workloads. In Foundry Local, it supports planner-based tuning and `spec.vllm.preferences` configuration.

### vLLM planner

An automatic tuning component that calculates memory-safe vLLM serving parameters based on model and GPU characteristics, with optional overrides through `spec.vllm.preferences`.

## Related content

- [What is Foundry Local on Azure Local?](overview.md)
- [Inference operator and model lifecycle](concept-inference-operator.md)
- [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md)
