---
title: "Automatic GPU Inference Tuning with vLLM planner"
titleSuffix: Foundry Local on Azure Local
description: "Understand how Foundry Local automatically tunes GPU inference settings for vLLM deployments and when to override defaults."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: article
ms.author: cwatson
author: cwatson-cat
ms.date: 04/17/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to understand how Foundry Local automatically tunes GPU inference settings so that I can get strong performance without manual trial-and-error.
---

# Automatic GPU inference tuning with vLLM planner in Foundry Local

In Foundry Local, the virtual large language model (vLLM) planner is an automatic tuning component that calculates model-serving settings for GPU-based vLLM deployments. It analyzes model and hardware characteristics and applies memory-safe defaults for parameters such as context length and concurrency. You can override specific values when you need custom performance behavior. The vLLM planner helps most deployments start with memory-safe, high-performance defaults instead of requiring manual tuning first.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## When automatic vLLM planner tuning applies

Automatic tuning is used when all of the following conditions are true:

- The workload is generative.
- The runtime is `vllm`.
- The deployment uses GPU compute.

CPU deployments and ONNX Runtime deployments don't use this planner.

For runtime-selection context, see [Choose an inference runtime in Foundry Local on Azure Local](concept-inference-runtimes.md).

## Why tuning matters for performance

GPU memory is a fixed budget shared between the model context length and the number of requests it can handle at the same time. By default, vLLM allocates enough key-value cache to support the model’s full context window. For example, Phi-4-mini can allocate for up to 128K tokens, even when your workload doesn't use prompts that long. The planner lets you trade context length for concurrency. If you set `max_model_len: 4096`, the memory that would have been reserved for 128K-token contexts becomes available for key-value cache blocks that serve additional parallel requests. In a typical deployment, reducing context length to match real workload needs can increase concurrent request capacity by an order of magnitude, which improves throughput and reduces queuing latency under load.

## How automatic tuning works

When you deploy a model with `framework: vllm`, the inference operator runs the vLLM planner before starting the model server. The planner reads the model configuration and detects the GPU hardware. Then, it automatically calculates memory-safe serving parameters.

The planner:

1. Reads the model metadata, `config.json`, and `safetensors` index to determine the model size, architecture, quantization, and context length.
1. Detects the GPU hardware, including video random access memory (VRAM), compute capability, and available free memory.
1. Calculates the memory budget, determining how much VRAM the model weights, activations, and overhead consume.
1. Fills the remaining memory with key-value cache and determines the optimal context length, batch size, and concurrency settings.
1. Detects model capabilities like tool calling and reasoning, and enables the correct vLLM parsers.
1. Outputs a complete set of `vllm serve` arguments that fit in GPU memory.

You don't need to manually tune parameters like `max_model_len`, `max_num_seqs`, or `gpu_memory_utilization`. The planner handles this automatically based on your specific model and GPU combination.

## Tuned parameters

The vLLM planner automatically configures the following parameters:

| Parameter | What the planner does |
|-----------|----------------------|
| `max_model_len` | Sets the maximum context length based on available key-value cache memory |
| `gpu_memory_utilization` | Adjusts the VRAM budget based on actual free memory (important on shared GPUs) |
| `max_num_seqs` | Limits concurrent sequences to prevent out-of-memory errors |
| `max_num_batched_tokens` | Controls the prefill batch size to cap peak activation memory |
| `quantization` | Detects the model's quantization method like floating-point 8-bit format (FP8), activation-aware weight quantization (AWQ), GPT quantization (GPTQ), and others. |
| `kv_cache_dtype` | Enables `FP8` key-value cache when the model and GPU support it (doubles token capacity) |
| `enable_auto_tool_choice` | Enables structured tool or function calling based on model family |
| `tool_call_parser` | Selects the correct parser for the model's tool call format |
| `reasoning_parser` | Enables chain-of-thought extraction for reasoning models |
| `calculate_kv_scales` | Adds runtime floating-point 8-bit format (FP8) scale computation when the model checkpoint lacks pre-calibrated scales |
| `performance_mode` | Passes through your latency or throughput preference to the vLLM scheduler |
| `language_model_only` | Skips loading the vision encoder for multimodal models used in text-only mode |

## Override planner parameters

Override any planner parameter by setting values in the `spec.vllm.preferences` field of your `ModelDeployment` resource. Preferences are key-value pairs using vLLM engine argument names in `snake_case`.

When you set a preference, the planner treats it as a fixed constraint and optimizes all other parameters around it. For example, if you set `max_model_len: 4096`, the planner accepts that context length and recalculates the batch size and concurrency to make the best use of the remaining memory.

### Example: Override context length and memory utilization

The following example sets the maximum context length to 4,096 tokens and limits GPU memory use to 85 percent. Use this pattern when your workload uses shorter prompts and you want to free up memory for more concurrent requests.

```yaml
apiVersion: foundrylocal.azure.com/v1
kind: ModelDeployment
metadata:
  name: my-model
spec:
  model:
    catalog:
      name: Phi-4-cuda-gpu
  workloadType: generative
  compute: gpu
  runtime: vllm
  resources:
    limits:
      gpu: 1
  vllm:
    preferences:
      max_model_len: 4096
      gpu_memory_utilization: 0.85
```

### Example: Disable CUDA graphs and limit concurrency

Use this configuration when a model has compatibility issues with CUDA graph capture, or when you want to cap the number of requests the model server handles at one time. Setting `enforce_eager: true` disables CUDA graph optimizations, which can help with debugging or reduce memory overhead on some models.

In the following example, the planner uses `enforce_eager: true` and `max_num_seqs: 16` as fixed values. It then automatically calculates the remaining parameters, such as `max_model_len` and `max_num_batched_tokens`, to maximize performance within those constraints.

```yaml
  vllm:
    preferences:
      enforce_eager: true
      max_num_seqs: 16
```

Pass any vLLM engine argument that the planner doesn't manage, such as `enable_chunked_prefill` or `disable_custom_all_reduce`. The planner forwards these arguments directly to the vLLM server without affecting its memory calculations.

## Planner-managed and passthrough preferences

Preferences fall into two categories depending on whether the planner factors them into its memory optimization or forwards them unchanged to vLLM.

| Category | Behavior | Examples |
|----------|----------|----------|
| Planner-managed | The planner uses these preferences as constraints and optimizes other parameters around them | `max_model_len`, `gpu_memory_utilization`, `max_num_seqs`, `max_num_batched_tokens`, `kv_cache_dtype`, `enforce_eager`, `performance_mode` |
| Passthrough | The planner forwards these preferences directly to vLLM without affecting memory calculations | `enable_chunked_prefill`, `disable_custom_all_reduce`, `dtype` |

If you override a planner-managed parameter with a value that doesn't fit in GPU memory, the planner reports a warning and attempts to reduce other parameters to compensate. If no valid configuration exists, the deployment fails with a descriptive error.

## Related content

- [Choose an inference runtime in Foundry Local on Azure Local](concept-inference-runtimes.md)
- [Inference operator and model lifecycle](concept-inference-operator.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md)
