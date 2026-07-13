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
ms.date: 06/23/2026
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
| `endpoint.exposure` | string | No | `internal` | Exposure mode for the Gateway API HTTPRoute. One of `internal` (route through the cluster-internal Gateway — the default when `exposure` is unset or when `endpoint` is omitted entirely), `external` (also attach the route to the external LoadBalancer Gateway), or `none` (no HTTPRoute; ClusterIP Service only). The legacy `endpoint.enabled` field is honored only when `exposure` is not set. | 
| `endpoint.enabled` | boolean | No | `false` | **Deprecated.** Retained for backward compatibility. When `true` and `exposure` is unset, the operator treats it as `exposure: internal`. New deployments should use `exposure` directly. | 
| `endpoint.host` | string | No | — | Hostname used by the HTTPRoute for host-based routing. Optional — leave unset to match on path only. | 
| `endpoint.path` | string | No | `/<deployment-name>` | URL path prefix served by the HTTPRoute. The operator matches with `PathPrefix` semantics. | 
| `endpoint.rewritePath` | string | No | `/` | Target path the prefix is rewritten to before forwarding to the backend. Replaces the old nginx `rewrite-target` annotation. | 
| `endpoint.gatewayAnnotations` | object | No | — | Implementation-specific annotations applied to the HTTPRoute (for example, Istio `networking.istio.io/*` overrides). | 
| `endpoint.ingressClassName` | string | No | — | **Deprecated and ignored.** Was used to select the nginx IngressClass; no longer in the data path. | 
| `endpoint.annotations` | object | No | — | **Deprecated and ignored.** Was used to pass nginx Ingress annotations; replaced by `endpoint.gatewayAnnotations`. | 
| `endpoint.tls.enabled` | boolean | No | `false` | Enable TLS for the per-deployment route. When `false`, TLS is still terminated by the Gateway listener using its own certificate. | 
| `endpoint.tls.secretName` | string | Conditional | — | Name of a `kubernetes.io/tls` secret in the same namespace. Required when `endpoint.tls.enabled: true`. | 
| `vllm.epp.enabled` | boolean | No | *replica-based* | Enable Endpoint Picker (EPP) intelligent routing for this vLLM deployment. **If unset, defaults to `true` when `replicas > 1` and `false` when `replicas == 1`.** An explicit value (`true` or `false`) always wins. The default re-evaluates on scaling: a deployment created at one replica with the field unset brings up the EPP stack the moment it is scaled to two or more, and tears it down again on scale-back. Requires `runtime: vllm`, the Gateway API Inference Extension CRDs, and Istio configured with `pilot.env.ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true`. See [Inference-aware routing with the Endpoint Picker (EPP)](concept-inference-runtimes.md#inference-aware-routing-with-the-endpoint-picker-epp). | 

### Annotation migration 

The nginx Ingress annotations that earlier releases honored on endpoint.annotations are no longer applied. Replace them with the Istio Gateway API equivalents on endpoint.gatewayAnnotations, the per-deployment HTTPRoute spec, or the cluster-wide external Gateway: 
  
| Old nginx annotation | New mechanism |
|---|---|
| `nginx.ingress.kubernetes.io/rewrite-target: /$2` | `spec.endpoint.rewritePath: "/"` (default already strips the prefix). |
| `nginx.ingress.kubernetes.io/proxy-body-size` | Configured on the Gateway listener via Istio `EnvoyFilter`, or on the route via `gatewayAnnotations`. |
| `nginx.ingress.kubernetes.io/proxy-read-timeout` / `proxy-send-timeout` |
| `endpoint.gatewayAnnotations.networking.istio.io/timeout` (Istio HTTPRoute timeout extension), or `spec.timeouts.request` on the HTTPRoute when emitted. |
| `nginx.ingress.kubernetes.io/configuration-snippet` | **Not portable.** Express the intent as Istio `VirtualService`, `EnvoyFilter`, or `BackendTLSPolicy`. |
| `cert-manager.io/cluster-issuer` | **Not applicable** — the operator issues certificates via cert-manager `Certificate` resources owned by the Gateway, not the HTTPRoute. |

### GPU configuration examples

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
| `endpointReady` | boolean | 'true' when the HTTPRoute is created and the parent Gateway has marked it Accepted. |
| `httpRouteReady` | boolean | `true` when the HTTPRoute resource exists and is bound to the internal Gateway. Mirrors `endpointReady` for clarity in Gateway API mode. | 
| `externalEndpoint` | string | External URL when exposure: external is set (populated once the external Gateway has assigned a LoadBalancer address).  |
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
# Gateway API networking defaults 
networking: 
  internalGateway: 
    gatewayName: inference-internal-gateway 
    gatewayClassName: istio 
    listenerName: https 
  externalGateway: 
    gatewayName: inference-external-gateway 
    gatewayClassName: istio 
    serviceType: LoadBalancer 
    listenerName: https 
    port: 443 
    # Annotations forwarded to the auto-created LoadBalancer Service. 
    # Default points the Azure LB health probe at Istio's /healthz/ready 
    # on port 15021 so the gateway's "404 on GET /" does not mark 
    # backends unhealthy. 
    annotations: 
      networking.istio.io/service-annotations: | 
        { 
          "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path": "/healthz/ready", 
          "service.beta.kubernetes.io/port_443_health-probe_port": "15021", 
          "service.beta.kubernetes.io/port_443_health-probe_protocol": "http" 
        } 
    tls: 
      # Customer-supplied TLS secret for external traffic termination. 
      # Leave empty to auto-issue from the internal CA. 
      secretName: "" 
  # EPP (Endpoint Picker) — shared infrastructure config used by every 
  # vLLM deployment that opts in via spec.vllm.epp.enabled. 
  epp: 
    image: 
      repository: mcr.microsoft.com/oss/v2/gateway-api-inference-extension/epp 
      tag: v1.3.1 
    replicas: 1 
    resources: 
      requests: { cpu: 250m, memory: 512Mi } 
      limits:   { cpu: "2",  memory: 2Gi } 
    targetPort: 8443 
    metricsDataSource: 
      scheme: https 
      insecureSkipVerify: true 
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
| `networking.internalGateway.gatewayName` | string | `inference-internal-gateway` | Name of the cluster-internal
Gateway the operator attaches HTTPRoutes to. |
| `networking.internalGateway.gatewayClassName` | string | `istio` | GatewayClass to use. Must match an installed
  Gateway API provider. |
| `networking.internalGateway.listenerName` | string | `https` | Listener (section) name on the internal Gateway. |
| `networking.externalGateway.gatewayName` | string | `inference-external-gateway` | Name of the external Gateway
created on demand when any deployment uses `exposure: external`. |
| `networking.externalGateway.gatewayClassName` | string | `istio` | GatewayClass for the external Gateway. |
| `networking.externalGateway.port` | integer | `443` | Port on the external LoadBalancer Service. |
| `networking.externalGateway.annotations` | object | *(Azure LB health probe defaults)* | Annotations applied to the
external Gateway, including `networking.istio.io/service-annotations` for cloud-provider Service settings. |
| `networking.externalGateway.tls.secretName` | string | `""` | TLS secret for external listener termination. Empty
means auto-issue from the internal CA when global TLS is enabled. |
| `networking.epp.image.repository` / `.tag` | string | `mcr.microsoft.com/oss/v2/gateway-api-inference-extension/epp`
/ `v1.3.1` | Container image used for every EPP instance. |
| `networking.epp.replicas` | integer | `1` | Number of EPP pod replicas per deployment that opts in. |
| `networking.epp.resources` | object | *(250m / 512Mi requests, 2 / 2Gi limits)* | Resource requests/limits for each
EPP pod. |
| `networking.epp.targetPort` | integer | `8443` | Pod port on the vLLM backend that EPP-selected traffic is forwarded
to. |
| `networking.epp.metricsDataSource.scheme` | string | `https` | Scheme used to scrape vLLM metrics for scoring. |
| `networking.epp.metricsDataSource.insecureSkipVerify` | boolean | `true` | Skip TLS verification on metrics scrape.
Keep `true` when the vLLM sidecar uses a self-signed cert from the internal CA. |
| `catalog.configmapName` | string | `foundry-local-catalog` | Name of the catalog ConfigMap. |
| `catalog.configmapNamespace` | string | `foundry-local-operator` | Namespace of the catalog ConfigMap. |
| `catalog.lazyRegistrationEnabled` | boolean | `true` | Automatically create Model CRs from catalog on first deployment. |

## Related content

- [Inference operator and model lifecycle](concept-inference-operator.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Inference API endpoints and payload reference](reference-inference-api-endpoints-payload.md)
