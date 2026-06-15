---
title: "Inference Runtimes in Foundry Local on Azure Local"
description: "Learn how Foundry Local chooses ONNX Runtime or vLLM for generative workloads, and when each runtime is a better fit."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: article
ms.author: cwatson
author: cwatson-cat
ms.date: 06/11/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to understand which inference runtime is used for my model and when to choose each runtime so that I can deploy workloads with the right performance profile.
---

# Inference runtimes in Foundry Local on Azure Local

Foundry Local on Azure Local supports two runtimes for generative inference: ONNX Runtime and vLLM. Each runtime is optimized for different scenarios, and the model you choose determines which runtime is used. The selected runtime affects hardware requirements, model format, and performance behavior. This article explains how runtime selection works and when each runtime is the better fit.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## How the runtime is selected

The model you choose determines the runtime. Each model in the Foundry catalog includes a framework field that specifies which runtime it uses. If the same model is available for both runtimes, it appears as two separate entries in the catalog, each with its own alias and framework.

For example, a model might appear as:

| Alias             | Device | Framework | Runtime used |
| ----------------- | ------ | --------- | ------------ |
| Phi-4-generic-cpu | CPU    | ONNX      | ONNX Runtime |
| Phi-4-cuda-gpu    | GPU    | ONNX      | ONNX Runtime |
| Phi-4             | GPU    | vllm      | vLLM         |

When you deploy a model, the operator reads the framework from the catalog and automatically selects the correct container image and configuration. You don't need to set the runtime manually for catalog models.

For custom (BYO) models, set the `runtime` field on the `ModelDeployment` spec to specify which engine to use. The default is `onnx-genai`.

## ONNX Runtime

ONNX Runtime is the default inference engine. It uses the ONNX-GenAI runtime through the Microsoft Foundry Local SDK to serve generative models in ONNX format. It supports both CPU and GPU execution.

### When to use

Use ONNX Runtime when you need broad hardware support or want a lower-overhead option for generative inference.

- **CPU inference** — The only runtime that supports CPU-based execution. Use it when GPU hardware isn't available.
- **Smaller models** — Well-suited for compact models such as Phi-4 and Qwen 2.5 that fit in CPU memory or a single GPU.
- **Edge and constrained environments** — Lower resource overhead than vLLM.

### Key characteristics

The following characteristics describe how ONNX Runtime behaves in Foundry Local on Azure Local.

- Runs on CPU (default) or GPU (CUDA).
- Serves ONNX-format models from the Foundry catalog or custom (BYO) registries.
- Exposes OpenAI-compatible endpoints: `/v1/chat/completions` and `/v1/models`.
- Supports streaming responses and tool calling (depending on the model).
- Single model per pod.

## vLLM

vLLM is a high-throughput inference engine for large language models on GPU hardware. It uses PagedAttention for efficient GPU memory management and continuous batching to maximize throughput under concurrent load.

### When to use

Use vLLM when your workload runs on GPUs and you want higher throughput or more efficient memory use for large generative models.

- **High throughput** — Continuous batching and PagedAttention deliver higher tokens-per-second than ONNX Runtime under concurrent load.
- **Large models** — Efficient memory management allows serving models that might otherwise exceed GPU memory.
- **Production GPU workloads** — Built-in GPU memory planning automatically sizes batch parameters and context length based on available hardware.

### Key characteristics

The following characteristics highlight how vLLM is optimized for GPU-based generative inference.

- Requires GPU (CUDA). CPU isn't supported.
- Serves HuggingFace-format models (safetensors) from the Foundry catalog or custom (BYO) registries.
- Exposes OpenAI-compatible endpoints: `/v1/chat/completions` and `/v1/models`.
- Supports streaming responses and tool calling (depending on the model).
- Includes a GPU-aware planner that automatically tunes memory utilization, context length, and batch sizes.
- Tunable through the `spec.vllm.preferences` field on the ModelDeployment.

## Comparison

Use the following comparison to quickly identify which runtime best matches your model format, hardware, and performance requirements.

|  Criteria                | ONNX Runtime                                  | vLLM                                               |
| ------------------- | --------------------------------------------- | -------------------------------------------------- |
| GPU required        | No (CPU or GPU)                               | Yes (GPU only)                                     |
| Model format        | ONNX                                          | Hugging Face safetensors                            |
| Best for            | Smaller models, CPU inference, edge scenarios | Large models, high concurrency, maximum throughput |
| Memory optimization | Standard ONNX Runtime                         | PagedAttention, floating-point 8 (FP8), key-value (KV) cache, chunked prefill      |
| Auto-tuning         | None                                          | GPU-aware planner sizes parameters automatically   |
| Catalog models      | Yes                                           | Yes                                                |
| Custom (BYO) models | Yes                                           | Yes                                                |
| API compatibility   | OpenAI chat completions                       | OpenAI chat completions                            |

## Model availability by runtime

For the complete and most current model list, including runtime availability, see [Foundry Local model catalog](https://aka.ms/FL_Models). Many model families appear as separate ONNX and vLLM catalog entries, while some models are available only for one runtime depending on framework packaging and hardware profile.

## Predictive workloads

For non-generative workloads such as classification, object detection, and regression, Foundry Local uses a separate predictive inference engine based on ONNX Runtime. Predictive workloads use the `/v1/predict` endpoint and support custom (BYO) ONNX models. The runtime selection described earlier applies to generative workloads only.

For more information, see [Predictive models](concept-inference-operator.md#predictive-models) in [Inference operator and model lifecycle](concept-inference-operator.md).

## Related content

- [Inference operator and model lifecycle](concept-inference-operator.md)
- [Automatic GPU inference tuning in Foundry Local on Azure Local](concept-gpu-inference-planner.md)
- [Foundry Local multi-node Kubernetes deployment](concept-multi-node-deployment.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
