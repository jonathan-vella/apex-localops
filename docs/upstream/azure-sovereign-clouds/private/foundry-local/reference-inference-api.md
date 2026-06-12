---
title: "Foundry Inference API Reference for Foundry Local on Azure Local"
description: "Reference for Foundry inference API surfaces, operations, authentication modes, and common API patterns in Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: reference
ms.author: cwatson
author: cwatson-cat
ms.date: 04/30/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want a reference of Foundry inference API surfaces, operations, and response patterns so that I can correctly discover, call, and troubleshoot APIs in Foundry Local on Azure Local.
---

# Foundry inference API reference

This article is the platform reference for Foundry inference APIs in Foundry Local on Azure Local. It covers API surfaces by service, control plane API contracts for models and deployments, and common API patterns such as pagination and error responses.

For data-plane endpoint payloads and request examples, see [Inference API endpoints and payload reference for Foundry Local on Azure Local](reference-inference-api-endpoints-payload.md).

For authentication architecture and authorization flow details, see [Authentication and authorization in Foundry Local enabled by Azure Arc](concept-authentication-authorization.md).

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Platform overview

The Foundry Inference platform gives you a Kubernetes-native system for deploying and managing AI model inference workloads across multiple API surfaces. Each service has a specific role in the inference lifecycle.

All APIs use REST/HTTP. The platform doesn't include any gRPC (remote procedure call) endpoints. All services enforce authentication via Azure role-based access control (Azure RBAC) or API keys.

| Service | Framework | Port | Purpose |
|---------|-----------|------|---------|
| **inference_api** | Python / FastAPI | 8080 | Control plane — create, read, update, and delete (CRUD) operations for Models, Deployments, API keys |
| **predictive-server** | Python / FastAPI | 8000 | Open Neural Network Exchange (ONNX) inference for predictive (non-generative) models |
| **Chat Server** | C# / ASP.NET Core | 5000 | OpenAI-compatible chat completions and audio transcription |

**Base URLs**

```text
Control Plane:     http://<host>:8080/api/v1
Predictive Server: http://<host>:8000
Chat Server:       http://<host>:5000
```

## Control plane API

The control plane API runs on port 8080 by using FastAPI and provides management operations for Kubernetes custom resources. It serves as the primary interface for creating and managing model deployments. An auto-generated OpenAPI specification is available at `/openapi.json` with an interactive Swagger UI at `/docs`.

All non-health endpoints require Azure RBAC authentication. GET and HEAD requests require the `deployments/read` action, POST, PUT, and PATCH requests require `deployments/write`, and DELETE requests require `deployments/delete`.

### Health endpoints

Use these endpoints to check service liveness and readiness.

| Method | Path | Description |
|--------|------|-------------|
| **GET** | /healthz | Liveness probe - always returns 200 if the process is alive |
| **GET** | /readyz | Readiness probe - verifies Kubernetes (K8s) API connectivity (503 if disconnected) |

**Response: GET /healthz**

```json
{ "status": "healthy" }
```

**Response: GET /readyz**

```json
// Success (200):
{ "status": "ready", "kubernetes": "connected" }

// Failure (503):
{ "status": "not ready", "kubernetes": "disconnected", "error": "<reason>" }
```

### Models (unified catalog and bring-your-own (BYO))

The Models API provides a unified view of all available models from multiple sources: the Foundry Local Open Neural Network Exchange (ONNX) catalog, the Microsoft Foundry vLLM catalog, and user-registered (BYO/custom) models. The old separate `/catalog` endpoints are now part of this unified API.

| Method | Path | Description |
|--------|------|-------------|
| **GET** | /api/v1/models | List all models (unified catalog + custom) |
| **GET** | /api/v1/models/foundry-local/{name} | Get a Foundry Local catalog model by alias or ID |
| **GET** | /api/v1/models/foundry/{name} | Get a Microsoft Foundry catalog model by alias |
| **GET** | /api/v1/models/custom/{name} | Get a BYO custom model by Kubernetes (K8s) resource name |
| **POST** | /api/v1/models | Register a new custom (BYO) model |
| **PUT** | /api/v1/models/custom/{name} | Update a custom model (full replace) |
| **DELETE** | /api/v1/models/custom/{name} | Delete a custom model |
| **POST** | /api/v1/models/sync | Trigger a catalog sync |

