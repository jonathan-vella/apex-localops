---
title: "Deploy a Bring-Your-Own Model on Foundry Local on Azure Local"
description: "Package a custom model as an OCI artifact, push it to a registry, create credentials, and deploy it on Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 04/30/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to package and deploy a bring-your-own model on Foundry Local on Azure Local so that I can run a custom model from my own registry.
---

# Package and deploy a bring-your-own model on Foundry Local

This article shows you how to package a bring-your-own (BYO) model, push it to an OCI-compatible registry, and deploy it on Foundry Local on Azure Local.

Use this article when your model isn't available in the Foundry catalog and you want to deploy a custom, fine-tuned, or third-party model from your own registry.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, make sure that you have:

- A running Foundry Local on Azure Local environment. 
- `kubectl` installed and configured for your cluster.
- Access to an OCI-compatible registry, such as Azure Container Registry.
- ORAS installed. For installation steps, see [ORAS](https://oras.land/).
- A model package that matches the runtime and workload requirements. For packaging requirements and limitations, see [Bring your own models in Foundry Local on Azure Local](concept-bring-your-own-models.md).

## Choose a deployment pattern

Foundry Local on Azure Local supports two BYO deployment patterns:

- **Inline custom model**: Define the model source directly in the `ModelDeployment` resource. Use this option for a single deployment.
- **Named model resource**: Create a `Model` resource and reference it from one or more `ModelDeployment` resources. Use this option when you want to reuse the same model definition across deployments.

## Prepare your model files

Organize your model files in a directory that matches the runtime you want to use.

- For ONNX Runtime generative workloads, include the ONNX model file and required tokenizer and generation configuration files.
- For ONNX Runtime predictive workloads, include the ONNX model file.
- For vLLM workloads, include the Hugging Face model configuration, weights, and tokenizer files.

For detailed file requirements, see [Bring your own models in Foundry Local on Azure Local](concept-bring-your-own-models.md#model-file-format-requirements).

## Package and push the model

1. Organize your model files in a working directory.

   Example directory layout:

   ```text
   my-model/
     config.json
     model.safetensors
     tokenizer.json
     tokenizer_config.json
   ```

1. Package the model files as a `.tar.gz` archive.

   ```bash
   tar -czf my-model.tar.gz -C my-model .
   ```

1. Sign in to your registry and push the archive by using ORAS.

   ```bash
   oras login myregistry.azurecr.io -u <username> -p <password>
   oras push myregistry.azurecr.io/models/my-model:v1 my-model.tar.gz
   ```

The model cache job unpacks the `.tar.gz` archive after it pulls the artifact from your external registry.

## Create registry credentials in Kubernetes

Create a Kubernetes secret in the same namespace where you plan to deploy the model.

```bash
kubectl create secret generic my-registry-secret \
  -n foundry-local-operator \
  --from-literal=username=<registry-username> \
  --from-literal=password=<registry-password-or-token>
```

## Deploy the model by using inline custom model configuration

Use this option when you want to define the model source directly in the `ModelDeployment` manifest.

1. Create a file named `modeldeployment-byo-inline.yaml`.

   ```yaml
   apiVersion: foundrylocal.azure.com/v1
   kind: ModelDeployment
   metadata:
     name: my-custom-model
     namespace: foundry-local-operator
   spec:
     workloadType: generative
     compute: gpu
     runtime: vllm
     model:
       custom:
         registry: myregistry.azurecr.io
         repository: models/my-model
         tag: v1
         credentials:
           secretRef:
             name: my-registry-secret
             usernameKey: username
             passwordKey: password
     vllm:
       preferences:
         gpu_memory_utilization: 0.92
         max_model_len: 8192
     resources:
       requests:
         cpu: "2"
         memory: "8Gi"
       limits:
         cpu: "4"
         memory: "16Gi"
         gpu: 1

   ```

1. Apply the manifest.

   ```bash
   kubectl apply -f modeldeployment-byo-inline.yaml
   ```

## Deploy the model by using a named model resource

Use this option when you want to reuse the same model definition across multiple deployments.

1. Create a file named `model-byo.yaml`.

   ```yaml
   apiVersion: foundrylocal.azure.com/v1
   kind: Model
   metadata:
     name: my-custom-model
     namespace: foundry-local-operator
   spec:
     displayName: "My Custom Model"
     source:
       custom:
         registry: myregistry.azurecr.io
         repository: models/my-model
         tag: v1
         credentials:
           secretRef:
             name: my-registry-secret
             usernameKey: username
             passwordKey: password
     variants:
       - id: my-model-gpu
         compute: gpu
         priority: 10
     requirements:
       minMemory: "16Gi"
       minVRAM: "8Gi"
       supportedCompute: [gpu]
     capabilities:
       task: chat-completion
       streaming: true
   ```

1. Apply the model resource.

   ```bash
   kubectl apply -f model-byo.yaml
   ```

1. Create a file named `modeldeployment-byo-ref.yaml`.

   ```yaml
   apiVersion: foundrylocal.azure.com/v1
   kind: ModelDeployment
   metadata:
     name: my-custom-deployment
     namespace: foundry-local-operator
   spec:
     workloadType: generative
     compute: gpu
     runtime: vllm
     model:
       ref: my-custom-model
   resources:
    requests:
      cpu: "2"
      memory: "8Gi"
    limits:
      cpu: "4"
      memory: "16Gi"
      gpu: 1

   ```

1. Apply the deployment manifest.

   ```bash
   kubectl apply -f modeldeployment-byo-ref.yaml
   ```

## Verify the deployment

1. Check the `ModelDeployment` status.

   ```bash
   kubectl get modeldeployment -n foundry-local-operator
   kubectl describe modeldeployment my-custom-model -n foundry-local-operator
   ```

1. If you used a named model resource, check the `Model` status.

   ```bash
   kubectl get model -n foundry-local-operator
   kubectl describe model my-custom-model -n foundry-local-operator
   ```

1. Review pod status and model cache job progress.

   ```bash
   kubectl get pods -n foundry-local-operator
   kubectl get jobs -n foundry-local-operator
   ```

The deployment is ready when the `ModelDeployment` reaches the `Running` state.

## Troubleshoot common issues

- If the model cache job fails, verify the registry hostname, credentials, and artifact path.
- If validation fails, confirm that the package contains the required files for the selected runtime and workload type.
- If the deployment doesn't start, review the `ModelDeployment` status message and pod logs.

For model lifecycle details, see [Inference operator and model lifecycle in Foundry Local on Azure Local](concept-inference-operator.md). For field-level details, see [ModelDeployment and operator configuration reference for Foundry Local on Azure Local](reference-model-deployment-operator.md).

## Next steps

- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [Bring your own models in Foundry Local on Azure Local](concept-bring-your-own-models.md)
- [ModelDeployment and operator configuration reference for Foundry Local on Azure Local](reference-model-deployment-operator.md)
