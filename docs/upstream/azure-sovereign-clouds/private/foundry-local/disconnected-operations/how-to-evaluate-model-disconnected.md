---
title: Evaluate a model in Foundry Local on Azure Local in a disconnected environment
description: Upload a test dataset, run evaluations, and download results for a deployed model in a disconnected Foundry Local environment.
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 07/24/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to evaluate deployed models in a disconnected Foundry Local environment so that I can measure model quality without internet connectivity.
---

# Evaluate a model in Foundry Local on Azure Local in a disconnected environment

After you deploy a model in a disconnected environment, you can evaluate its quality by running structured evaluations against a test dataset. The evaluation runs entirely on the cluster. No data leaves the environment, and no internet connectivity is required.

For supported evaluators, dataset format, and limits, see [Evaluate a model on Foundry Local on Azure Local](../how-to-evaluate-model.md).

[!INCLUDE [foundry-local-preview](../includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, make sure you complete the following prerequisites:

- [Prepare to deploy Foundry Local on Azure Local in disconnected environments](how-to-prepare.md).
- [Deploy Foundry Local on Azure Local in a disconnected environment](deploy-platform.md).
- [Configure authentication and authorization for Foundry Local on Azure Local in disconnected environments](how-to-authenticate.md).
- At least one model deployed and in **Running** state. See [Deploy your first model](how-to-deploy-first-model.md).
- For quality evaluators, deploy a second model to use as a judge.

## Generate access token and request headers

Run these commands to generate an access token and create the request headers that authenticate REST API calls to Foundry Local.

```powershell
$DisplayName = "FoundryOnArc-Disconnected"
$app = az ad app list --display-name $DisplayName --query "[0]" -o json | ConvertFrom-Json
$appId = $app.AppId

$token = az account get-access-token --resource "$appId" --query accessToken -o tsv
$headers = @{ "Authorization" = "Bearer $token" }

# If using gateway api:
$baseUrl = "https://<FOUNDRY_API_BASE_PATH>/inference-api"

# If not using ingress, use the direct API endpoint instead:
# $baseUrl = "https://<FOUNDRY_API_BASE_PATH>"
```

## Upload a dataset

Upload a dataset file to Foundry Local. The file must contain a `query` column and a `ground_truth` column in JSONL or CSV format.

```powershell
$datasetName = "eval-dataset"
$filePath = "<PATH_TO_DATASET_FILE>"
$format = "jsonl"  # or "csv"

$fileBytes = [System.IO.File]::ReadAllBytes($filePath)
$fileName = Split-Path $filePath -Leaf
$boundary = [System.Guid]::NewGuid().ToString()

$body = @(
    "--$boundary",
    "Content-Disposition: form-data; name=`"name`"", "", $datasetName,
    "--$boundary",
    "Content-Disposition: form-data; name=`"format`"", "", $format,
    "--$boundary",
    "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"",
    "Content-Type: application/octet-stream", "",
    [System.Text.Encoding]::UTF8.GetString($fileBytes),
    "--$boundary--"
) -join "`r`n"

Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/datasets" `
  -Method POST `
  -Headers $headers `
  -ContentType "multipart/form-data; boundary=$boundary" `
  -Body $body
```

### Verify dataset upload

Run the following command to confirm that your dataset is uploaded and ready.

```powershell
Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/datasets/$datasetName" `
  -Headers $headers
```

Expected result: `phase` is `Ready` and `rowCount` shows the number of rows in your dataset.

## Run an evaluation

When you submit an evaluation:

- `datasetRef` is the dataset name from the upload step.
- `modelRef` is the deployment name of the model under test (the `name` field from [Deploy your first model](how-to-deploy-first-model.md)).
- `judgeModelRef` is the deployment name of the judge model (required only for quality evaluators).

### NLP evaluation (no judge model)

Use this request when you want to run only NLP evaluators that compare responses against ground truth.

```powershell
$body = @{
  name        = "nlp-eval"
  datasetRef  = "eval-dataset"
  modelRef    = "phi4-cpu-demo"
  evaluators  = @("f1_score", "bleu", "rouge")
} | ConvertTo-Json

Invoke-WebRequest -UseBasicParsing `
  -Uri "$baseUrl/api/v1/evaluations" `
  -Method POST `
  -Headers ($headers + @{ "Content-Type" = "application/json" }) `
  -Body $body
```

### Quality evaluation (with judge model)

Use this request when you want a judge model to score output quality dimensions.

```powershell
$body = @{
  name          = "quality-eval"
  datasetRef    = "eval-dataset"
  modelRef      = "phi4-cpu-demo"
  judgeModelRef = "gpt-oss-20b"
  evaluators    = @("coherence", "fluency", "f1_score")
} | ConvertTo-Json

Invoke-WebRequest -UseBasicParsing `
  -Uri "$baseUrl/api/v1/evaluations" `
  -Method POST `
  -Headers ($headers + @{ "Content-Type" = "application/json" }) `
  -Body $body
```

### Monitor evaluation status

Poll the evaluation status until the phase reaches `Succeeded` or `Failed`.

```powershell
Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/evaluations/quality-eval" `
  -Headers $headers
```

When the evaluation completes, you see the following results:

- `phase` is `Succeeded`.
- `metrics` contains aggregate scores for each evaluator.
- `startTime` and `completionTime` show when the evaluation ran.

## Download results

After an evaluation succeeds, download the full per-row results.

```powershell
Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/evaluations/quality-eval/results" `
  -Headers $headers `
  -OutFile "results.json"
```

The JSON results include aggregate metrics and per-row scores with the model's generated response and judge reasoning for each query. To download as CSV, append `?format=csv` to the URL.

## Related content

- [Evaluate a model on Foundry Local on Azure Local](../how-to-evaluate-model.md) — full evaluator reference, dataset formats, and limits.
- [Deploy your first model in a disconnected environment](how-to-deploy-first-model.md)
- [Troubleshoot Foundry Local on Azure Local](../troubleshoot.md)