BYO model operations (POST, PUT, DELETE) are scoped to the `foundry-local-operator` namespace. No namespace path parameter is required.

#### List models — query parameters

Use these query parameters to filter, sort, and page model list results.

| Parameter | Type | Req. | Description |
|-----------|------|------|-------------|
| **name** | string | No | Partial, case-insensitive match on model ID, alias, or displayName |
| **compute** | enum | No | Filter by compute type: cpu, gpu, npu |
| **task** | string | No | Exact, case-insensitive match (e.g., chat-completion) |
| **publisher** | string | No | Partial, case-insensitive match on publisher name |
| **source** | string | No | Filter by source: foundry-local, foundry, custom |
| **limit** | integer | No | Max results per page (1–100, server-clamped) |
| **offset** | integer | No | Number of items to skip for pagination (≥ 0) |

#### List models — response fields

This response includes pagination metadata and the list of returned models.

| Field | Type | Description |
|-------|------|-------------|
| **models** | CatalogModelSummary[] | Paginated list of model summaries |
| **total** | integer | Total count after filtering (before pagination) |
| **count** | integer | Number of models returned in this response |
| **hasMore** | boolean | Whether more results exist beyond this page |
| **limit** | integer or null | The limit parameter used |
| **offset** | integer or null | The offset parameter used |
| **unfilteredTotal** | integer | Total models before any filtering applied |
| **version** | string or null | Catalog version / timestamp |
| **lastSync** | string or null | Last catalog sync timestamp (ISO 8601) |

#### Model summary fields

Each model in the list includes the following summary fields.

| Field | Type | Description |
|-------|------|-------------|
| **alias** | string or null | Short model alias |
| **publisher** | string or null | Publisher / author |
| **description** | string or null | Model description |
| **license** | string or null | License identifier |
| **task** | string or null | Task type (e.g., chat-completion) |
| **source** | string or null | Source: foundry-local, foundry, huggingface, or custom |
| **framework** | string or null | Model framework (e.g., ONNX, Custom/PyTorch) |
| **modelVersion** | string or null | Model version string |
| **supportedCompute** | enum[] or null | List of CPU, GPU, NPU |

#### Create BYO model — request body

You can create only custom (BYO) models through the API. The `source.type` value must be "custom". The catalog sync process manages catalog models.

```json
POST /api/v1/models
Content-Type: application/json

{
  "name": "my-custom-model",
  "displayName": "My Custom Model",
  "description": "A custom ONNX model for image classification",
  "source": {
    "type": "custom",
    "custom": {
      "registry": "myacr.azurecr.io",
      "repository": "models/my-model",
      "tag": "v1.0",
      "credentials": {
        "secretRef": {
          "name": "my-registry-secret",
          "usernameKey": "username",
          "passwordKey": "password"
        }
      }
    }
  },
  "capabilities": {
    "task": "chat-completion",
    "contextLength": 4096,
    "streaming": true
  }
}
```

The `registry` field is validated for server-side request forgery (SSRF) protection. The validation rejects private, internal, and bare IP addresses with a 400 error.

#### Trigger catalog sync

Use this endpoint to start a manual catalog synchronization cycle.

```json
POST /api/v1/models/sync

// Response (200):
{
  "status": "triggered",
  "message": "Catalog sync requested",
  "syncedAt": "2024-01-15T10:30:00Z"
}
```

### Deployments

The Deployments API manages ModelDeployment custom resource definitions (CRDs), which represent running inference workloads. Each deployment creates a Kubernetes Deployment, Service, and optionally an Ingress. The API injects an nginx transport layer security (TLS) sidecar for secure communication, and it enforces authentication at the application layer.

