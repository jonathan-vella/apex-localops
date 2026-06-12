---
title: "Bring your own models in Foundry Local on Azure Local"
description: "Learn how bring-your-own models work in Foundry Local on Azure Local, including packaging, validation, deployment patterns, and limitations."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: article
ms.author: cwatson
author: cwatson-cat
ms.date: 04/21/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to understand how bring-your-own models work in Foundry Local on Azure Local so that I can package, register, and deploy custom models from my own registry.
---

# Bring-your-own model support in Foundry Local on Azure Local

A bring your own (BYO) model is any model that's not in the catalog. Instead of selecting a pre-registered catalog model, you provide your own model files by pushing them to an Open Container Initiative (OCI)-compatible container registry, like Azure Container Registry, and pointing your `ModelDeployment` at that registry location.

BYO models give you the flexibility to run custom, fine-tuned, or third-party models that aren't available in the catalog.

## BYO models vs. catalog models

The following table shows how catalog models and BYO models differ in source, authentication, deployment behavior, and workload support.

| Aspect | Catalog Model | BYO Model |
|--------|---------------|-----------|
| **Source** | Catalog, Azure AI model registry | Your own OCI registry |
| **Model custom resource (CR) required?** | No, resolved from catalog ConfigMap | Optional, inline model.custom or named model CR |
| **Synchronization state at creation** | Synced from catalog | Synced from the customer OCI registry |
| **Authentication** | Managed internally | You provide credentials via a Kubernetes Secret |
| **Predictive workloads** | Not supported | Supported |
| **Environment variable `FOUNDRY_SOURCE_TYPE`** | foundry | BYO |
| **Image variants** | Standard images | OCI Registry As Storage (ORAS)-enabled images like `generative-cpu-oras` |

## Supported runtimes and workloads

The following table shows which runtimes, workload types, and compute targets support BYO models.

| Runtime | Workload | Compute | BYO Supported? |
|---------|----------|---------|----------------|
| onnx-genai | Generative | Central processing unit (CPU) | Yes |
| onnx-genai | Generative | Graphics processing unit (GPU) | Yes |
| onnx-genai | Predictive | CPU | Yes |
| onnx-genai | Predictive | GPU | Yes |
| vllm | Generative | GPU | Yes |
| vllm | Generative | CPU | No (vLLM requires GPU) |

Predictive workloads only support BYO models. You can't use catalog models for predictive workloads.

## Model file format requirements

The required file format depends on the runtime and workload type.

### ONNX Runtime (onnx-genai)

For ONNX Runtime, the required files depend on whether you deploy a generative or predictive workload.

#### Generative workloads

Generative ONNX workloads require model files, generation configuration, and tokenizer assets.

| File | Required | Description |
|------|----------|-------------|
| `*.onnx` | Yes | At least one ONNX model file |
| `genai_config.json` | Yes | Generation configuration (tokenizer, decoder, search params) |
| `tokenizer.json` | Recommended | Tokenizer vocabulary |
| `tokenizer_config.json` | Recommended | Tokenizer settings |

The recommended way to produce these files is by using Microsoft Olive, which converts and optimizes Hugging Face models to ONNX format with quantization support.

#### Predictive workloads

Predictive ONNX workloads have a simpler package structure and require only the model file.

| File | Required | Description |
|------|----------|-------------|
| `*.onnx` | Yes | At least one ONNX model file |

No `genai_config.json` is needed for predictive workloads.

### vLLM runtime

vLLM expects a standard Hugging Face model layout with configuration, weights, and tokenizer files.

| File | Required | Description |
|------|----------|-------------|
| `config.json` | Yes | Hugging Face model config (must contain `model_type` and `architectures` keys) |
| `*.safetensors` or `*.bin` | Yes | Model weight files |
| `tokenizer.json` or `tokenizer_config.json` | Yes | Tokenizer files |

vLLM expects the standard Hugging Face model directory layout. If you download your model from Hugging Face Hub or export it in the Hugging Face format, it works as-is.

#### Example config.json (minimum required fields)

The following example shows the minimum fields that your config.json file must have.

```json
{
  "model_type": "llama",
  "architectures": ["LlamaForCausalLM"],
  "hidden_size": 4096,
  "num_hidden_layers": 32,
  "num_attention_heads": 32,
  "max_position_embeddings": 4096
}
```

