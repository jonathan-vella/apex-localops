---
title: "Run inference on Foundry Local on Azure Local"
description: "Retrieve API keys and send inference requests to deployed models on Foundry Local on Azure Local, including bring-your-own model scenarios."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 04/30/2026
ai-usage: ai-assisted
customer intent: As a developer, I want to send inference requests to models deployed on Foundry Local on Azure Local so that I can integrate AI capabilities into my applications.
---

# Run inference on Foundry Local

This article shows you how to retrieve API keys and send inference requests to models deployed on Foundry Local on Azure Local. It covers catalog model deployments on CPU and GPU, and bring-your-own (BYO) model scenarios.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, you must have the following resources:

- A running model deployment. For deployment steps, see [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md). Helm is also a supported deployment option, and installation instructions are provided during preview access onboarding.
- The endpoint URL for your deployment, with or without an ingress controller.
- kubectl installed and configured for your cluster.

## Run inference on a catalog model

The following steps use Phi-4 as an example. Substitute your deployment name and model ID as needed.

### Step 1: Authenticate

Foundry Local on Azure Local supports two authentication methods: API key authentication and Microsoft Entra ID JSON Web Token (JWT) authentication. Choose the method that fits your scenario.

#### Option A: API key authentication (default) 

Each model deployment has a primary and secondary API key stored in a Kubernetes Secret. Retrieve the key and pass it in the `Authorization: Bearer` header. Select the CPU or GPU section that matches the compute value in your ModelDeployment.

##### [CPU — Bash](#tab/bash)

```bash
API_KEY=$(kubectl get secret phi-4-cpu-api-keys -n foundry-local-operator \
  -o jsonpath='{.data.primary-key}' | base64 -d)
```

##### [CPU — PowerShell](#tab/powershell)

```powershell
$API_KEY = kubectl get secret phi-4-cpu-api-keys -n foundry-local-operator `
  -o jsonpath='{.data.primary-key}' | ForEach-Object {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))
  }
```

---

#### [GPU — Bash](#tab/bash)

```bash
API_KEY=$(kubectl get secret phi-4-gpu-api-keys -n foundry-local-operator \
  -o jsonpath='{.data.primary-key}' | base64 -d)
```

##### [GPU — PowerShell](#tab/powershell)

```powershell
$API_KEY = kubectl get secret phi-4-gpu-api-keys -n foundry-local-operator `
  -o jsonpath='{.data.primary-key}' | ForEach-Object {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))
  }
```

---

#### Option B: Entra ID (JWT) authentication 

When you enable Entra ID authentication, acquire a JWT token from Microsoft Entra ID scoped to the Foundry application registration audience. Use the same `Authorization: Bearer` header - the platform detects the credential type automatically. 

##### [Bash](#tab/bash)

```bash
JWT_TOKEN=$(az account get-access-token \
  --resource api://<ENTRA_CLIENT_ID> \
  --query accessToken -o tsv)
```

##### [PowerShell](#tab/powershell)

```powershell
$JWT_TOKEN = az account get-access-token `
  --resource "api://<ENTRA_CLIENT_ID>" `
  --query accessToken -o tsv
```

---

Then use `$JWT_TOKEN` (or `$env:JWT_TOKEN`) in place of `$API_KEY` in the inference calls below. The `Authorization: Bearer` header accepts both API keys and JWTs.

