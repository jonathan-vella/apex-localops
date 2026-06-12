---
title: "vLLM Runtime Model Reference for Foundry Local on Azure Local"
description: "Reference specifications for models using the vLLM runtime in Foundry Local on Azure Local, including GPU requirements, recommended settings, and performance benchmarks."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: reference
ms.author: cwatson
author: cwatson-cat
ms.date: 04/30/2026
ai-usage: ai-assisted
---

# vLLM runtime model reference for Foundry Local 

This article provides GPU requirements, recommended settings, and expected performance benchmarks for models that use the vLLM runtime in Foundry Local.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

For a list of available models and guidance on choosing one, see [Generative small language models in Foundry Local on Azure Local](concept-models.md). For information about how the vLLM runtime compares to ONNX Runtime and how Foundry Local selects a runtime, see [Inference runtimes in Foundry Local on Azure Local](concept-inference-runtimes.md).

## Microsoft

The following models are published by Microsoft and available in the Foundry Local catalog for use with the vLLM runtime.

### Phi-3.5-mini-instruct

Natively-accelerated GPU generation (**recommended**): `Ampere (compute capability (CC) 8.0)` or higher

Natively-supported GPU generation: `Ampere (CC 8.0)` or higher

Minimal supported GPU generation: `Volta (CC 7.0)`

**NVIDIA A10 Tensor Core GPU (Ampere architecture, SM 8.0)**

The following table shows the recommended settings and expected running times for this GPU type:

| Setting | Value |
|---|---|
| Recommended GPU utilization | 0.85 |
| Max model context length | 29,472 |
| Required GPU memory | 8.428 GB |

**Expected running times**

The following table provides performance metrics for standard chat completion usages:

| Maximal concurrency | Mean TTFT (ms)** | P99 TTFT (ms)** | Output throughput (tokens/s) |
|---|---|---|---|
| 1 request | 40.94 | 84.21 | 55.61 |
| 2 requests | 58.64 | 102.78 | 104.01 |
| 4 requests | 66.2 | 106.78 | 180.48 |
| 8 requests | 72.13 | 115.11 | 341.75 |

\* For standard chat completion usages

\*\* Mean metrics stand for the average performance, p99 metrics stand for the worst-performant percentile

### Phi-4-mini-instruct

Natively-accelerated GPU generation (**recommended**): `Ampere (CC 8.0)` or higher

Natively-supported GPU generation: `Ampere (CC 8.0)` or higher

Minimal supported GPU generation: `Volta (CC 7.0)`

**NVIDIA A10 Tensor Core GPU (Ampere architecture, SM 8.0)**

The following table shows the recommended settings and expected running times for this GPU type:

| Setting | Value |
|---|---|
| Recommended GPU utilization | 0.85 |
| Max model context length | 93,520 |
| Required GPU memory | 7.806 GB |

**Expected running times**

The following table provides performance metrics for standard chat completion usages:

| Maximal concurrency | Mean TTFT (ms)** | P99 TTFT (ms)** | Output throughput (tokens/s) |
|---|---|---|---|
| 1 request | 40.32 | 62.34 | 49.96 |
| 2 requests | 61.96 | 88.3 | 93.78 |
| 4 requests | 64.83 | 85.43 | 126.83 |
| 8 requests | 71.3 | 107.32 | 196.12 |

\* For standard chat completion usages

\*\* Mean metrics stand for the average performance, p99 metrics stand for the worst-performant percentile

### Phi-4-mini-reasoning

Natively-accelerated GPU generation (**recommended**): `Ampere (CC 8.0)` or higher

Natively-supported GPU generation: `Ampere (CC 8.0)` or higher

Minimal supported GPU generation: `Volta (CC 7.0)`

**NVIDIA A10 Tensor Core GPU (Ampere architecture, SM 8.0)**

The following table shows the recommended settings and expected running times for this GPU type:

| Setting | Value |
|---|---|
| Recommended GPU utilization | 0.85 |
| Max model context length | 93,520 |
| Required GPU memory | 7.806 GB |

**Expected running times**

The following table provides performance metrics for standard chat completion usages:

| Maximal concurrency | Mean TTFT (ms)** | P99 TTFT (ms)** | Output throughput (tokens/s) |
|---|---|---|---|
| 1 request | 41.53 | 62.45 | 49.92 |
| 2 requests | 64.37 | 88.6 | 91.54 |
| 4 requests | 68.26 | 94.31 | 169.38 |
| 8 requests | 90.47 | 117.99 | 244.84 |

\* For standard chat completion usages

\*\* Mean metrics stand for the average performance, p99 metrics stand for the worst-performant percentile

## Mistral AI

The following models are published by Mistral AI and available in the Foundry Local catalog for use with the vLLM runtime.

### Mistral-7B-Instruct-v0.2

Natively-accelerated GPU generation (**recommended**): `Ampere (CC 8.0)` or higher

Natively-supported GPU generation: `Ampere (CC 8.0)` or higher

Minimal supported GPU generation: `Volta (CC 7.0)`

**NVIDIA A10 Tensor Core GPU (Ampere architecture, SM 8.0)**

The following table shows the recommended settings and expected running times for this GPU type:

| Setting | Value |
|---|---|
| Recommended GPU utilization | 0.85 |
| Max model context length | 29,328 |
| Required GPU memory | 15.64 GB |

**Expected running times**

The following table provides performance metrics for standard chat completion usages:

| Maximal concurrency | Mean TTFT (ms)** | P99 TTFT (ms)** | Output throughput (tokens/s) |
|---|---|---|---|
| 1 request | 75.97 | 146.06 | 30.34 |
| 2 requests | 108.29 | 179.27 | 58.22 |
| 4 requests | 110.83 | 179.02 | 111.96 |
| 8 requests | 123.91 | 241.35 | 182.04 |

\* For standard chat completion usages

\*\* Mean metrics stand for the average performance, p99 metrics stand for the worst-performant percentile

## OpenAI

The following models are published by OpenAI and available in the Foundry Local catalog for use with the vLLM runtime.

### gpt-oss-20b

Natively-accelerated GPU generation (**recommended**): `Blackwell (CC 10.0)` or higher

Natively-supported GPU generation: `Blackwell (CC 10.0)` or higher

Minimal supported GPU generation: `Volta (CC 7.0)`

**NVIDIA A10 Tensor Core GPU (Ampere architecture, SM 8.0)**

The following table shows the recommended settings and expected running times for this GPU type:

| Setting | Value |
|---|---|
| Recommended GPU utilization | 0.8 |
| Max model context length | 96,784 |
| Required GPU memory | 14.793 GB |

**Expected running times**

The following table provides performance metrics for standard chat completion usages:

| Maximal concurrency | Mean TTFT (ms)** | P99 TTFT (ms)** | Output throughput (tokens/s) |
|---|---|---|---|
| 1 request | 52.68 | 232.26 | 97.54 |
| 2 requests | 57.48 | 97.07 | 147.96 |
| 4 requests | 69.18 | 108.85 | 227.53 |
| 8 requests | 87.54 | 169.05 | 354.41 |

\* For standard chat completion usages

\*\* Mean metrics stand for the average performance, p99 metrics stand for the worst-performant percentile

## Related content

- [GPU inference planner in Foundry Local on Azure Local](concept-gpu-inference-planner.md)
- [Run inference in Foundry Local on Azure Local](how-to-run-inference.md)
