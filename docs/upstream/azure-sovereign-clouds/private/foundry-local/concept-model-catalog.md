---
title: "Model catalog and sourcing in Foundry Local on Azure Local"
description: "Understand how the model catalog works, how catalog-sync populates model metadata, and how to reference catalog and BYO models in Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: article
ms.author: cwatson
author: cwatson-cat
ms.date: 06/03/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to understand how models are sourced and referenced in Foundry Local on Azure Local so that I can deploy catalog and custom models effectively.
---

# Model catalog and sourcing in Foundry Local

This article explains where models come from in Foundry Local on Azure Local, how the catalog-sync component populates the model catalog, and the different ways you can reference models in a ModelDeployment. It also covers image selection and how the operator maps workload type, compute, and runtime to container images.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Where models come from

The operator supports two model sources: catalog models pulled from the Azure AI Foundry platform, and bring-your-own (BYO) models pulled from any ORAS-compatible OCI registry.

### Catalog models

Catalog models come from model registries. A component named **catalog-sync** gets model metadata from the Foundry API and stores it in a Kubernetes ConfigMap called **foundry-local-catalog**.

**What catalog-sync does in each cycle:**

1. Gets model metadata for each enabled source. For **foundry-local**, it paginates per device type (CPU, GPU). For **foundry**, it paginates once without device filters and applies the model allowlist.
2. Transforms each API response into a concise format: model ID, alias, display name, publisher, license, task type, variants with compute type and file size, framework, and version.
3. Deduplicates by a composite key (source + alias + compute + version).
4. Writes the result to the foundry-local-catalog ConfigMap as a JSON blob under the catalog.json key.

**When catalog-sync runs:**

- **Initial sync:** A Helm post-install hook Job runs once when you first install the operator.
- **Scheduled sync:** A CronJob runs every six hours by default (`0 */6 * * *`).

**At deployment time**, when a ModelDeployment references a catalog model by name, the operator reads the ConfigMap, finds the matching entry by alias, ID, or display name, and extracts the variant, source provider, framework, and version. The operator makes no external API calls during deployment.

### Query the catalog

To see what models are available in your cluster, use the following steps:

```bash
kubectl get cm foundry-local-catalog -n foundry-local-operator -o json \
  | jq -r '.data."catalog.json"' \
  | jq -r '["ALIAS", "DEVICE", "SIZE", "MODEL_ID"],
  (.models[] | [.alias, (.variants[0].compute | ascii_upcase),
  ((.variants[0].fileSizeBytes / 1073741824 * 100 | floor) / 100 | tostring + "GB"),
  .variants[0].id]) | @tsv' \
  | column -t
```

Check the last sync time:

```bash
kubectl get configmap foundry-local-catalog -n foundry-local-operator \
  -o jsonpath='{.metadata.annotations.foundry\.azure\.com/last-sync}'
```

Trigger a manual sync:

```bash
kubectl create job --from=cronjob/foundry-local-catalog-sync manual-sync \
  -n foundry-local-operator
```

### BYO (bring-your-own) models

BYO models let you deploy any model you package as an OCI artifact in a container registry (Azure Container Registry, GitHub Container Registry, Docker Hub, or any ORAS-compatible registry).

**How BYO model resolution works:**

1. You specify `model.custom` in the ModelDeployment with the registry URL, repository path, tag, and a Kubernetes Secret containing registry credentials.
1. The operator validates the registry hostname against SSRF protections (rejects raw IPs, localhost, and hostnames resolving to internal addresses). The operator's own internal model-store registry is exempt.
1. A StoreModel CR is created, which triggers a cache Job. The Job pulls the OCI artifact from the external registry and pushes it to the local model store.
1. Subsequent deployments of the same model reuse the local cache.

For generative models, package your model in ONNX format. The inference runtime (ONNX Runtime GenAI) loads it directly. For predictive models, package your ONNX model and any preprocessing logic.

### Runtime diversity in the curated catalog

The curated catalog includes hundreds of supported models across multiple publishers, formats, and runtimes. Many model families appear as separate ONNX and vLLM catalog entries, while some models are available only for one runtime depending on framework packaging and hardware profile.

