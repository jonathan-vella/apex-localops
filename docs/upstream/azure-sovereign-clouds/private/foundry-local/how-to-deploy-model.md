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
ms.date: 05/19/2026
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