| Method | Path | Description |
|--------|------|-------------|
| **GET** | /api/v1/deployments | List all deployments across all namespaces |
| **GET** | /api/v1/namespaces/{ns}/deployments | List deployments in a specific namespace |
| **GET** | /api/v1/namespaces/{ns}/deployments/{name} | Get a specific deployment with full spec and status |
| **POST** | /api/v1/namespaces/{ns}/deployments | Create a new deployment |
| **PUT** | /api/v1/namespaces/{ns}/deployments/{name} | Full-replace update of a deployment spec |
| **PATCH** | /api/v1/namespaces/{ns}/deployments/{name} | Partial update (replicas, env, resources, endpoint) |
| **DELETE** | /api/v1/namespaces/{ns}/deployments/{name} | Delete a deployment and its child K8s resources |

#### Create deployment — request body

Use the following fields to define a new deployment request.

| Field | Type | Req. | Description |
|-------|------|------|-------------|
| **name** | string | **Yes** | Unique name (1–63 chars, DNS label format) |
| **spec.model** | ModelRef | **Yes** | Model reference (one of: ref, catalog, or custom) |
| **spec.compute** | enum | **Yes** | Compute type: "cpu" or "gpu" |
| **spec.workloadType** | enum | No | Workload type: "generative" (default) or "predictive" |
| **spec.replicas** | integer | No | Pod replica count, 1–100 (default: 1) |
| **spec.port** | integer | No | Container port, 1024–65535 (default: 5000) |
| **spec.displayName** | string | No | Human-readable name (max 256 chars) |
| **spec.env** | EnvVar[] | No | Extra environment variables [{name, value}] |
| **spec.resources** | object | No | CPU, memory, and GPU requests and limits |
| **spec.nodeSelector** | object | No | K8s node selector key-value pairs |
| **spec.tolerations** | Toleration[] | No | Pod scheduling tolerations |
| **spec.endpoint** | EndpointConfig | No | Ingress configuration (host, path, TLS) |
| **spec.authentication** | AuthConfig | No | API key authentication configuration |

#### Model reference types

The `spec.model` field accepts exactly one of the following reference types:

```json
// Reference an existing Model CRD in the same namespace
{ "ref": "my-model-name" }

// Inline catalog model reference
{ "catalog": { "name": "phi-4-mini", "version": "latest" } }

// Inline custom (BYO) model reference
{ "custom": {
    "registry": "myacr.azurecr.io",
    "repository": "models/my-model",
    "tag": "v1.0",
    "credentials": { "secretRef": { "name": "secret-name" } }
  }
}
```

#### Resource requirements

Use this structure to set CPU, memory, and GPU requests and limits.

```json
"resources": {
  "requests": { "cpu": "100m", "memory": "256Mi" },
  "limits": { "cpu": "1000m", "memory": "1Gi", "gpu": 1 }
}
```

> [!NOTE]
> When compute is "gpu" and `skipGpuResource` is false, `resources.limits.gpu` is required (1–8).

#### Create deployment — example request

This example shows a complete deployment request payload.

```json
POST /api/v1/namespaces/default/deployments
Content-Type: application/json

{
  "name": "phi4-mini-deploy",
  "spec": {
    "model": { "catalog": { "name": "phi-4-mini", "version": "latest" } },
    "compute": "cpu",
    "workloadType": "generative",
    "replicas": 2,
    "resources": {
      "requests": { "cpu": "2000m", "memory": "4Gi" },
      "limits": { "cpu": "4000m", "memory": "8Gi" }
    },
    "authentication": { "enabled": true }
  }
}
```

#### Deployment status fields

These fields describe deployment state, readiness, and resolved endpoints.

| Field | Type | Description |
|-------|------|-------------|
| **state** | enum or null | Pending, Creating, Running, Updating, Error, Terminating |
| **message** | string or null | Human-readable status message |
| **readyReplicas** | integer or null | Number of pods in ready state |
| **deploymentReady** | boolean or null | Whether all requested replicas are ready |
| **serviceReady** | boolean or null | Whether the K8s Service is created |
| **internalEndpoint** | string or null | Internal cluster URL for the deployment |
| **externalEndpoint** | string or null | External URL (when Ingress is configured) |
| **resolvedModel** | object or null | Resolved model info: {name, variant, image} |
| **authentication** | object or null | Auth status: {keysSecretName, key rotation timestamps} |
| **conditions** | Condition[] | K8s-style conditions array with type/status/reason/message |

#### Partial update (PATCH)

