---
title: "Deploy Your First Model and Run Inference on Foundry Local on Azure Local in a Disconnected Environment"
description: "Create your first model deployment and send inference requests by using the REST API in an existing Foundry Local environment."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 05/31/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to deploy and run my first model in an existing disconnected Foundry Local environment on Azure Local so that I can validate AI inference on my on-premises cluster.
---

# Deploy your first model in a disconnected environment

After you install the Foundry Local extension expansion pack, the `phi-4-mini` CPU is available as part of the base pack. This article shows you how to create your first deployment from the catalog.

[!INCLUDE [foundry-local-preview](../includes/foundry-local-preview.md)]

## Prerequisites

Make sure you followed the steps in [Prepare to deploy Foundry Local on Azure Local in disconnected environments](how-to-prepare.md) and [Deploy Foundry Local on Azure Local in a disconnected environment](deploy-platform.md) to set up your environment and deploy the Foundry Local extension.

## Generate access token and request headers

Run these commands to generate an access token and create the request headers that authenticate REST API calls to Foundry Local.

```powershell
$DisplayName = "FoundryOnArc-Disconnected"
$app = az ad app list --display-name $DisplayName --query "[0]" -o json | ConvertFrom-Json
$appId = $app.AppId

$token = az account get-access-token --resource "$appId" --query accessToken -o tsv
$headers = @{ "Authorization" = "Bearer $token" }

# If using ingress:
$baseUrl = "https://<FOUNDRY_API_BASE_PATH>/inference-api"

# If not using ingress, use the direct API endpoint instead:
# $baseUrl = "https://<FOUNDRY_API_BASE_PATH>"
```

## Create your first deployment (phi-4-mini CPU)

Run this request to create a phi-4-mini CPU deployment from the model catalog in your Foundry Local environment.

```powershell
$namespace = "foundry-local-operator"
$deploymentName = "phi4-cpu-demo"

$body = @{
  name = $deploymentName
  spec = @{
    displayName = "Phi 4 CPU Demo"
    model = @{
      catalog = @{
        name = "phi-4-mini"
      }
    }
    workloadType = "generative"
    compute = "cpu"
    runtime = "onnx-genai"
    replicas = 1
    port = 5000
    authentication = @{
      enabled = $true
    }
    endpoint = @{
      enabled = $true
      path = "/phi4-cpu-demo(/|$)(.*)"
      pathType = "ImplementationSpecific"
    }
  }
} | ConvertTo-Json -Depth 20

Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/namespaces/$namespace/deployments" `
  -Headers ($headers + @{ "Content-Type" = "application/json" }) `
  -Method POST `
  -Body $body
```

## Verify deployment

Run the following command to confirm the deployment exists and check whether it's moving to a ready state.

```powershell
Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/namespaces/$namespace/deployments/$deploymentName" `
  -Headers $headers `
  -Method GET
```

Expected result:

* Deployment exists and returns successfully from the GET request.
* Deployment status moves to ready state after model cache and pod startup complete.

## Related content

* [Troubleshoot Foundry Local on Azure Local in disconnected environments](how-to-troubleshoot.md)
* [Configure authentication and authorization for Foundry Local on Azure Local in disconnected environments](how-to-authenticate.md)
* [Expand model catalog for Foundry Local on Azure Local in disconnected environments](how-to-expand-catalog.md)
