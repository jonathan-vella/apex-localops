---
title: "ModelDeployment and operator configuration reference for Foundry Local on Azure Local"
description: "Reference for ModelDeployment CRD spec and status fields, and inference operator configuration settings in Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: reference
ms.author: cwatson
author: cwatson-cat
ms.date: 04/20/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want a complete reference for ModelDeployment fields and operator configuration so that I can deploy and configure AI inference workloads precisely.
---

# ModelDeployment and operator configuration reference for Foundry Local

This article is a reference for the `ModelDeployment` CRD spec and status fields, the `Model` CRD spec and status fields, and the inference operator configuration settings.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## ModelDeployment spec fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `displayName` | string | No | — | Human-readable deployment name. |
| `model` | object | Yes | — | Model reference. Set one of: `ref`, `catalog`, or `custom`. |
| `model.ref` | string | Conditional | — | Name of an existing Model CR to reference. |
| `model.catalog.name` | string | Conditional | — | Catalog model name. |
| `model.catalog.version` | string | No | latest | Catalog model version. |
| `model.custom` | object | Conditional | — | Inline custom model definition. |
| `workloadType` | string | Yes | — | `generative` or `predictive`. |
| `compute` | string | Yes | — | `cpu` or `gpu`. |
| `replicas` | integer | No | 1 | Number of pod replicas (1–100). |
| `port` | integer | No | 8080 | Container port (1024–65535). |
| `resources.requests.cpu` | string | No | `100m` | CPU request. |
| `resources.requests.memory` | string | No | `256Mi` | Memory request. |
| `resources.limits.cpu` | string | No | `1000m` | CPU limit. |
| `resources.limits.memory` | string | No | `1Gi` | Memory limit. |
| `resources.limits.gpu` | integer | No | — | Number of GPUs (0–8). |
| `runtime` | string | No | onnx-genai | Inference runtime: `onnx-genai` or `vllm`. vLLM requires `compute: gpu`. |
| `vllm` | object | No | - | vLLM-specific configuration. Only used when `runtime: vllm`. |
| `vllm.preferences` | object | No | - | vLLM engine argument overrides (open schema). See vLLM planner documentation |
| `Vllm.modelCacheStorageGi` | integer | No | 100 | Size of the model cache PVC in GiB (minimum 1). |
| `nodeSelector` | object | No | — | Node selector labels for pod scheduling. |
| `skipGpuResource` | boolean | No | `false` | Skip the `nvidia.com/gpu` limit. Requires `nodeSelector` when set to `true`. |
| `tolerations` | array | No | — | Pod tolerations. |
| `env` | array | No | — | Environment variables for the model container. |
| `endpoint.enabled` | boolean | No | `false` | Create an Ingress resource for this deployment. |
| `endpoint.host` | string | Conditional | — | Ingress hostname. Required when `endpoint.enabled: true`. |
| `endpoint.path` | string | No | Derived from deployment name | URL path for ingress routing. |
| `endpoint.pathType` | string | No | `ImplementationSpecific` | Ingress path matching type. |
| `endpoint.ingressClassName` | string | No | `nginx` | IngressClass name. |
| `endpoint.annotations` | object | No | — | Custom Ingress annotations. |
| `endpoint.tls.enabled` | boolean | No | `false` | Enable TLS on the Ingress resource. |
| `endpoint.tls.secretName` | string | Conditional | — | Name of the TLS secret. Required when `endpoint.tls.enabled: true`. |

### External endpoint examples

**Minimal ingress configuration:**

```yaml
spec:
  endpoint:
    enabled: true
    ingressClassName: nginx
    tls:
      enabled: false
```

The operator automatically derives the path as `/{deployment-name}(/|$)(.*)` with URL rewriting.

**With custom annotations:**

```yaml
spec:
  endpoint:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "50m"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
```

**GPU with skip GPU resource:**

```yaml
spec:
  compute: gpu
  skipGpuResource: true
  nodeSelector:
    kubernetes.io/gpu-partition: "1g.5gb"
```

> [!NOTE]
> To use `skipGpuResource: true`, set `nodeSelector`.

**GPU with node selector and tolerations:**

```yaml
spec:
  compute: gpu
  nodeSelector:
    accelerator: nvidia-a100
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
```

## ModelDeployment status fields