The PATCH endpoint accepts a subset of fields for quick updates without replacing the entire spec. Only `replicas`, `env`, `resources`, and `endpoint` are patchable. Authentication and model aren't patchable.

```json
PATCH /api/v1/namespaces/default/deployments/phi4-mini-deploy
Content-Type: application/json

{
  "replicas": 3,
  "resources": {
    "limits": { "cpu": "8000m", "memory": "16Gi" }
  }
}
```

### API keys

Each deployment with authentication enabled has a primary and secondary API key, stored as a Kubernetes Secret. The system auto-generates keys when the deployment becomes Ready.

| Method | Path | Description |
|--------|------|-------------|
| **GET** | /api/v1/namespaces/{ns}/deployments/{name}/keys | Get primary and secondary API keys |
| **POST** | .../{name}/keys/{key_type}/rotate | Rotate a key (key_type: primary or secondary) |

#### Get keys — response

This response returns the active primary and secondary API keys for a deployment.

```json
{
  "deploymentName": "phi4-mini-deploy",
  "namespace": "default",
  "primaryKey": {
    "value": "fndry-pk-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "createdAt": "2024-01-15T10:00:00Z"
  },
  "secondaryKey": {
    "value": "fndry-sk-f1e2d3c4-b5a6-0987-dcba-1234567890ef",
    "createdAt": "2024-01-15T10:00:00Z"
  }
}
```

#### Key format

Generated API keys follow these formats.

```text
Primary keys:   fndry-pk-{uuid4} (generated by operator on initial deployment)
Secondary keys: fndry-sk-{uuid4} (generated by operator on initial deployment)
```

Keys rotated through the API rotate endpoint use `secrets.token_hex(32)`, which produces a 64-character hex string without the `fndry-pk-` or `fndry-sk-` prefix.

#### Rotate key — example

This example rotates one key and returns the new key value and timestamp.

```json
POST /api/v1/namespaces/default/deployments/phi4-mini-deploy/keys/primary/rotate

// Response:
{
  "deploymentName": "phi4-mini-deploy",
  "namespace": "default",
  "keyType": "primary",
  "key": {
    "value": "a7f3e2b1c9d8......",
    "createdAt": "2024-01-20T14:30:00Z"
  }
}
```

The deployment must have authentication enabled. If you request keys for a deployment with authentication disabled, the API returns 400.

### InferenceServices (legacy)

InferenceServices is the older CRD design. The recommended approach is to use Models + ModelDeployments. Both approaches remain active in the codebase.

| Method | Path | Description |
|--------|------|-------------|
| **GET** | /api/v1/inferenceservices | List all InferenceServices (all namespaces) |
| **GET** | /api/v1/namespaces/{ns}/inferenceservices | List InferenceServices in a namespace |
| **GET** | /api/v1/namespaces/{ns}/inferenceservices/{name} | Get a specific InferenceService |
| **POST** | /api/v1/namespaces/{ns}/inferenceservices | Create an InferenceService |
| **PUT** | /api/v1/namespaces/{ns}/inferenceservices/{name} | Full-replace update |
| **PATCH** | /api/v1/namespaces/{ns}/inferenceservices/{name} | Partial update |
| **DELETE** | /api/v1/namespaces/{ns}/inferenceservices/{name} | Delete |

#### Key differences from deployments

This table shows how InferenceServices fields map to ModelDeployment fields.

| Field | InferenceService | ModelDeployment |
|-------|------------------|-----------------|
| Workload type field | inferenceType | spec.workloadType |
| Compute field | hardware | spec.compute |
| Model source field | modelSource.foundry / modelSource.byo | spec.model.ref / catalog / custom |
| Ingress field | ingress | spec.endpoint |

## Data-plane API surfaces

This section lists the data-plane endpoints by service surface. For request and response schema details, payload examples, and client samples, see [Inference API endpoints and payload reference for Foundry Local on Azure Local](reference-inference-api-endpoints-payload.md).

### Predictive server (port 8000)

These endpoints support predictive inference workloads and model status checks.

