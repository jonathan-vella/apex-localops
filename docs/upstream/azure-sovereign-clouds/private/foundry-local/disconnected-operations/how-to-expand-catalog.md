---
title: "Expand Model Catalog for Foundry Local on Azure Local Deployment in Disconnected Mode"
description: "Expand the Model Catalog for your Foundry Local on Azure Local deployment in a disconnected environment."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 05/31/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to expand the model catalog for my Foundry Local disconnected environment.
---

# Expand model catalog in disconnected mode

To make more models available in a disconnected environment, transfer and install the corresponding model expansion packs into the Azure Local disconnected deployment. Each model is distributed as a separate expansion pack.

This article covers model expansion packs. For the Foundry Local extension expansion pack, see [Prepare to deploy Foundry Local on Azure Local in disconnected environments](how-to-prepare.md).

## Prerequisites

Before you begin, make sure you complete the following prerequisites:

- [Prepare to deploy Foundry Local on Azure Local in disconnected environments](how-to-prepare.md).
- [Deploy Foundry Local on Azure Local in a disconnected environment](deploy-platform.md).
- [Configure authentication and authorization for Foundry Local on Azure Local in disconnected environments](how-to-authenticate.md).
- Have the model expansion pack zip file for each model that you want to add.
- Have valid request headers and a Foundry API base path for your environment.

## Install model expansion pack

Install each model expansion pack on the Azure Local disconnected operations machine.

1. Transfer each model expansion pack zip file to the disconnected Azure Local environment.
1. Validate each package name before installation to confirm the expected model and publish version.

   `azurelocal.pxp.foundrylocal.<MODEL_NAME>.model.<PUBLISH_VERSION>.zip`
 
   Example:
 
   `azurelocal.pxp.foundrylocal.phi-3.5-mini.gpu.model.1.2605.12.zip`

1. Replace `<PATH_TO_MODEL_EXPANSION_PACK_ZIP>` and `<PATH_TO_ALDO_MODULES>` in the following script, and then run the commands.

   ```powershell
   Import-Module "<PATH_TO_ALDO_MODULES>\Azure.Local.ExpansionPack.psm1"
   
   $expansionPackId = Start-AldoExpansionPackUpload `
     -ExpansionPackPath "<PATH_TO_MODEL_EXPANSION_PACK_ZIP>"
   
   $result = Start-AldoExpansionPackInstallation `
     -ExpansionPackId $expansionPackId `
     -Wait
   ```

Repeat this process for each model expansion pack that you want to install.

After installation, the model artifacts are imported into the `edgeartifacts` container registry.

## Check pack status with Get-ApplianceExpansionPackDetails

After each model expansion pack installation, verify the pack state on the `Azure Local Disconnected Operations` machine:

```powershell
Get-ApplianceExpansionPackDetails
```

Confirm the newly installed model pack is in the `Installed` state before running model sync.

## Run model sync by using the REST API

After the expansion packs are installed successfully, trigger a model synchronization operation to refresh the model catalog and make the newly installed models available for use.

Use the following PowerShell command to initiate the synchronization. Replace `<FOUNDRY_API_BASE_PATH>` with the appropriate value for your environment.

```powershell
$baseUrl = "https://<FOUNDRY_API_BASE_PATH>"

Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/models/sync" `
  -Headers $headers `
  -Method POST
```

## Confirm models appear in the catalog

After the synchronization completes, the newly installed models appear in the model catalog and you can enable them for deployment and inference workloads.
Verify model sync completed and the model is visible in the catalog:

```powershell
Invoke-RestMethod `
  -Uri "$baseUrl/api/v1/models" `
  -Headers $headers `
  -Method GET
```

## Related content

- [Deploy your first model in a disconnected environment](how-to-deploy-first-model.md)
- [Configure authentication and authorization for Foundry Local on Azure Local in disconnected environments](how-to-authenticate.md)
- [Troubleshoot Foundry Local on Azure Local in disconnected environments](how-to-troubleshoot.md)