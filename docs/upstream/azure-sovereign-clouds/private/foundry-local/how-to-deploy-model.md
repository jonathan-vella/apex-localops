---
title: Deploy a catalog model on Foundry Local on Azure Local
description: List available models from the Foundry Local catalog and deploy one to your Kubernetes cluster by using kubectl or the REST API.
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 06/23/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to deploy a catalog model to my Foundry Local cluster so that I can serve AI inference workloads on-premises.
---

# Deploy a catalog model on Foundry Local

This article shows you how to list available models from the Foundry Local catalog and deploy one to your Kubernetes cluster. It covers both kubectl and REST API approaches.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, make sure you have:

- A running Foundry Local on Azure Local environment. 
- An active Azure subscription. If you don't have one, [create one](https://azure.microsoft.com/free/) before you begin.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed and configured for your cluster.
- Authentication configured. See [Configure authentication for Foundry Local Azure Arc Extension Deployment](/azure/azure-sovereign-clouds/private/foundry-local/how-to-configure-authentication).

## List available models

After you deploy Foundry Local and complete authentication, you can browse the model catalog. Foundry Local supports two approaches for managing models:

- **kubectl** — Work directly with Kubernetes custom resources (ModelDeployment CRDs).
- **Foundry Local REST API** — Use HTTP endpoints exposed by the inference operator.

### [kubectl](#tab/kubectl)

View the full model catalog to see which models are available for deployment:

```bash
kubectl get configmap foundry-local-catalog -n foundry-local-operator -o jsonpath="{.data['catalog\.json']}"
```

For a table-style catalog:

```powershell
kubectl get configmap foundry-local-catalog -n foundry-local-operator -o jsonpath="{.data['catalog\.json']}" | ConvertFrom-Json | Select-Object -ExpandProperty models | Format-Table alias, displayName, task, framework
```

### [REST API](#tab/rest-api)

Set up port forwarding to the API service:

```bash
kubectl port-forward -n foundry-local-operator svc/inference-operator-api 8080:8080
```

In a new terminal, obtain an access token for API authentication:

```bash
token=$(az account get-access-token --resource "<client-id>" --query accessToken -o tsv)
```

List the available models:

```bash
curl -k -s https://localhost:8080/api/v1/models -H "Authorization: Bearer $token"
```

Or in a table format:

```powershell
$response = curl -k -s https://localhost:8080/api/v1/models -H "Authorization: Bearer $token" | ConvertFrom-Json
$response.models | Format-Table alias, source, framework, @{L='compute';E={$_.supportedCompute -join ','}} -AutoSize
```

---

## Deploy a model

Choose the model you want from the catalog and create a deployment. 
A model is defined by its alias, runtime, and compute. Some models can run both through the onnx runtime and vLLM. Therefore, it's important to define the right runtime and compute, not only the alias.
Adjust CPU, memory, and GPU resource values based on your model size, quantization level, and expected concurrency. For CPU-only deployments, set `compute` to `cpu`, `runtime` to `onnx-genai`, and remove the `gpu` limit.

