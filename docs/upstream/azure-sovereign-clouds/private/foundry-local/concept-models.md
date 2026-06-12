---
title: "Generative small language models in Foundry Local on Azure Local"
description: "Learn about the generative small language models available in Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: article
ms.author: cwatson
author: cwatson-cat
ms.date: 06/03/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to understand the generative small language models available in Foundry Local on Azure Local so that I can choose the right model for my workload.
---

# Generative small language models in Foundry Local

Foundry Local on Azure Local includes a curated catalog of generative small language models (SLMs) that you can deploy for on-premises inference. These models are optimized to run on constrained hardware while delivering strong performance on tasks like chat completion, code generation, and reasoning. Depending on the model entry you choose, generative inference uses either ONNX Runtime or vLLM.

This article provides guidance on choosing the right model for your workload.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## What are small language models?

Small language models are compact generative AI models, typically ranging from under 1 billion to around 14 billion parameters. Compared to large language models (LLMs) with hundreds of billions of parameters, SLMs offer:

- **Lower resource requirements** — Run on a single GPU or even on CPU, making them practical for edge and on-premises environments.
- **Faster inference** — Smaller model sizes translate to lower latency and higher throughput per device.
- **Local deployment** — Keep data processing on-premises where your data is generated, without relying on cloud endpoints.

SLMs trade some breadth of general knowledge for efficiency, but advances in training techniques mean that modern SLMs can match or exceed larger models on focused tasks.

## Choose a model

The Foundry Local catalog includes generative models from different providers. All models support the chat completion task and use OpenAI-compatible REST API patterns. The **CC** value in the table refers to the NVIDIA GPU compute capability version.

Use [Inference runtimes in Foundry Local on Azure Local](concept-inference-runtimes.md) to compare ONNX Runtime and vLLM for hardware requirements and performance characteristics.

The following table highlights representative examples only. For the complete and most current list, see [Foundry Local model catalog](https://aka.ms/FL_Models).

| Model | Publisher | Max context length | Recommended minimal GPU generation | Required GPU memory |
|---|---|---|---|---|
| [Phi-3.5-mini-instruct](reference-models.md#phi-35-mini-instruct) | Microsoft | 29,472 | Ampere (CC 8.0)+ | 8.428 GB |
| [Phi-4-mini-instruct](reference-models.md#phi-4-mini-instruct) | Microsoft | 93,520 | Ampere (CC 8.0)+ | 7.806 GB |
| [Phi-4-mini-reasoning](reference-models.md#phi-4-mini-reasoning) | Microsoft | 93,520 | Ampere (CC 8.0)+ | 7.806 GB |
| [Mistral-7B-Instruct-v0.2](reference-models.md#mistral-7b-instruct-v02) | Mistral AI | 29,328 | Ampere (CC 8.0)+ | 15.64 GB |
| [gpt-oss-20b](reference-models.md#gpt-oss-20b) | OpenAI | 96,784 | Blackwell (CC 10.0)+ | 14.793 GB |

For GPU-specific settings and performance benchmarks, see [vLLM model reference](reference-models.md).

## Next steps

- [vLLM model reference](reference-models.md) — GPU requirements, recommended settings, and performance benchmarks for each model.
- [Inference operator and model lifecycle](concept-inference-operator.md) — Understand how models are deployed and managed on your cluster.
- [Run inference](how-to-run-inference.md) — Send requests to a deployed model endpoint.
