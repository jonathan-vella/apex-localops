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
ms.date: 07/23/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to understand how Foundry Local automatically tunes GPU inference settings so that I can get strong performance without manual trial-and-error.
---

# Automatic GPU inference tuning with vLLM planner in Foundry Local

In Foundry Local, the vLLM planner prepares GPU-based vLLM deployments by validating the selected model and serving configuration against the GPUs allocated to the deployment during startup. It measures runtime memory requirements, verifies that the configuration fits, auto-fits the maximum model context length when you don't specify one, and applies the resulting vLLM settings. You can provide supported vLLM preferences to customize the configuration. The planner provides a memory-safe starting point, but workload-specific performance tuning might still require benchmarking.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## When vLLM planner applies

The vLLM planner is used for a `ModelDeployment` when all of the following conditions are true:

- `spec.workloadType` is `generative`.
- `spec.runtime` is `vllm`.
- `spec.compute` is `gpu`.

CPU deployments and deployments that use ONNX Runtime don't use the vLLM planner.

For runtime-selection context, see [Choose an inference runtime in Foundry Local on Azure Local](concept-inference-runtimes.md).

## Why automatic memory sizing matters

Both model execution and the key-value (KV) cache use GPU memory, and requirements vary by model and deployment. During startup, the planner evaluates the selected model and vLLM configuration against the memory currently available on the allocated GPUs. If you don't specify `max_model_len`, the planner uses vLLM runtime sizing to keep the model's full context when it fits or selects the largest context length that fits. You can set an explicit combined prompt and output limit when your application requires one.

## How the vLLM planner works

When you deploy a GPU model with `runtime: vllm`, the planner runs during model server startup and prepares a configuration for the selected model and allocated GPUs.

The planner:

1. Reads the model configuration and the supported vLLM preferences provided with the deployment.
1. Inspects the allocated GPUs and the memory currently available on them.
1. Uses the installed vLLM runtime to profile the memory required by the selected model and serving configuration.
1. Determines the memory available for KV cache and resolves the maximum context length when one isn't specified.
1. Resolves vLLM scheduler settings and model-specific capabilities such as tool calling and reasoning parsers.
1. Applies the resulting settings when starting the model engine.

The resolved settings provide a starting point for the deployment. If your application has specific context-length or GPU-memory requirements, you can override individual settings. Evaluate latency or throughput changes with a workload representative of your production traffic.

## Automatically configured settings

For the selected deployment, the planner automatically configures the following memory-sensitive and model-specific settings:

| Setting | Planner behavior |
| --- | --- |
| `max_model_len` | Uses an explicit value when provided. Otherwise, vLLM keeps the model's full context when it fits or selects the largest context length that fits. |
| `gpu_memory_utilization` | Derives the vLLM memory budget from the memory currently available on the allocated GPUs and the requested or default utilization. |
| `enable_auto_tool_choice`, `tool_call_parser` | Enables tool calling and selects a parser for supported model families, unless disabled or overridden. |
| `reasoning_parser` | Selects a parser for supported reasoning-output formats. |
| `language_model_only` | By default, sets detected decoder-only multimodal models to text-only serving. You can set it to `false` when full multimodal inputs are required. |

### Common vLLM preferences

The planner doesn't automatically select the following settings. When you provide them in `spec.vllm.preferences`, the settings are included in startup validation and applied to the model server.

| Preference | Purpose |
| --- | --- |
| `max_num_seqs` | Limits the number of sequences processed in one scheduler iteration. |
| `max_num_batched_tokens` | Limits the number of tokens processed in one scheduler iteration. |
| `kv_cache_dtype` | Overrides the KV-cache storage type when a specific memory or compatibility behavior is required. |
| `performance_mode` | Selects `balanced`, `interactivity`, or `throughput` behavior. |

## Override settings with vLLM preferences

Set supported vLLM options in the `spec.vllm.preferences` field of your `ModelDeployment` resource by using vLLM argument names in `snake_case` and native YAML values. The planner treats each preference as a constraint on the selected configuration, while settings you don't specify use planner or vLLM defaults.

The resulting configuration is validated during startup. If it's unsupported or doesn't fit in the available GPU memory, the deployment fails with an error. You can only set supported vLLM preferences through this field.

### Example: Set an application context limit

Use `max_model_len` when your application requires a specific maximum combined prompt and output length. The planner includes the explicit value in startup validation.

