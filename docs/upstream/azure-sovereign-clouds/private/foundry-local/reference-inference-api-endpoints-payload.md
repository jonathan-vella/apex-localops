---
title: "Inference API Endpoints and Payload Reference for Foundry Local on Azure Local"
description: "Reference for data-plane inference API endpoints, request and response payload formats, and authentication header options in Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: reference
ms.author: cwatson
author: cwatson-cat
ms.date: 04/30/2026
ai-usage: ai-assisted
customer intent: As a developer, I want a reference of data-plane inference endpoint paths, payload formats, and authentication headers so that I can correctly construct and validate requests to deployed models in Foundry Local on Azure Local.
---

# Inference API endpoints and payload reference for Foundry Local

This article is a reference for inference API endpoints, request and response payload formats, and authentication header options for models deployed on Foundry Local on Azure Local. Use this article for data-plane endpoint paths and methods, request and response payload shapes, and client request examples for chat, transcription, and predictive inference.

For platform API surface and control-plane contracts, see [Foundry inference API reference for Foundry Local on Azure Local](reference-inference-api.md).

For authentication architecture and authorization behavior, see [Authentication and authorization in Foundry Local enabled by Azure Arc](concept-authentication-authorization.md).

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## API endpoints

Each deployed model exposes the following endpoints. Replace `<base-url>` with your ingress address or internal cluster URL.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Liveness check. Returns `200 OK` when the service is running. |
| `/ready` | GET | Readiness check. Returns `200 OK` when the model is loaded and ready to serve requests. |
| `/v1/model` | GET | Model information. Returns metadata about the loaded model. |
| `/v1/chat/completions` | POST | Generative inference. Use for chat and text generation workloads. When using models with tool calling capabilities, include the `tool_choice` field in the request payload. |
| `/v1/audio/transcriptions` | POST | Generative inference. Use for audio to text transcription. For models with automatic-speech-recognition capabilities (for example, whisper). |
| `/v1/predict` | POST | Predictive inference. Use for ONNX-based classification, regression, and other ML tasks. |

## Authentication

All endpoints require authentication. The platform supports two methods: API key authentication and Microsoft Entra ID JSON Web Token (JWT) authentication. For API key authentication, include the key in your request using one of these header formats: 

| Header format | Example |
|--------------|---------|
| Bearer token (standard) | `Authorization: Bearer <api-key>` |
| api-key header (OpenAI-compatible) | `api-key: <api-key>` |
| Entra ID JWT (enterprise) | `Authorization: Bearer <jwt-token>` |

The platform supports the `Authorization: Bearer` and `api-key` header formats. The application-layer authentication middleware validates the key against the deployment's primary and secondary keys and rejects invalid keys with 401 Unauthorized.

To use Microsoft Entra ID authentication, acquire a JWT and send it in the `Authorization: Bearer` header.

For token acquisition steps, see [Run inference on Foundry Local on Azure Local](how-to-run-inference.md).

For JWT validation, API key detection, and Azure RBAC authorization behavior, see [Authentication and authorization in Foundry Local enabled by Azure Arc](concept-authentication-authorization.md).

## Generative inference request examples

The `/v1/chat/completions` endpoint follows OpenAI Chat Completions conventions.

### Authorization: Bearer

The following example authenticates by using an API key in a standard Bearer token header.

```bash
curl -X POST https://<your-domain>/phi-3.5-gpu/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "Phi-3.5-mini-instruct-cuda-gpu:1",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is the capital/major city of France?"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

### api-key

Use this format for OpenAI-compatible clients that send the key in an `api-key` header.

```bash
curl -X POST https://<your-domain>/phi-3.5-gpu/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "api-key: $API_KEY" \
  -d '{
    "model": "Phi-3.5-mini-instruct-cuda-gpu:1",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is the capital/major city of France?"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

### Authorization: Bearer (Entra ID JWT)

For enterprise scenarios, you can authenticate by using a Microsoft Entra ID JSON Web Token instead of an API key.

```bash
curl -X POST https://<your-domain>/phi-3.5-gpu/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -d '{
    "model": "Phi-3.5-mini-instruct-cuda-gpu:1",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is the capital/major city of France?"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

### Generative response

The following example shows the response shape from a successful chat completion request.

```json
{
  "model": "Phi-3.5-mini-instruct-cuda-gpu:1",
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "The capital/major city of France is Paris."
    },
    "index": 0,
    "finish_reason": "stop"
  }],
  "object": "chat.completion"
}
```

## Predictive inference request examples

The `/v1/predict` endpoint accepts ONNX model inputs. The exact payload structure depends on your model's input schema.

### Image input (base64-encoded)

Convert your image to base64 format by using one of the following commands:

#### [Bash](#tab/bash)

```bash
BASE64_IMAGE=$(base64 -w 0 <PATH_TO_IMAGE_FILE>)

curl -k -X POST "https://<URL>/v1/predict" \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: $API_KEY" \
  -d "{
    \"items\": [{
      \"content_type\": \"image/jpeg\",
      \"encoder\": \"base64\",
      \"data\": \"$BASE64_IMAGE\"
    }]
  }"
```

#### [PowerShell](#tab/powershell)

```powershell
$base64Image = [Convert]::ToBase64String(
  [System.IO.File]::ReadAllBytes("<PATH_TO_IMAGE_FILE>")
)

$body = @{
  items = @(
    @{
      content_type = "image/jpeg"
      encoder      = "base64"
      data         = $base64Image
    }
  )
} | ConvertTo-Json -Depth 3 -Compress

Invoke-RestMethod -Uri https://<URL>/v1/predict -Method Post `
  -Body $body -ContentType "application/json" `
  -Headers @{ "X-API-Key" = $API_KEY } -SkipCertificateCheck
```

---

> [!NOTE]
> The `-k` flag (curl) and `-SkipCertificateCheck` (PowerShell) skip certificate validation for self-signed certificates. In production, configure proper TLS certificates.

## Related content

- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [Configure TLS for Foundry Local on Azure Local](how-to-configure-tls-authentication.md)
- [Inference operator and model lifecycle](concept-inference-operator.md)
- [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md)