The following table shows a representative sample to illustrate the breadth of the catalog. It isn't an exhaustive list.

| Model | Publisher | Runtime | Primary use case | Notes |
| --- | --- | --- | --- | --- |
| Phi-4 | Microsoft | ONNX, vLLM | General reasoning and chat | Strong reasoning with efficient deployment options |
| Phi-4 Mini Instruct | Microsoft | ONNX, vLLM | Lightweight instruction following | Optimized for smaller footprints |
| Mistral 7B Instruct v0.2 | Mistral AI | ONNX, vLLM | General-purpose chat | Widely adopted open instruct model |
| Mixtral-8x7B Instruct | Mistral AI | vLLM | High-quality chat and multi-turn conversation | Mixture-of-experts architecture |
| DeepSeek R1 Distill Qwen 7B | DeepSeek | ONNX, vLLM | Reasoning-focused workloads | Distilled model optimized for reasoning |
| DeepSeek R1 Distill Qwen 14B | DeepSeek | ONNX, vLLM | Higher-capacity reasoning | Higher-capacity reasoning model |
| Qwen2.5 7B Instruct | Alibaba | ONNX, vLLM | Multilingual chat | Strong general and multilingual performance |
| Qwen2.5 14B Instruct | Alibaba | ONNX, vLLM | High-quality chat | Larger variant for improved response quality |
| Qwen2.5 Coder 7B Instruct | Alibaba | ONNX, vLLM | Code generation and developer workflows | Optimized for developer workflows |
| gpt-oss-20b | OpenAI (OSS) | ONNX, vLLM | Large open-weight inference | Open-weight GPT-style model |
| Nemotron family | NVIDIA | vLLM | High-throughput GPU inference | Optimized for high-performance GPU deployments |
| Whisper Large v3 Turbo | OpenAI | ONNX, vLLM | Speech-to-text transcription | High-accuracy transcription |