The vLLM planner reads many additional fields from `config.json`, like quantization config, sliding window, rotary position embeddings (RoPE) scaling, mixture of experts (MoE) settings, and more, to auto-tune engine parameters. For best results, include the full Hugging Face configuration.

## ONNX predictive model input and output

When deploying an ONNX model for predictive workloads, the model must use tensor inputs and outputs exclusively. ONNX sequence, map, and optional types aren't supported.

### Supported ONNX types

Only ONNX tensor types are supported. The following data types are recognized:

| ONNX Type String | NumPy Dtype | Description |
|------------------|-------------|-------------|
| `tensor(float16)` | `float16` | Half-precision floating point |
| `tensor(float)` / `tensor(float32)` | `float32` | Single-precision floating point (default) |
| `tensor(float64)` / `tensor(double)` | `float64` | Double-precision floating point |
| `tensor(int32)` | `int32` | 32-bit signed integer |
| `tensor(int64)` | `int64` | 64-bit signed integer |
| `tensor(uint8)` | `uint8` | 8-bit unsigned integer |

If the model declares an unrecognized type, the server defaults to float32 with a warning. The server doesn't handle non-tensor ONNX types, like sequences, maps, or optionals. These types can produce unpredictable results.

### Model constraints

The following constraints apply when you deploy an ONNX model for predictive workloads.

- **Single input only** — the model must have exactly one input tensor. Multi-input ONNX models aren't supported.
- **Multiple outputs supported** — the model can have multiple output tensors. Each output is returned in the response keyed by its name.
- **Single ONNX file** — the model directory should contain only one `.onnx` file. If multiple `.onnx` files exist, the runtime loads only one file and doesn't guarantee which file it selects.
- **Dynamic dimensions supported** — input shapes can include dynamic dimensions (marked as -1 or string names like "batch_size"). The server doesn't validate these dimensions at inference time.

### API contract

The predictive server exposes a single inference endpoint:

#### Request: POST /v1/predict

The request body has a single item with base64-encoded data:

```json
{
  "items": [{
    "content_type": "application/json",
    "encoder": "base64",
    "data": "<base64-encoded JSON array>"
  }]
}
```

The `data` field must be a base64-encoded JSON array representing the input tensor values. The endpoint supports only one item per request.

#### Supported content types

The predictive endpoint accepts the following content types for inference requests.

| Content Type | Description | Use Case |
|--------------|-------------|----------|
| `application/json` | Raw tensor data as a JSON array | Numeric/structured input |
| `image/jpeg` | JPEG image | Vision models |
| `image/png` | PNG image | Vision models |
| `image/gif` | GIF image | Vision models |
| `image/webp` | WebP image | Vision models |
| `image/bmp` | BMP image | Vision models |

The API schema declares `text/plain`, but the endpoint doesn't support it. If you use this content type, the endpoint returns an error.

#### Response

The response returns base64-encoded JSON containing the output tensors:

```json
{
  "metadata": {
    "model_id": "my-model",
    "batch_size": 1,
    "inference_time_ms": 45.67
  },
  "items": [{
    "content_type": "application/json",
    "encoder": "base64",
    "data": "<base64-encoded JSON object>"
  }]
}
```

Decoding the response `data` field yields a JSON object where each key is an output tensor name with an index suffix:

```json
// Decoded response data:
{
  "output_0_0": [[0.1, 0.2, 0.7]],
  "probabilities_1": [[0.3, 0.5, 0.2]]
}
```

### Image preprocessing

When the content type is an image format, the server automatically preprocesses the image before inference:

1. **Decode** — Decodes the base64 input and opens the image by using the Python Imaging Library (PIL).
1. **Convert** — Converts the image to the RGB color space.
1. **Resize** — Resizes the image to the height and width that the model expects from the input shape.
1. **Normalize** — Scales the image to [0, 1], then applies ImageNet normalization (mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]).
1. **Transpose** — Converts the image from height-width-channel (HWC) to channel-height-width (CHW) layout if the model expects channels-first input.

Image preprocessing requires the model input shape to be 4-dimensional (batch, channels, height, width) or (batch, height, width, channels). The server doesn't support other ranks for image inputs.

### Model metadata endpoint

You can query the model's input and output schema by using the following endpoint:

```
GET /v1/model
```

```json
// Response:
{
  "id": "my-model",
  "name": "my-model",
  "type": "classification",
  "input_shape": [1, 3, 224, 224],
  "outputs": [
    { "name": "probabilities", "shape": [1, 1000], "type": "tensor(float)" }
  ],
  "batch_size": 1,
  "execution_provider": "CUDAExecutionProvider",
  "status": "loaded"
}
```

