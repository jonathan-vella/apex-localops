---
title: Evaluate a model on Foundry Local on Azure Local
description: Upload a test dataset, run evaluations, and download structured results for a deployed model on Foundry Local on Azure Local.
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 07/24/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to evaluate a deployed model by using structured evaluators so that I can measure response quality and compare model behavior in my environment.
---

# Evaluate a model on Foundry Local on Azure Local

This article shows you how to evaluate a deployed model by uploading a test dataset, running evaluations, and downloading structured results. Evaluations run entirely on the cluster. No data leaves the environment.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, make sure you have:

- A running Foundry Local on Azure Local environment.
- An active Azure subscription. If you don't have one, [create one](https://azure.microsoft.com/free/) before you begin.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed and configured for your cluster.
- [Azure CLI](/cli/azure/install-azure-cli) installed and signed in.
- At least one model deployed and in **Running** state. See [Deploy a catalog model](how-to-deploy-model.md).
- For quality evaluators, a second deployed model to use as a judge.
- Authentication configured. See [Configure authentication for Foundry Local Azure Arc Extension Deployment](how-to-configure-authentication.md).

## Step 1: Choose evaluators

Choose the evaluator type based on whether you want score-only text matching or judge-model quality scoring.

### NLP evaluators (no judge model required)

NLP evaluators compare the model response to a ground truth answer by using text-matching algorithms.

| Evaluator | Score range | Description |
|-----------|------------|-------------|
| `f1_score` | 0–1 | Token-level F1 score between response and ground truth |
| `bleu` | 0–1 | BLEU (Bilingual Evaluation Understudy) translation quality metric |
| `gleu` | 0–1 | GLEU (Google-BLEU) metric |
| `rouge` | 0–1 | ROUGE (Recall-Oriented Understudy for Gisting Evaluation) metric |
| `meteor` | 0–1 | METEOR (Metric for Evaluation of Translation with Explicit Ordering) metric |

### Quality evaluators (judge model required)

Quality evaluators use a second deployed model (the judge) to score responses.

| Evaluator | Score range | Description |
|-----------|------------|-------------|
| `coherence` | 1–5 | Measures the ability of the response to read naturally and flow smoothly |
| `fluency` | 1–5 | Measures the extent to which the response conforms to grammatical rules and vocabulary usage |
| `relevance` | 1–5 | Measures how well the response captures the key points and addresses the query |
| `similarity` | 1–5 | Measures semantic similarity between the response and the ground truth |
| `response_completeness` | 1–5 | Measures how thoroughly the response covers the information in the ground truth |

You can mix NLP and quality evaluators in the same run.

Safety evaluators (such as violence, self-harm, and hate/unfairness) aren't supported.

## Step 2: Prepare your dataset and evaluation settings

A dataset file must contain a `query` column and a `ground_truth` column. Foundry Local supports JSONL and CSV formats.

You don't need to provide a `response` column. The evaluation process automatically generates responses by calling the model under test.

### JSONL example

Use JSONL when you want one query-and-answer pair per line.

```jsonl
{"query": "What is the capital/major city of France?", "ground_truth": "Paris"}
{"query": "What atoms compose water?", "ground_truth": "Hydrogen and oxygen"}
{"query": "Who developed the theory of relativity?", "ground_truth": "Albert Einstein"}
```

### CSV example

Use CSV when you prefer tabular datasets that are easy to edit in spreadsheet tools.

```csv
query,ground_truth
"What is the capital/major city of France?","Paris"
"What atoms compose water?","Hydrogen and oxygen"
"Who developed the theory of relativity?","Albert Einstein"
```

### Dataset limits

Keep the following dataset limits in mind when you prepare files for upload.

- Maximum file size: 1 MB (default). Your platform administrator can change this setting.
- File encoding: UTF-8.
- Dataset names must be unique.

### Evaluation limits

The following limits apply when you create evaluation runs.

- Each run supports one to 10 evaluators.
- Evaluation names must be unique.
- Duplicate evaluators in the same run aren't allowed.

## Step 3: Set up API access

Set up port forwarding to the API service:

```powershell
kubectl port-forward -n foundry-local-operator svc/inference-operator-api 8080:8080
```

In a new terminal, obtain an access token for API authentication:

```powershell
$token = az account get-access-token --resource "<client-id>" --query accessToken -o tsv
$headers = @{ "Authorization" = "Bearer $token" }
$baseUrl = "https://localhost:8080"
```

## Step 4: Upload a dataset

Upload a dataset file to Foundry Local.

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

## Step 5: Run an evaluation

When you submit an evaluation:

- `datasetRef` is the dataset name from the upload step.
- `modelRef` is the deployment name of the model under test.
- `judgeModelRef` is the deployment name of the judge model (required only for quality evaluators).

### NLP evaluation (no judge model)

Use this request when you want to run only NLP evaluators that compare responses against ground truth.

```powershell
$body = @{
  name        = "nlp-eval"
  datasetRef  = "eval-dataset"
  modelRef    = "phi-4-mini"
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
  modelRef      = "phi-4-mini"
  judgeModelRef = "gpt-oss-20b"
  evaluators    = @("coherence", "fluency", "f1_score")
} | ConvertTo-Json

Invoke-WebRequest -UseBasicParsing `
  -Uri "$baseUrl/api/v1/evaluations" `
  -Method POST `
  -Headers ($headers + @{ "Content-Type" = "application/json" }) `
  -Body $body
```

## Step 6: Monitor evaluation status

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

## Step 7: Download results

After an evaluation succeeds, download the full per-row results.

### JSON format

Use JSON output when you need both aggregate metrics and detailed per-row results.

```powershell
Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/evaluations/quality-eval/results" `
  -Headers $headers `
  -OutFile "results.json"
```

The JSON file includes aggregate metrics and per-row scores with the model's generated response and judge reasoning for each query.

### CSV format

Use CSV output when you want per-row scores in a tabular format.

```powershell
Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/evaluations/quality-eval/results?format=csv" `
  -Headers $headers `
  -OutFile "results.csv"
```

The CSV file contains per-row results only, including per-row scores with the model's generated response and judge reasoning for each query. Aggregate metrics aren't included in the CSV format.

## Related content

- [Deploy a catalog model](how-to-deploy-model.md)
- [Inference API reference](reference-inference-api.md)
- [Troubleshoot Foundry Local on Azure Local](troubleshoot.md)