By default, you can reach the deployment from inside the cluster through the internal Gateway. To expose it outside the cluster (or to opt out of the Gateway route entirely), see Expose the deployment (#expose-the-deployment) below.*

### [kubectl](#tab/kubectl)

1. Create a YAML file (for example, `model-deployment.yaml`) with a ModelDeployment resource. Replace the placeholder values with the model name from the catalog and your desired configuration:

    ```yaml
    apiVersion: foundrylocal.azure.com/v1
    kind: ModelDeployment
    metadata:
      name: <deployment-name>
      namespace: foundry-local-operator
    spec:
      model:
        catalog:
          name: <model-name-from-catalog>
          version: "latest"
      compute: gpu              # or cpu
      runtime: vllm             # or onnx-genai
      workloadType: generative
      replicas: 1
      resources:
        requests:
          cpu: "2"
          memory: "32Gi"
        limits:
          cpu: "4"
          memory: "64Gi"
          gpu: 1
    ```

1. Apply the manifest to deploy the model:

    ```bash
    kubectl apply -f model-deployment.yaml
    ```

### [REST API](#tab/rest-api)

Send a POST request to create the deployment:

```bash
curl -k -X POST https://localhost:8080/api/v1/namespaces/foundry-local-operator/deployments \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{"name":"<deployment-name>","spec":{"model":{"catalog":{"name":"<model-name>","version":"latest"}},"workloadType":"generative","compute":"gpu","runtime":"vllm","replicas":1,"resources":{"requests":{"cpu":"2","memory":"8Gi"},"limits":{"cpu":"4","memory":"16Gi","gpu":1}},"authentication":{"enabled":true}}}'
```

---

## Expose the deployment 

By default, when you omit `spec.endpoint` or don't set `spec.endpoint.exposure`, the operator creates an HTTPRoute attached to the cluster-internal Gateway. Any pod in the cluster can reach the deployment at `https://<internal-gateway>/<deployment-name>` without extra configuration. Set `spec.endpoint.exposure` only when you want to change that default:

| Value | Behavior |
|---|---|
| `internal` *(default)* | The operator creates an HTTPRoute attached to the cluster-internal Gateway (`inference-internal-gateway`). Any pod in the cluster can reach the deployment at `https://<internal-gateway>/<deployment-name>`. This setting is the recommended default for service-to-service traffic and is what you get when `exposure` isn't set. |
| `external` | The operator creates (or reuses) the external Gateway (`inference-external-gateway`, type LoadBalancer) and attaches the same HTTPRoute to it. The deployment is reachable from outside the cluster. The external Gateway is created on demand the first time any deployment requests `external`, and deleted when the last one is removed. |
| `none` | No HTTPRoute is created. Only the ClusterIP Service exists. Use this value when you want the operator to manage the workload but route traffic yourself (for example through a custom HTTPRoute or service-mesh policy). |

```yaml
apiVersion: foundrylocal.azure.com/v1 
kind: ModelDeployment 
metadata: 
  name: phi-4-mini 
  namespace: foundry-local-operator 
spec: 
  model: 
    catalog: 
      name: Phi-4-mini-instruct 
      version: "latest" 
  workloadType: generative 
  compute: gpu 
  runtime: vllm 
  replicas: 1 
  endpoint: 
    exposure: external          # internal | external | none 
    # Optional: hostname for the route 
    host: phi-4-mini.example.com 
    # Optional: override the URL prefix (defaults to /<deployment-name>) 
    path: /phi-4 
    # Optional: pass implementation-specific annotations to the HTTPRoute 
    gatewayAnnotations: 
      networking.istio.io/timeout: "600s" 
```

Migrating from earlier releases. The operator still accepts `endpoint.enabled: true` (the previous toggle) for backward compatibility and maps it to `exposure: internal`. The operator accepts but ignores the legacy fields `endpoint.ingressClassName` and `endpoint.annotations` - these fields configured the nginx Ingress controller, which is no longer in the data path. If your deployment used `nginx.ingress.kubernetes.io/*` annotations, see [Annotation migration](reference-model-deployment-operator.md#annotation-migration) for the Gateway API equivalents.

TLS for external exposure. When you set `exposure: external`, the external Gateway terminates TLS by using either a customer-provided secret (`networking.externalGateway.tls.secretName` in the operator values) or, when that secret is empty and the cluster-wide TLS toggle is on, a certificate auto-issued from the internal CA. In-cluster traffic always uses the internal CA bundle. 

## Verify the deployment status

Confirm the model deployment is ready before sending inference requests. The deployment is ready when the ModelDeployment reaches the **Running** state.

### [kubectl](#tab/kubectl)

Check whether a specific model deployment is ready:

```bash
kubectl get modeldeployment <deployment-name> -n foundry-local-operator
```

For detailed status information including events and conditions:

```bash
kubectl describe modeldeployment <deployment-name> -n foundry-local-operator
```

To list all deployed models across all namespaces:

```bash
kubectl get modeldeployment -A
```

### [REST API](#tab/rest-api)

```bash
curl -k -s https://localhost:8080/api/v1/namespaces/foundry-local-operator/deployments/<deployment-name> \
  -H "Authorization: Bearer $token"
```

---

## Related content

- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [Package and deploy a bring-your-own model on Foundry Local](how-to-deploy-custom-model.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
