---
title: "Prepare to Deploy Foundry Local on Azure Local in a Disconnected Environment"
description: "Fulfill prerequisites and download and import the Foundry Local extension expansion pack to prepare for deployment in a disconnected environment."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 06/23/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to fulfill the prerequisites and download and import the required expansion pack to deploy Foundry Local as an Azure Arc extension in my disconnected environment.
---

# Prepare to deploy Foundry Local on Azure Local in disconnected environments

This article outlines the prerequisites and steps to download and import the Foundry Local extension expansion pack in preparation for deployment in a disconnected environment.

[!INCLUDE [foundry-local-preview](../includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, complete the following checks:

* Azure Local Disconnected Operations is installed on-premises. The minimum supported version is `2604.3.0`.
* An AKS Arc cluster on Azure Local, registered with Azure Arc as a `connectedClusters` resource.

    | Requirement | Minimum | Recommended |
    |---|---|---|
    | Worker node VM size | Standard_D4s_v3 (4 vCPU / 16 GiB) | Standard_D8s_v3 (8 vCPU / 32 GiB) |
    | Allocatable memory/node | >= 14 GiB | >= 28 GiB |
    | Worker node count | 1 | 2+ (HA or GPU pool separation) |
    | Logical network | Reachable from edgeartifacts ACR | - |

    If you plan to run multireplica `vLLM` deployments, reserve extra capacity for one EPP pod per ModelDeployment (about 512 MiB request and 2 GiB limit). For default behavior and tunables, see [ModelDeployment and operator configuration reference](../reference-model-deployment-operator.md).

    Don't use the `az aksarc create` default worker size `Standard_A4_v2` (8 GiB). Use at least `Standard_D4s_v3`.

* (Optional) GPU node pool (required only for GPU model variants such as `*-cuda-gpu` and `vLLM`):
    * NVIDIA DDA-passthrough SKU: `Standard_NC*_A2`, `Standard_NC*_L4_*`, `Standard_NC*_L40_*`, `Standard_NC*_L40S_*`, `Standard_NC*_RTX6000Pro_*`, or Tesla T4 `Standard_NK*`. AMD GPUs aren't supported.
    * NVIDIA mitigation INF is installed on the physical Azure Local node.
    * `nvidia/k8s-device-plugin:v0.11.0` is mirrored into the `edgeartifacts` container registry at the path expected by the auto-deployed DaemonSet.

For disconnected architecture and bundled dependency details, see [Foundry Local on Azure Local in disconnected environments overview](concept-overview.md).

## Download and import the Foundry Local expansion pack

Download the Foundry Local extension expansion pack in a connected environment, transfer it to your disconnected environment, and then install it on the Azure Local Disconnected Operations machine.

1. Download the latest [Foundry Local extension expansion pack](https://aka.ms/azurelocal-pxp-microsoft-foundrylocal-k8sextension).
   For additional versions and release notes, see the [Foundry Local Disconnected Catalog](https://aka.ms/azure-local-disconnected-operations-foundrylocal).
1. Transfer the expansion pack to the disconnected Azure Local environment.
1. Run the following commands on the `Azure Local Disconnected Operations` machine to install the expansion pack.

    Replace `<PATH_TO_EXPANSION_PACK>` with the local path to the expansion pack zip file and `<PATH_TO_ALDO_MODULES>` before you run the command.

    ```powershell
    Import-Module "<PATH_TO_ALDO_MODULES>\Azure.Local.ExpansionPack.psm1"
    
    $expansionPackId = Start-AldoExpansionPackUpload `
        -ExpansionPackPath "<PATH_TO_EXPANSION_PACK>"
    
    $result = Start-AldoExpansionPackInstallation `
        -ExpansionPackId $expansionPackId `
        -Wait
    ```

When installation finishes:

* Container images are imported into the `edgeartifacts` registry.
* Model artifacts are published to the registry.
* The Foundry Local Azure Arc extension becomes available for installation.

### Verify installation

Run the following command on the `Azure Local Disconnected Operations` machine and confirm your expansion pack is in `Installed` state.

```powershell
Get-ApplianceExpansionPackDetails
```

## Next step

> [!div class="nextstepaction"]
> [Deploy Foundry Local as an Azure Arc extension in a disconnected environment](deploy-platform.md)

## Related content

* [Troubleshoot Foundry Local on Azure Local in disconnected environments](how-to-troubleshoot.md)