| Method | Path | Description |
|--------|------|-------------|
| **GET** | /health | Liveness probe |
| **GET** | /ready | Readiness probe |
| **GET** | /v1/model | Model metadata endpoint |
| **POST** | /v1/predict | Predictive inference endpoint |

### Chat server (port 5000)

These endpoints support chat completions, transcription, and model listing.

| Method | Path | Description |
|--------|------|-------------|
| **POST** | /v1/chat/completions | OpenAI-compatible generative inference |
| **POST** | /v1/audio/transcriptions | OpenAI-compatible transcription |
| **GET** | /v1/models | OpenAI-compatible model listing |

## Authentication and authorization summary

The application layer enforces authentication, and the nginx sidecar provides TLS termination. Data-plane requests support API key and Microsoft Entra ID JSON Web Token (JWT) credential modes based on deployment configuration.

For detailed architecture, validation flow, and authorization behavior, see [Authentication and authorization in Foundry Local enabled by Azure Arc](concept-authentication-authorization.md).

## Common patterns

Use these patterns for consistent pagination, error handling, and API discovery.

### Pagination

These pagination patterns apply to list endpoints across the API surface.

#### Cursor pagination (deployments, InferenceServices)

These endpoints use Kubernetes-native cursor pagination. Pass the `continueToken` from the response as the `continue` query parameter in the next request.

```
GET /api/v1/deployments?limit=10
// Response includes: "continueToken": "eyJjb250aW51ZS..."

GET /api/v1/deployments?limit=10&continue=eyJjb250aW51ZS...
// Next page; continueToken: null when no more pages
```

#### Offset pagination (models)

The unified models list uses offset-based pagination with `limit` (1–100) and `offset` parameters.

```
GET /api/v1/models?limit=20&offset=0
// Response: { "total": 45, "count": 20, "hasMore": true, ... }

GET /api/v1/models?limit=20&offset=20
// Response: { "total": 45, "count": 20, "hasMore": true, ... }

GET /api/v1/models?limit=20&offset=40
// Response: { "total": 45, "count": 5, "hasMore": false, ... }
```

### Error responses

The following sections describe standard error payloads by API surface.

#### Control plane API format

Control plane errors return a structured envelope with field-level validation details.

```json
{
  "error": "ValidationError",
  "message": "Request validation failed",
  "details": {
    "errors": [
      { "field": "spec.compute", "message": "value is not a valid enumeration member" }
    ]
  }
}
```

#### Error types

Use these error types and status codes to diagnose failed control plane requests.

| Error Type | HTTP | Description |
|------------|------|-------------|
| **NotFound** | 404 | Requested K8s resource doesn't exist |
| **Conflict** | 409 | Resource with the same name already exists |
| **ValidationError** | 400 | Request body validation failed (details.errors has field-level messages) |
| **AuthenticationDisabled** | 400 | API keys requested for a deployment with auth disabled |
| **InternalError** | 500 | Unexpected server error or K8s API failure |

#### Chat server error format (OpenAI-compatible)

Chat server errors follow the OpenAI-compatible error shape.

```json
{
  "error": {
    "message": "Request failed.",
    "type": "server_error",
    "code": "internal_error"
  }
}
```

#### Predictive server error format

Predictive server errors return either a standard detail message or a queue-capacity payload.

```json
// Standard errors:
{ "detail": "Model not loaded yet" }

// Queue full (includes Retry-After header):
{ "error": "Queue full: ...", "queue_depth": 100, "retry_after": 5 }
```

### OpenAPI and Swagger

Use these endpoints to inspect API schemas and test endpoints interactively.

| Service | Swagger UI | OpenAPI JSON |
|---------|------------|--------------|
| **Control Plane API** | http://\<host\>:8080/docs | http://\<host\>:8080/openapi.json |
| **Predictive Server** | http://\<host\>:8000/docs | http://\<host\>:8000/openapi.json |
| **Chat Server** | Not available | Not available |

## Related content

- [Inference API endpoints and payload reference for Foundry Local on Azure Local](reference-inference-api-endpoints-payload.md)
- [Authentication and authorization in Foundry Local enabled by Azure Arc](concept-authentication-authorization.md)
- [Configure TLS for Foundry Local on Azure Local](how-to-configure-tls-authentication.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