| Field | Type | Description |
|-------|------|-------------|
| `state` | string | Deployment state: `Pending`, `Creating`, `Running`, `Updating`, `Error`, or `Terminating`. |
| `message` | string | Human-readable status message. |
| `replicas.desired` | integer | Desired number of replicas. |
| `replicas.ready` | integer | Number of ready replicas. |
| `replicas.available` | integer | Number of available replicas. |
| `readyReplicas` | integer | Deprecated. Use replicats.ready instead. |
| `deploymentReady` | boolean | `true` when all replicas are ready. |
| `serviceReady` | boolean | `true` when the Service resource is created. |
| `internalEndpoint` | string | Internal cluster endpoint URL. |
| `endpointReady` | boolean | `true` when the Ingress is ready (if enabled). |
| `externalEndpoint` | string | External URL (populated if Ingress is enabled). |
| `resolvedModel.name` | string | Name of the resolved Model CR. |
| `resolvedModel.variant` | string | Selected variant ID. |
| `resolvedModel.image` | string | Container image used for this deployment. |
| `authentication.keysSecretName` | string | Name of the secret containing API keys. |
| `conditions` | array | Detailed status conditions. |
| `lastUpdated` | datetime | Timestamp of last status update. |

## Model CRD spec fields

The Model CRD is for BYO (custom) models only. Catalog models are resolved from the catalog ConfigMap and do not use this CRD. To deploy a catalog model, use model.catalog in the ModelDeployment spec instead.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `displayName` | string | No | Human-readable model name. |
| `description` | string | No | Model description. |
| `publisher` | string | No | Model publisher. |
| `license` | string | No | License identifier. |
| `licenseUrl` | string | No | URL to the full license text. |
| `source` | object | Yes | Model source configuration. |
| `source.type` | string | Yes | `catalog` or `custom`. |
| `source.catalog.alias` | string | Conditional | Catalog model alias. Required when `source.type: catalog`. |
| `source.catalog.modelId` | string | Conditional | Full catalog model ID. |
| `source.custom.registry` | string | Conditional | OCI registry URL. Required when `source.type: custom`. |
| `source.custom.repository` | string | Conditional | Repository path in the registry. |
| `source.custom.tag` | string | Conditional | Image tag. |
| `source.custom.credentials.secretRef.name` | string | Conditional | Name of the Kubernetes secret with registry credentials. |
| `variants` | array | No | Hardware-specific variant overrides. |
| `requirements` | object | No | Resource requirements. |
| `capabilities` | object | No | Model capabilities. |

## Model CRD status fields

| Field | Type | Description |
|-------|------|-------------|
| `phase` | string | Model phase: `Pending`, `Available`, or `Error`. |
| `message` | string | Human-readable status message. |
| `catalogSync.lastSynced` | datetime | Timestamp of the last catalog sync. |
| `catalogSync.syncStatus` | string | `Syncing`, `Synced`, or `Error`. |
| `conditions` | array | Detailed status conditions. |
| `lastUpdated` | datetime | Timestamp of last status update. |

## Inference operator configuration

The inference operator reads its configuration from a ConfigMap mounted at `/etc/inference-operator/config.yaml`.

### Configuration file example

```yaml
# Container registry for inference images
registry: "myregistry.azurecr.io"

# Container images for different workload types
images:
  generative_cpu:
    repository: generative-cpu
    tag: "latest"
  generative_gpu:
    repository: generative-gpu
    tag: "latest"
  predictive_cpu_oras:
    repository: predictive-cpu-byo
    tag: "latest"
  predictive_gpu_oras:
    repository: predictive-gpu-byo
    tag: "latest"
  Vllm_gpu:
    repository: vllm-server
    tag: "latest"


# Ingress defaults
ingress:
  pathTemplate: "/{name}(/|$)(.*)"
  rewritePathTemplate: "/$2"
  pathType: "ImplementationSpecific"
  ingressClassName: "nginx"

# Catalog settings
catalog:
  configmapName: "foundry-local-catalog"
  configmapNamespace: "foundry-local-operator"
```

### Configuration fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `registry` | string | `""` | Container registry prefix for inference images. |
| `images.<type>.repository` | string | Varies by workload type | Image repository path. Types: `generative_cpu`, `generative_gpu`, `generative_cpu_oras`, `generative_gpu_oras`, `predictive_cpu_oras`, `predictive_gpu_oras`, `vllm_gpu`.|
| `images.<type>.tag` | string | `latest` | Image tag. |
| `ingress.pathTemplate` | string | `/{name}(/\|$)(.*)` | Ingress path template. `{name}` is replaced with the deployment name. |
| `ingress.rewritePathTemplate` | string | `/$2` | Rewrite target path for NGINX. |
| `ingress.pathType` | string | `ImplementationSpecific` | Ingress path matching type. |
| `ingress.ingressClassName` | string | `nginx` | Default IngressClass name. |
| `catalog.configmapName` | string | `foundry-local-catalog` | Name of the catalog ConfigMap. |
| `catalog.configmapNamespace` | string | `foundry-local-operator` | Namespace of the catalog ConfigMap. |
| `catalog.lazyRegistrationEnabled` | boolean | `true` | Automatically create Model CRs from catalog on first deployment. |

## Related content

- [Inference operator and model lifecycle](concept-inference-operator.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Inference API endpoints and payload reference](reference-inference-api-endpoints-payload.md)