Entra ID authentication requires the [Cognitive Services OpenAI User role](/azure/role-based-access-control/built-in-roles/ai-machine-learning#cognitive-services-openai-user) (or equivalent) assigned to the caller identity on the cluster scope. API key authentication grants full access without role checks.

### Step 2: Call the inference endpoint

In this step, you send a chat completions request to your deployed model endpoint and confirm that it returns a response.

#### [CPU — With ingress — Bash](#tab/bash)

```bash
# URI uses the model's metadata.name value
curl -k -X POST "https://<YOUR_INGRESS_ADDRESS>/phi-4-cpu/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Phi-4-generic-cpu:1",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is the capital/major city of France? Reply in one sentence."}
    ],
    "max_tokens": 50
  }'
```

#### [CPU — With ingress — PowerShell](#tab/powershell)

```powershell
$body = @{
  model    = "Phi-4-generic-cpu:1"
  messages = @(
    @{ role = "system"; content = "You are a helpful assistant." }
    @{ role = "user";   content = "What is the capital/major city of France? Reply in one sentence." }
  )
  max_tokens = 50
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "https://<YOUR_INGRESS_ADDRESS>/phi-4-cpu/v1/chat/completions" `
  -Method POST -ContentType "application/json" -Body $body `
  -Headers @{ "Authorization" = "Bearer $API_KEY" } -SkipCertificateCheck
```

---

#### [GPU — With ingress — Bash](#tab/bash)

```bash
# URI uses the model's metadata.name value
curl -k -X POST "https://<YOUR_INGRESS_ADDRESS>/phi-4-gpu/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Phi-4-cuda-gpu:1",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is the capital/major city of France? Reply in one sentence."}
    ],
    "max_tokens": 50
  }'
```

#### [GPU — With ingress — PowerShell](#tab/powershell)

```powershell
$body = @{
  model    = "Phi-4-cuda-gpu:1"
  messages = @(
    @{ role = "system"; content = "You are a helpful assistant." }
    @{ role = "user";   content = "What is the capital/major city of France? Reply in one sentence." }
  )
  max_tokens = 50
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "https://<YOUR_INGRESS_ADDRESS>/phi-4-gpu/v1/chat/completions" `
  -Method POST -ContentType "application/json" -Body $body `
  -Headers @{ "Authorization" = "Bearer $API_KEY" } -SkipCertificateCheck
```

---

> [!NOTE]
> When you use an ingress controller, the `-k` flag (curl) and `-SkipCertificateCheck` (PowerShell) skip certificate validation because these examples use self-signed certificates. In production, configure proper TLS certificates.

#### [CPU — Without ingress](#tab/no-ingress)

```bash
kubectl run curl-run --rm -it --restart=Never --image=curlimages/curl \
  -n foundry-local-operator -- \
  curl -ks -X POST \
    "https://phi-4-cpu.foundry-local-operator.svc.cluster.local:5000/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "Phi-4-generic-cpu:1", "messages": [{"role": "system", "content": "You are a helpful assistant."},{"role": "user", "content": "What is the capital/major city of France? Reply in one sentence."}], "max_tokens": 50}'
```

#### [GPU — Without ingress](#tab/gpu-no-ingress)

```bash
kubectl run curl-run --rm -it --restart=Never --image=curlimages/curl \
  -n foundry-local-operator -- \
  curl -ks -X POST \
    "https://phi-4-gpu.foundry-local-operator.svc.cluster.local:5000/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "Phi-4-cuda-gpu:1", "messages": [{"role": "system", "content": "You are a helpful assistant."},{"role": "user", "content": "What is the capital/major city of France? Reply in one sentence."}], "max_tokens": 50}'
```

---

### Expected response

The following example shows a successful chat completions response from a catalog model deployment.

```json
{
  "model": "Phi-4-generic-cpu:1",
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

## Run inference with a bring-your-own (BYO) model

Use these steps to deploy a custom model from your own OCI registry and run inference against it.

### Step 1: Create a registry secret

Create a Kubernetes secret with your registry credentials so the cluster can pull your model image.

```bash
kubectl create secret generic registry-credentials \
  -n foundry-local-operator \
  --from-literal=username='<username>' \
  --from-literal=password='<password>'
```

### Step 2: Deploy the BYO model

Create a file named `modeldeployment-<your-model>.yaml`. This example shows a CPU deployment:

```yaml
apiVersion: foundrylocal.azure.com/v1
kind: ModelDeployment
metadata:
  name: <model-name>-byo-cpu
  namespace: foundry-local-operator
  labels:
    app.kubernetes.io/name: <model-name>-byo-cpu
    app.kubernetes.io/component: inference
    foundry.azure.com/hardware: cpu
    foundry.azure.com/source: custom
spec:
  displayName: "<Model Name> BYO CPU"
  model:
    custom:
      registry: <registry-name>
      repository: <repo-name>
      tag: <tag>
      credentials:
        secretRef:
          name: registry-credentials
          usernameKey: username
          passwordKey: password
  workloadType: generative
  compute: cpu
  replicas: 1
  resources:
    requests:
      cpu: "4"
      memory: "16Gi"
    limits:
      cpu: "8"
      memory: "32Gi"
  # Required only if you use an ingress controller
  endpoint:
    enabled: true
    host: <YOUR_INGRESS_ADDRESS>
```

Apply the manifest:

```bash
kubectl apply -f modeldeployment-<your-model>.yaml
```

Verify the deployment:

```bash
kubectl get modeldeployments -A

# If you use an ingress controller
kubectl get ingress -A
```

Wait for **State** to show `Running` and **Ready** to show `true`. The model downloads from the internet during this step, so it might take some time depending on your connection.

### Step 3: Authenticate

Get an access credential for your BYO deployment by using either an API key or an Entra ID JWT.

### Option A: API key authentication

Retrieve the primary API key from the Kubernetes Secret created for your deployment and pass it in the `Authorization: Bearer` header.

#### [Bash](#tab/bash)

```bash
API_KEY=$(kubectl get secret <your-model>-api-keys -n foundry-local-operator \
  -o jsonpath='{.data.primary-key}' | base64 -d)
```

#### [PowerShell](#tab/powershell)

```powershell
$API_KEY = kubectl get secret <your-model>-api-keys -n foundry-local-operator `
  -o jsonpath='{.data.primary-key}' | ForEach-Object {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))
  }
```

---

#### Option B: Entra ID (JWT) authentication

When you enable Entra ID authentication, acquire a JWT token from Microsoft Entra ID scoped to the Foundry application registration audience.

##### [Bash](#tab/bash)

```bash
JWT_TOKEN=$(az account get-access-token \
  --resource api://<ENTRA_CLIENT_ID> \
  --query accessToken -o tsv)
```

##### [PowerShell](#tab/powershell)

```powershell
$JWT_TOKEN = az account get-access-token `
  --resource "api://<ENTRA_CLIENT_ID>" `
  --query accessToken -o tsv
```

---

### Step 4: Call the inference endpoint

Choose the endpoint that matches your deployment compute type. Then, send a chat completions request with your API key or JWT token to confirm the model responds.

#### [With ingress — Bash](#tab/bash)

```bash
curl -k -X POST "https://<YOUR_INGRESS_ADDRESS>/<your-model>-cpu/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<your-model>:<tag>",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is the capital/major city of France? Reply in one sentence."}
    ],
    "max_tokens": 50
  }'
```

#### [With ingress — PowerShell](#tab/powershell)

```powershell
$body = @{
  model    = "<your-model>:<tag>"
  messages = @(
    @{ role = "system"; content = "You are a helpful assistant." }
    @{ role = "user";   content = "What is the capital/major city of France? Reply in one sentence." }
  )
  max_tokens = 50
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "https://<YOUR_INGRESS_ADDRESS>/<your-model>-cpu/v1/chat/completions" `
  -Method POST -ContentType "application/json" -Body $body `
  -Headers @{ "Authorization" = "Bearer $API_KEY" } -SkipCertificateCheck
```

---

#### Without ingress

```bash
kubectl run curl-run --rm -it --restart=Never --image=curlimages/curl \
  -n foundry-local-operator -- \
  curl -ks -X POST \
    "https://<your-model>-cpu.foundry-local-operator.svc.cluster.local:5000/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "<your-model>:<tag>", "messages": [{"role": "system", "content": "You are a helpful assistant."},{"role": "user", "content": "What is the capital/major city of France? Reply in one sentence."}], "max_tokens": 50}'
```

> [!NOTE]
> The example uses self-signed certificates, so it includes the `-k` flag for curl and the `-SkipCertificateCheck` flag for PowerShell. In production, configure proper TLS certificates.

### Expected response

The following example shows a successful chat completions response from a bring-your-own model deployment.

```json
{
  "model": "<your-model>:<tag>",
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

## Related content

- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Configure TLS for Foundry Local on Azure Local](how-to-configure-tls-authentication.md)
- [Inference API endpoints and payload reference](reference-inference-api-endpoints-payload.md)
- [Inference operator and model lifecycle](concept-inference-operator.md)
- [OpenAI Chat Completions API reference](https://developers.openai.com/api/reference/chat-completions/overview)

