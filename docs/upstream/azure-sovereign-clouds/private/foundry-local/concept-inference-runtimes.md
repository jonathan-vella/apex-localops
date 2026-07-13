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
ms.date: 06/23/2026
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

### Inference-aware routing with the Endpoint Picker (EPP) 

For multireplica vLLM deployments, Foundry Local routes requests by using the Gateway API Inference Extension instead of the Gateway's default round-robin. The operator deploys an Endpoint Picker (EPP) alongside the model and binds it to an InferencePool that selects across the replicas. On every request, EPP scores each replica on three signals scraped from vLLM:

- Queue depth — how many requests are waiting in the vLLM scheduler. 
- KV-cache utilization — how much of the paged KV cache is already pinned by in-flight requests. 
- Prefix-cache locality — whether the request's prompt prefix is already cached on a given replica. 
EPP picks the highest-scoring pod and instructs Envoy to forward there. The selection happens out-of-band via ExtProc gRPC — there's no extra hop on the data path. 

#### Default behavior 
Configure EPP per vLLM deployment via `spec.vllm.epp.enabled`. When you don't set the field, the operator chooses a default based on the deployment's replica count: 

| `replicas` | `spec.vllm.epp.enabled` | Effective EPP |
|---|---|---|
| `1` | unset | **off** — nothing to balance, so the operator skips the EPP stack and the `HTTPRoute` targets the service directly. |
| `> 1` | unset | **on** — the operator builds the EPP stack and the HTTPRoute targets the InferencePool. |
| any | explicitly `true` | **on** — explicit value always wins. |
| any | explicitly `false` | **off** — explicit value always wins. |

A typical multireplica vLLM deployment therefore needs no `vllm.epp` block at all: 
```yaml
spec: 
  runtime: vllm 
  compute: gpu 
  replicas: 2          # >1 → EPP is on by default 
  # vllm.epp.enabled is left unset → operator chooses based on replicas 
```

Set the field only when you want to override the default - for example, to force EPP off on a multireplica deployment, or to force it on for a single-replica deployment you intend to scale up: 

```yaml
spec: 
  runtime: vllm 
  compute: gpu 
  replicas: 3 
  vllm: 
    epp: 
      enabled: false   # opt out of the multireplica default 
```

#### Performance benefits 

EPP's value comes from two routing decisions: steering new requests away from the most-loaded replica when concurrency rises, and steering follow-up turns of a conversation back to the replica that already has the chat history in its KV cache. Measured on a 3-replica vLLM deployment with output length capped at 256 tokens (so the comparison isn't skewed by generation-length variance): 

| Scenario | Bottom-line result vs Gateway round-robin |
|---|---|
| Single-turn requests, 20 concurrent users | Average **TTFT is 14% lower** (646 ms vs 753 ms), inter-token latency is 5% lower, and per-user throughput is 6% higher. The gain comes from queue-depth and KV-cache-utilization scoring picking the least-loaded replica per request. |
| Multi-turn chat (3-turn conversations) | Per-user **throughput is 16% higher** at one concurrent user and **10% higher at five**; inter-token latency is **14% lower**; aggregate throughput is **14% higher** at five concurrent users. The gain comes from prefix-cache-aware routing - follow-up turns hit warm KV cache on the same replica instead of cold-prefilling the conversation history on a random one. |
  
When to override the default:

- Leave the default in place for the common cases - single-replica deployments get plain Service routing (no overhead) and multireplica vLLM deployments get inference-aware routing automatically.
- Force `enabled: false` for throughput-maximizing batch workloads that generate very long, unbounded outputs at high concurrency, where the per-token ExtProc overhead can outweigh the routing benefit.
- Force `enabled: true` when you want the EPP stack pre-provisioned on a deployment you currently run at one replica but intend to scale up shortly (avoids a brief reconciliation window during the first scale-up). 

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