```yaml
apiVersion: foundrylocal.azure.com/v1
kind: ModelDeployment
metadata:
  name: my-model
spec:
  model:
    catalog:
      name: phi-4-mini-instruct
  workloadType: generative
  compute: gpu
  runtime: vllm
  resources:
    limits:
      gpu: 1
  vllm:
    preferences:
      max_model_len: 4096
```

### Example: Reserve extra GPU memory headroom

Use `gpu_memory_utilization` when the deployment must leave extra GPU memory for other workloads. This example requests 85% of the memory available at startup. Lower values reduce the memory available to vLLM, including KV-cache capacity.

```yaml
  vllm:
    preferences:
      gpu_memory_utilization: 0.85
```

## How preferences are handled

Foundry Local handles supported preferences according to when vLLM uses them:

| Category | Behavior | Examples |
| --- | --- | --- |
| Engine preferences | Included in startup validation and applied to the model engine | `max_model_len`, `gpu_memory_utilization`, `max_num_seqs`, `max_num_batched_tokens`, `kv_cache_dtype`, `performance_mode`, `dtype`, `quantization` |
| Serving preferences | Applied when the API server starts and don't participate in GPU memory sizing | `enable_auto_tool_choice`, `tool_call_parser`, `reasoning_parser` |

A preference must be supported by the installed vLLM version and available through Foundry Local.

## Configure tensor or pipeline parallelism

Foundry Local supports vLLM model-parallel deployments across multiple GPUs by using either tensor parallelism (TP) or pipeline parallelism (PP). You select the parallel topology in `spec.vllm.preferences`; the planner validates the selected configuration but doesn't choose a topology automatically.

| Mode | Behavior |
| --- | --- |
| Tensor parallelism | Partitions model tensors and their associated computations across GPU workers. |
| Pipeline parallelism | Partitions model layers into ordered stages across GPU workers. |

Both `tensor_parallel_size` and `pipeline_parallel_size` default to `1`. Set only the parallelism mode that you want to increase. vLLM creates one worker rank for each tensor-parallel and pipeline-parallel combination, so the number of GPUs required by one replica is:

`required GPUs = tensor_parallel_size * pipeline_parallel_size`

Request this value in `spec.resources.limits.gpu`. For example, both `TP=2, PP=1` and `TP=1, PP=2` require:

```yaml
resources:
  limits:
    gpu: 2
```

### Tensor parallelism example

Use this example when you want to shard tensor operations across multiple GPUs for a single vLLM replica.

```yaml
spec:
  compute: gpu
  runtime: vllm
  resources:
    limits:
      gpu: 2
  vllm:
    preferences:
      tensor_parallel_size: 2
```

### Pipeline parallelism example

Use this example when you want to split model layers into staged execution across multiple GPUs.

```yaml
spec:
  compute: gpu
  runtime: vllm
  resources:
    limits:
      gpu: 2
  vllm:
    preferences:
      pipeline_parallel_size: 2
```

### Combined tensor and pipeline parallelism example

Use this example when you need both tensor and pipeline parallelism in the same deployment to scale model execution across more GPUs.

`TP=2, PP=2` requires four GPUs:

```yaml
spec:
  compute: gpu
  runtime: vllm
  resources:
    limits:
      gpu: 4
  vllm:
    preferences:
      tensor_parallel_size: 2
      pipeline_parallel_size: 2
```

### Implementation constraints

Keep the following constraints in mind when you configure GPU limits and model parallelism settings.

- Setting `resources.limits.gpu` to a value lower than `tensor_parallel_size * pipeline_parallel_size` is invalid.
- Requesting multiple GPUs without setting TP or PP doesn't configure model parallelism automatically.
- All GPUs for one replica must be available on the same cluster node. If the cluster doesn't contain a node with the requested GPU capacity, or the GPUs aren't currently available, the pod remains `Pending`.

## Related content

- [Inference runtimes in Foundry Local on Azure Local](concept-inference-runtimes.md)
- [Model parallelism for multi-GPU inference in Foundry Local on Azure Local](concept-model-parallelism.md)
- [Deploy a catalog model on Foundry Local](how-to-deploy-model.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [vLLM model reference](reference-models.md)
- [vLLM engine arguments](https://docs.vllm.ai/en/stable/configuration/engine_args/)
- [vLLM parallelism and scaling](https://docs.vllm.ai/en/stable/serving/parallelism_scaling/)
