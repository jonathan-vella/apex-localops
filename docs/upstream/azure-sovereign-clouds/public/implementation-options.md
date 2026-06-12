---
title: "Sovereign Landing Zone (SLZ) implementation options"
description: "Implementation options for deploying a Sovereign Landing Zone (SLZ)."
author: lavanyapg
ms.topic: overview
ms.date: 01/28/2026
ms.author: jatracey
ms.reviewer: lsuresh
ms.subservice: sovereign-public-clouds
ms.collection: 
  - microsoftcloud-sovereignty
  - microsoftcloud-seo-priority
---

# Sovereign Landing Zone (SLZ) implementation options

The Sovereign Landing Zone (SLZ) is a variant of the [Azure landing zone](/azure/cloud-adoption-framework/ready/landing-zone/) that helps organizations implement sovereign controls, such as data residency, customer managed keys, externally managed encryption keys, encryption at rest, encryption in transit, confidential computing, and operational oversight. There's no single mandated deployment path. Organizations can adopt SLZ capabilities incrementally or as a full variant of an existing Azure landing zone.

> [!IMPORTANT]
> SLZ is an architectural variant. You don't need to replace your Azure landing zone implementation. Instead, layer sovereign design choices, controls, and policies. Start from your existing landing zone unless critical structural gaps exist.

## Implementation options

To deploy and manage your Sovereign landing zone (SLZ), use any of the following implementation options.

### Terraform

The Sovereign Landing Zone (SLZ) implementation is currently available only through the [Terraform Azure Verified Modules for the platform landing zone](https://azure.github.io/Azure-Landing-Zones/terraform/). You can deploy these modules either [manually](https://azure.github.io/Azure-Landing-Zones/terraform/gettingstarted/) or by using the (recommended) [Azure landing zone accelerator](https://azure.github.io/Azure-Landing-Zones/accelerator/).

#### Azure landing zone accelerator high-level process overview

The best way to deploy Sovereign Platform Landing Zone (SLZ) is via the [Azure landing zone accelerator](https://azure.github.io/Azure-Landing-Zones/accelerator/). It provides a guided experience to help you set up a landing zone aligned to your organization's needs. The following list describes the high-level steps to follow.

> [!IMPORTANT]
> You must follow the steps in the [user guide](https://azure.github.io/Azure-Landing-Zones/accelerator/). The following steps are a high-level summary only.

1. [Choose Infrastructure-as-Code (IaC) tool](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/#decision-1---choose-infrastructure-as-code-iac-tooling) - Terraform
1. [Choose Version Control System (VCS)](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/#decision-2---choose-a-version-control-system) - GitHub or Azure DevOps
1. [Choose a Scenario](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/#decision-1---choose-a-scenario)
1. [Choose Options](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/#decision-2---choose-options) to tweak your platform landing zone deployment
   - Ensure [15 - Implement Sovereign Landing Zone (SLZ) controls](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/) is followed
1. [Ensure prerequisites are met](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/)
1. [Deploy Bootstrap](https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/)
1. [Run CD to deploy platform landing zone](https://azure.github.io/Azure-Landing-Zones/accelerator/3_run/)
1. Iterate, customize, and extend your landing zone via your chosen VCS and CI/CD pipelines

### Bicep

The Bicep implementation option is in development. It builds on the new Bicep Azure Verified Modules for a platform landing zone, described in the blog post [Update on Bicep Azure Verified Modules for platform landing zone](https://techcommunity.microsoft.com/blog/azuretoolsblog/an-update-on-bicep-azure-verified-modules-for-platform-landing-zone-alz/4407626).

## Azure landing zone library

Both Terraform and Bicep implementations of SLZ use the [Azure landing zone library](https://azure.github.io/Azure-Landing-Zones-Library/), a collection of resources to help you build and manage governance on Azure.

The library includes Azure Policy assets, together with a series of constructs that result in a deployable architecture. It's extensible, customizable, and flexible. It supports many implementation approaches and scenarios.

You can find the SLZ library assets in the [`platform/slz` directory](https://github.com/Azure/Azure-Landing-Zones-Library/tree/main/platform/slz) of the Azure landing zone library.

> [!NOTE]
> The SLZ library takes a dependency, as detailed further [here](https://azure.github.io/Azure-Landing-Zones-Library/extensibility/#on-dependencies), on the [Azure landing zone library (`platform/alz` directory)](https://github.com/Azure/Azure-Landing-Zones-Library/tree/main/platform/alz) as you can see in the dependencies section of the [SLZ's `alz_library_metadata.json` file](https://github.com/Azure/Azure-Landing-Zones-Library/blob/main/platform/slz/alz_library_metadata.json#L7-L12).

For more information, see the following sections in the [Azure landing zone library documentation](https://azure.github.io/Azure-Landing-Zones-Library/):

- [Assets](https://azure.github.io/Azure-Landing-Zones-Library/assets/)
- [Clients](https://azure.github.io/Azure-Landing-Zones-Library/clients/)
- [Extensibility](https://azure.github.io/Azure-Landing-Zones-Library/extensibility/)

## Next steps

- [Implement controls and principles](implement-controls-principles.md)
- [FAQs for Sovereign Landing Zone (SLZ)](questions-sovereign-landing-zone.md)

## See also

- [Sovereign Landing Zone (SLZ) overview](overview-sovereign-landing-zone.md)
- [Design sovereign policies](design-sovereign-policies.md)
- [Azure landing zone reference architecture](/azure/cloud-adoption-framework/ready/landing-zone/)
- [Azure encryption overview](/azure/security/fundamentals/encryption-overview)
- [Azure confidential computing overview](/azure/confidential-computing/overview)
- [EU Data Boundary](/privacy/eudb/eu-data-boundary-learn)