Use this endpoint to verify that your model loads correctly and to inspect its expected input shape and output schema before sending inference requests.

## Packaging and deployment overview

Bring your own (BYO) packaging and deployment follow a consistent flow:

1. Prepare model files that match the selected runtime and workload type.
1. Package the model as an OCI artifact and push it to your registry.
1. Create registry credentials in Kubernetes.
1. Deploy the model by using either inline `model.custom` configuration in a `ModelDeployment` or a named `Model` resource referenced by a `ModelDeployment`.

Use inline custom model configuration when you want the simplest deployment path for a single deployment. Use a named `Model` resource when you want to reuse the same model definition across multiple deployments or manage model metadata separately from deployments.

For the full task flow, see [Package and deploy a bring-your-own model on Foundry Local on Azure Local](how-to-deploy-custom-model.md).

## Validation pipeline

When a BYO model is downloaded, it goes through a validation pipeline before being pushed to the internal model store:

1. **Integrity check** - Scans for zero-byte files (indicates failed or truncated download).
1. **Format validation** - Validates .safetensors file headers and .json file parsing.
1. **Framework detection** - Verifies the files match the declared runtime. For example, vLLM models must have config.json and weight files.
1. **Manifest completeness** - Checks that all required files for the runtime and workload type are present.

If validation fails, the model cache job reports an error and the `ModelDeployment` doesn't progress to Running state.

## Security considerations

BYO model support includes validation and configuration safeguards to help protect your cluster and credentials.

### Registry hostname validation

The operator validates BYO registry hostnames to prevent server-side request forgery attacks:

- Raw IP addresses are rejected.
- Localhost and loopback addresses are rejected.
- Hostnames that DNS-resolve to private or internal IP ranges are rejected.

### vLLM blocked preferences

When you use the vLLM runtime, the operator blocks certain engine parameters through `spec.vllm.preferences` for security or correctness reasons. Key examples include:

- **trust_remote_code** - Prevents arbitrary Python code execution from model files.
- **hf_token** - Prevents credential exposure.
- **download_dir, allowed_local_media_path** - Prevents file system access.
- **worker_cls, scheduler_cls** - Prevents custom class loading.

### Credential handling

Store registry credentials in Kubernetes Secrets. The operator injects these credentials into the model cache job as environment variables (`ORAS_USERNAME`, `ORAS_PASSWORD`). The operator never logs or exposes these credentials in the `ModelDeployment` status.

## End-to-end flow

The following sequence shows how a BYO model moves from your external registry into a running deployment:

1. You push the packaged model to an OCI registry.
1. You create a `ModelDeployment` or `Model` resource that references the external registry artifact.
1. The model cache job pulls the artifact, unpacks it, validates the files, and pushes the model to the internal model store.
1. The pod starts, loads the model from the internal store, and serves requests.

For the deployment procedure, see [Package and deploy a bring-your-own model on Foundry Local on Azure Local](how-to-deploy-custom-model.md).

## Limitations

Review the following limitations before you package and deploy a BYO model.

| Limitation | Details |
|------------|---------|
| **vLLM requires GPU** | vLLM runtime can't run on CPU compute. |
| **Predictive requires BYO** | Catalog models aren't supported for predictive workloads. |
| **No raw IPs in registry URL** | SSRF protection rejects raw IP addresses and localhost. |
| **tar.gz packaging assumed** | BYO models should be packaged as tar.gz archives for proper extraction. |
| **trust_remote_code blocked** | Models requiring custom Python code execution like `modeling_*.py` files aren't supported through vLLM preferences. |
| **Tensors only (predictive)** | ONNX predictive models must use tensor inputs and outputs only. Sequences, maps, and optionals aren't supported. |
| **Single input (predictive)** | ONNX predictive models must have exactly one input tensor. |
| **Single item per request** | The predictive API accepts exactly one item per inference request. |

## Related content

- [Package and deploy a bring-your-own model on Foundry Local on Azure Local](how-to-deploy-custom-model.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [Inference runtimes in Foundry Local on Azure Local](concept-inference-runtimes.md)
- [Inference operator and model lifecycle in Foundry Local on Azure Local](concept-inference-operator.md)
- [ModelDeployment and operator configuration reference for Foundry Local on Azure Local](reference-model-deployment-operator.md)
