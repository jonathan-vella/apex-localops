---
title: AI Workloads on Azure Local Overview
description: Learn how Azure Local enables AI inference, agentic retrieval, and video analysis on your own infrastructure with cloud-consistent management.
author: cwatson-cat
ms.author: cwatson
ms.topic: concept-article
ms.date: 05/30/2026
ms.collection: ce-skilling-ai-copilot
ms.update-cycle: 180-days
ai-usage: ai-assisted
#CustomerIntent: As an IT admin or AI developer, I want to understand how Azure Local enables AI workloads on my own infrastructure so that I can process data locally while meeting latency, sovereignty, and compliance requirements.
---

# AI workloads on Azure Local

Azure Local brings Azure AI capabilities directly to your infrastructure so you can process data locally without sending it to the cloud. This article covers the AI workloads available on Azure Local and helps you pick the right one for your needs. Each workload runs on Azure Arc-enabled Kubernetes, so you get cloud-consistent management and security while keeping data processing local.

> [!IMPORTANT]
> Some AI workloads described in this article are currently in preview, including Foundry Local on Azure Local and Agentic Retrieval in Foundry Local. See the linked workload documentation and the [Supplemental Terms of Use for Microsoft Azure Previews](https://azure.microsoft.com/support/legal/preview-supplemental-terms/) for legal terms that apply to Azure features that are in beta, preview, or otherwise not yet released into general availability.

## Run AI model inference on your infrastructure

Foundry Local on Azure Local, currently in preview, brings AI inference to your Azure Local environment. Deploy and run generative or predictive models from the Foundry model catalog on an Arc-enabled Kubernetes cluster. You can deploy Foundry Local as an Azure Arc extension or by using Helm.

Foundry Local uses an operator-based control plane for model lifecycle management. The Kubernetes inference operator watches cluster state and reconciles model resources, syncs metadata from the Foundry model catalog, and deploys models through declarative custom resources (Model and ModelDeployment CRDs). Inference traffic is exposed through internal services or ingress, protected with API key or Microsoft Entra ID token validation and TLS.

### Capabilities

Foundry Local includes the core capabilities you need to run AI model inference on Azure Local.

| Capability | Description |
|-----------|-------------|
| **Model catalog sync** | Sync model metadata from the Foundry model catalog to your cluster so you can find and deploy models. |
| **CPU and GPU inference** | Deploy models on CPU-only or GPU-enabled nodes. Use the default ONNX-GenAI engine (CPU or GPU) or the vLLM engine (GPU only) for high-throughput scenarios. |
| **OpenAI-compatible API** | Send requests through `/v1/chat/completions` for generative tasks and `/v1/predict` for predictive tasks. |
| **Multi-model support** | Run multiple model deployments in one cluster with declarative configuration. |
| **Multi-node deployment** | Scale inference across multi-node Kubernetes clusters for concurrent usage and high-parameter model support. |
| **Disconnected operations** | Operate in disconnected environments where internet connectivity isn't available, with a deployment model consistent with connected scenarios. |
| **Bring your own model** | Deploy your own models alongside catalog models for specialized or fine-tuned inference scenarios. |
| **Security** | Use API keys or Microsoft Entra ID authentication for access control, TLS for encryption, and ingress for controlled external access. |

### Use cases

Use Foundry Local when you need low-latency AI inference on local infrastructure for sensitive or operational workloads.

- Run internal chat and content-generation applications while you keep sensitive data on-premises.
- Deploy predictive models for classification, scoring, and real-time decisions on the factory floor.
- Manage AI model serving with Kubernetes-native workflows that fit your existing platform operations.
- Scale AI inference across multiple nodes in a Kubernetes cluster for concurrent access and larger models.
- Run AI inference in disconnected or air-gapped environments without internet connectivity.

For more information, see:

- [What is Foundry Local on Azure Local?](/azure/azure-sovereign-clouds/private/foundry-local/what-is-foundry-local-on-azure-local)
- [Disconnected environments overview](/azure/azure-sovereign-clouds/private/foundry-local/disconnected-operations/concept-overview)

## Search and reason over on-premises documents with AI agents

Agentic Retrieval in Foundry Local, currently in preview, is the Azure Arc-enabled Kubernetes extension at the core of the Agents and Tools with Foundry Local platform. It provides an agentic Retrieval-Augmented Generation (RAG) platform at the edge, combining a knowledge layer (document ingestion, embedding, vector search) with an agentic layer (AI agents, knowledge orchestration, MCP server) to deliver intelligent, multistep assistants grounded in your private on-premises data.

The platform is built on three components that work together:

- **Local agentic RAG** - AI agent orchestration with knowledge bases, knowledge sources, and an MCP server for multistep reasoning over your data.
- **Local knowledge sources** - Data ingestion, embedding, and retrieval pipeline that indexes your on-premises documents into searchable collections.
- **Local chat experience** - A built-in chat UI for interacting with agents, managing conversations, and viewing citations. No custom frontend required.

### Capabilities

Agentic Retrieval in Foundry Local provides the core capabilities you need to build grounded AI experiences over local data.

| Capability | Description |
|-----------|-------------|
| **Agentic RAG** | AI agents process user queries by reasoning over instructions, invoking tools, and generating responses grounded in on-premises data through multistep interactions. |
| **Knowledge orchestration** | Connect agents to one or more data sources through knowledge bases and knowledge sources for comprehensive retrieval. |
| **MCP server** | A built-in Model Context Protocol (MCP) server with search tools, plus support for connecting to external MCP servers. |
| **Data ingestion pipeline** | Ingest, chunk, embed, store, and retrieve your documents and images in a single integrated pipeline. |
| **Local language models** | Use a Foundry Local on Azure Local endpoint (recommended) or bring your own model with an OpenAI-compatible chat completions API. |
| **Multiple search types** | Hybrid, vector, text, and hybrid multimodal search to match your query needs. |
| **Local chat solution** | A built-in chat UI for interacting with agents, managing conversations, and viewing citations with streaming responses. |
| **Azure RBAC** | Control access with Microsoft Entra integration and role-based permissions. |

### Use cases

Use Agentic Retrieval in Foundry Local when you need to search, summarize, and reason over private content that must stay on-premises with intelligent multistep AI agents.

- Query regulatory and compliance documents by using natural language to support permitting, zoning, and environmental review workflows.
- Run compliance checks and customer assistance workflows against financial data that must stay on-premises.
- Build troubleshooting assistants for factory floor technicians by using local operational and maintenance data.
- Deploy an agent that can reason across multiple clinical documents, using knowledge bases and MCP tools to correlate patient records, lab results, and treatment guidelines.
- Connect agents to multiple external data sources via MCP servers, without ingesting all data locally.
- Summarize and generate training materials from classified or sensitive datasets.

For more information, see:

- [What is Agents and Tools with Foundry Local?](/azure/azure-arc/edge-rag/overview)

## Analyze live video at the edge

Azure AI Video Indexer enabled by Azure Arc runs live video analysis on edge devices with low-latency processing. Prebuilt and custom video agents, powered by vision language models, handle tasks such as retail operations monitoring, safety detection, and queue tracking. You can also define custom detection logic by using natural language to monitor specific objects or conditions without writing code.

### Capabilities

Azure AI Video Indexer enabled by Azure Arc provides capabilities for live video analysis on edge infrastructure.

| Capability | Description |
|-----------|-------------|
| **Live video analysis** | Analyze live video feeds in real time with low-latency edge processing for retail, safety, and operational monitoring. |
| **Custom AI models** | Define detection logic by using natural language to monitor specific objects or conditions without writing code. |
| **Video agents** | Deploy prebuilt and custom video agents powered by vision language models to automate monitoring and analysis tasks. |
| **Data governance** | All video data stays on-premises. Only system metadata is sent to Microsoft. |

### Use cases

Use Azure AI Video Indexer enabled by Azure Arc when you need to analyze live video locally for operational, safety, or compliance scenarios.

- Monitor retail store conditions with live video feeds. Detect shelf conditions, safety hazards, and queue lengths, then generate end-of-shift summaries.
- Run quality control and worker safety analysis on manufacturing floor video.
- Deploy custom video agents with natural language-defined detection logic for site-specific monitoring needs.

For more information, see:

- [Azure AI Video Indexer enabled by Azure Arc overview](/azure/azure-video-indexer/arc/azure-video-indexer-enabled-by-arc-overview)

## Operate AI in disconnected and sovereign environments

Azure Local supports disconnected operations in environments with limited or no cloud connectivity. Your clusters can run without continuous Azure connectivity and then sync after connectivity returns.

Before your production rollout, confirm which AI workloads support fully disconnected mode.

All three AI workloads process data on-premises:

- **Foundry Local** processes inference requests locally. Model artifacts are stored in your cluster. Supports fully disconnected operations with a deployment model consistent with connected scenarios.
- **Agentic Retrieval in Foundry Local** runs the entire agentic RAG pipeline, including ingestion, retrieval, agent orchestration, and generation, within your network boundaries.
- **Video Indexer** processes all video and audio locally. No media data is sent to the cloud.

## Common requirements

All three AI workloads require:

- **Azure subscription**: Used to register and manage your resources.
- **Azure Arc-enabled Kubernetes cluster**: Runs on Azure Local and connects to Azure through Azure Arc.
- **Azure CLI**: Used to manage deployments and extensions.
- **Network connectivity**: Outbound connectivity to Azure for control plane operations, billing, and monitoring (except during disconnected operations).

Before your production rollout, verify the network and connectivity requirements for each workload. Each workload has its own hardware and software prerequisites. See the individual workload documentation for more information.

## Choose the right workload

Use the following table to match each AI scenario to the best-fit workload on Azure Local. Plan to combine workloads when your environment has multiple data and application needs.

| If you need to... | Consider |
|-------------------|----------|
| Serve AI models for chat, generation, or prediction | Foundry Local on Azure Local (preview) |
| Scale AI inference across multiple nodes | Foundry Local on Azure Local (preview) |
| Build an intelligent agent over on-premises documents with multistep reasoning | Agentic Retrieval in Foundry Local (preview) |
| Connect AI agents to external data sources via MCP servers | Agentic Retrieval in Foundry Local (preview) |
| Analyze video or audio content in real time or from archives | Azure AI Video Indexer enabled by Azure Arc |
| Process sensitive data that can't leave your premises | Any of the three, depending on your data type |
| Operate fully disconnected or air-gapped | Foundry Local on Azure Local (preview) |

## Related content

- [Azure Arc-enabled Kubernetes overview](/azure/azure-arc/kubernetes/overview)
- [What is Foundry Local on Azure Local?](/azure/azure-sovereign-clouds/private/foundry-local/what-is-foundry-local-on-azure-local)
- [What is Agents and Tools with Foundry Local?](/azure/azure-arc/edge-rag/overview)
- [What is Azure AI Video Indexer enabled by Azure Arc?](/azure/azure-video-indexer/arc/azure-video-indexer-enabled-by-arc-overview)
