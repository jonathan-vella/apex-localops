---
title: "Model parallelism for multi-GPU inference in Foundry Local on Azure Local"
description: "Model parallelism is a technique that distributes a single model replica across multiple GPUs using tensor parallelism (TP), pipeline parallelism (PP), or both in Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: concept-article
ms.author: cwatson
author: cwatson-cat
ms.date: 07/27/2026
ai-usage: ai-assisted
#customer intent: As a platform engineer, I want to understand how model parallelism works so that I can run large models across multiple GPUs when a single GPU isn't sufficient.
---

# Model parallelism for multi-GPU inference in Foundry Local on Azure Local

Model parallelism is a technique that distributes a single AI model across multiple GPUs to enable inference on models that exceed a single GPU's memory or performance capacity. Foundry Local on Azure Local supports two model parallelism strategies for vLLM deployments: tensor parallelism (TP) and pipeline parallelism (PP).

Use model parallelism in Foundry Local on Azure Local when a model's weights exceed a single GPU's memory, or when single-GPU throughput doesn't meet your workload requirements.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## When to use model parallelism

Model parallelism allows a single model replica to run across multiple GPUs. Use it when the model and runtime state required by your workload don't fit on one GPU, or when measured single-GPU performance doesn't meet your requirements. If the model fits and meets your performance and capacity targets on one GPU, distributed inference is usually unnecessary.

## Tensor parallelism (TP) and pipeline parallelism (PP)

The following table describes how each parallelism strategy works and when to use it.

| Strategy | How it works | Use when |
|---|---|---|
| Tensor parallelism (TP) | Partitions model weights across multiple GPUs. Each GPU processes the same request using its weight shard, and workers communicate to combine partial results. | A single GPU lacks the memory or performance capacity, and the model supports the selected TP size. High-bandwidth interconnects such as NVLink reduce communication overhead. |
| Pipeline parallelism (PP) | Assigns different groups of model layers to multiple GPUs. Each GPU processes its stage, and activations pass from one stage to the next. | Layer-based partitioning better fits the model or hardware, or the selected TP size isn't compatible or TP communication is costly. |

You can combine TP and PP when the model supports the selected topology. In a combined configuration, each pipeline stage uses a tensor-parallel group. Actual latency and throughput depend on the model, GPU interconnect, and workload.

## Resource and configuration requirements

These settings apply to vLLM model deployments in Foundry Local on Azure Local. Both `tensor_parallel_size` and `pipeline_parallel_size` default to `1`. Each model replica requires:

`required GPUs per replica = tensor_parallel_size * pipeline_parallel_size`

Set `spec.resources.limits.gpu` to this value. Before you configure parallelism, review these constraints:

- The selected parallel sizes must be compatible with the model.
- Requesting multiple GPUs without setting TP or PP doesn't enable model parallelism automatically.
- A configuration that requests fewer GPUs than `tensor_parallel_size * pipeline_parallel_size` fails during deployment validation.
- All GPUs for one replica must be on the same cluster node. If the cluster doesn't have a node with the requested GPU capacity, or those GPUs aren't available, the pod remains `Pending`.

### Tensor parallelism example

The following example configures a two-GPU TP deployment. Set `tensor_parallel_size` in `spec.vllm.preferences` and set `spec.resources.limits.gpu` to the same value.

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

The following example configures a two-GPU PP deployment. Set `pipeline_parallel_size` in `spec.vllm.preferences` and set `spec.resources.limits.gpu` to the same value.

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

The following example combines TP and PP, requiring four GPUs (2 × 2). Both `tensor_parallel_size` and `pipeline_parallel_size` are set in `spec.vllm.preferences`, and `spec.resources.limits.gpu` is set to the product of the two values.

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

## Related content

- [Deploy a model in Foundry Local on Azure Local](how-to-deploy-model.md)
- [Multi-node deployment concepts in Foundry Local on Azure Local](concept-multi-node-deployment.md)
- [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md)
- [vLLM: Parallelism and Scaling](https://docs.vllm.ai/en/stable/serving/parallelism_scaling/)
- [TensorRT-LLM: Parallelism Strategies](https://nvidia.github.io/TensorRT-LLM/features/parallel-strategy.html)
- [Kubernetes: Schedule GPUs](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