For the complete and most current model list, see [Foundry Local model catalog](https://aka.ms/FL_Models).

Use [Inference runtimes in Foundry Local on Azure Local](concept-inference-runtimes.md) to compare runtime behavior and selection criteria.

## Three ways to reference a model

When you create a model deployment, reference a model by using one of three approaches, depending on your model source and deployment needs.

### Catalog reference (`model.catalog`)

Specify a catalog model by name and version. The operator reads the catalog `ConfigMap`, finds the model by name, and resolves all metadata. You don't create a Model custom resource.

```yaml
spec:
  model:
    catalog:
      name: Phi-4-generic-cpu
      version: latest
```

### Model CR reference (`model.ref`)

Reference an existing Model custom resource in the same namespace. The Model custom resource must be in Available phase. Model custom resources are BYO-only: they always contain `source.custom` with registry, repository, tag, and credentials.

```yaml
spec:
  model:
    ref: my-custom-model
```

### Inline custom reference (`model.custom`)

Define the BYO model inline. The operator automatically creates a Model custom resource for reuse.

```yaml
spec:
  model:
    custom:
      registry: myregistry.azurecr.io
      repository: models/my-custom-model
      tag: v1.0.0
      credentials:
        secretRef:
          name: my-registry-credentials
```

## Image selection

The operator selects the container image for the inference pod based on four dimensions:

| Workload | Compute | Source | Runtime | Image key |
|----------|---------|--------|---------|-----------|
| Generative | CPU | Catalog | onnx-genai | generative-cpu |
| Generative | GPU | Catalog | onnx-genai | generative-gpu |
| Generative | CPU | Custom | onnx-genai | generative-cpu-byo (ORAS) |
| Generative | GPU | Custom | onnx-genai | generative-gpu-byo (ORAS) |
| Generative | GPU | Any | vllm | vllm_gpu |
| Predictive | CPU | Custom | onnx-genai | predictive-cpu-byo (ORAS) |
| Predictive | GPU | Custom | onnx-genai | predictive-gpu-byo (ORAS) |

Predictive workloads don't support catalog models. vLLM runtime requires GPU compute.

### Runtimes

The ModelDeployment supports two inference runtimes through the `spec.runtime` field:

- **onnx-genai** (default): Uses ONNX Runtime GenAI. Supports both CPU and GPU. Used for Foundry Local catalog models and BYO ONNX models.
- **vllm**: Uses vLLM for GPU-only inference. Supports both catalog and BYO models. Configured through `spec.vllm` for engine preferences and model cache storage size.

### Example: Same model, multiple catalog entries

A single model can appear multiple times in the catalog, with each entry representing a different platform or compute type. For example, Phi-4-mini-instruct appears as three separate entries:

| Catalog entry | Compute | Runtime | Source | Execution provider | Size |
|---------------|---------|---------|--------|-------------------|------|
| Phi-4-mini-instruct-generic-cpu | CPU | ONNX | foundry-local | CPUExecutionProvider | ~4.8 GB |
| Phi-4-mini-instruct-cuda-gpu | GPU | ONNX | foundry-local | CUDAExecutionProvider | ~3.6 GB |
| Phi-4-mini-instruct | GPU | vLLM | foundry | (managed by vLLM) | N/A |

All three entries share the same alias (phi-4-mini) and serve the same underlying Phi-4-mini-instruct model. The differences are:

- The foundry-local entries use ONNX Runtime and are optimized for on-device inference quantization. One targets CPUs, and the other targets Compute Unified Device Architecture (CUDA) GPUs.
- The foundry entry uses the vLLM runtime engine for high-throughput GPU inference.
- Each entry has its own unique ID (for example, Phi-4-mini-instruct-generic-cpu:5) that you reference in a ModelDeployment.

The following JSON shows the actual catalog entries for this model, taken directly from the catalog ConfigMap:

#### CPU entry

This catalog entry represents the CPU-optimized variant from the foundry-local source:

```json
{
  "id": "Phi-4-mini-instruct-generic-cpu:5",
  "alias": "phi-4-mini",
  "displayName": "Phi-4-mini-instruct-generic-cpu",
  "publisher": "Microsoft",
  "license": "MIT",
  "task": "chat-completion",
  "source": "foundry-local",
  "framework": "ONNX",
  "modelVersion": "5",
  "variants": [
    {
      "id": "Phi-4-mini-instruct-generic-cpu:5",
      "compute": "cpu",
      "executionProvider": "CPUExecutionProvider",
      "fileSizeBytes": 5153960755
    }
  ],
  "supportedCompute": ["cpu"]
}
```

#### GPU entry

This catalog entry represents the GPU variant with CUDA acceleration from the foundry-local source

```json
{
  "id": "Phi-4-mini-instruct-cuda-gpu:5",
  "alias": "phi-4-mini",
  "displayName": "Phi-4-mini-instruct-cuda-gpu",
  "publisher": "Microsoft",
  "license": "MIT",
  "task": "chat-completion",
  "source": "foundry-local",
  "framework": "ONNX",
  "modelVersion": "5",
  "variants": [
    {
      "id": "Phi-4-mini-instruct-cuda-gpu:5",
      "compute": "gpu",
      "executionProvider": "CUDAExecutionProvider",
      "fileSizeBytes": 3865470566
    }
  ],
  "supportedCompute": ["gpu"]
}
```

#### vLLM entry 

This catalog entry represents the high-throughput vLLM variant from the foundry source:

```json
{
  "id": "Phi-4-mini-instruct:1",
  "alias": "Phi-4-mini-instruct",
  "displayName": "Phi-4-mini-instruct",
  "publisher": "Microsoft",
  "license": "MIT",
  "task": "chat-completion",
  "source": "foundry",
  "framework": "vllm",
  "modelVersion": "1",
  "variants": [],
  "supportedCompute": []
}
```

When you deploy this model, choose the entry to reference based on your hardware and throughput needs. For example, to deploy the CPU variant, set `model.catalog.name` to `Phi-4-mini-instruct-generic-cpu` in your ModelDeployment spec.

## Related content

- [Inference operator and model lifecycle](concept-inference-operator.md)
- [StoreModel and model caching](concept-model-caching.md)
- [Inference runtimes in Foundry Local on Azure Local](concept-inference-runtimes.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md)
- [Inference API endpoints and payload reference](reference-inference-api-endpoints-payload.md)
