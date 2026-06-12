---
title: "Sovereign Landing Zone (SLZ)"
description: "Overview of the Sovereign Landing Zone (SLZ) architecture and scenarios."
author: lavanyapg
ms.topic: overview
ms.date: 10/07/2025
ms.author: jatracey
ms.reviewer: lsuresh
ms.subservice: sovereign-public-clouds
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---
# Sovereign Landing Zone (SLZ)

The Sovereign Landing Zone (SLZ) is a variant of the [Azure landing zone](/azure/cloud-adoption-framework/ready/landing-zone/) platform landing zone architecture. It's tailored to help accelerate customers with sovereign requirements to meet their specific sovereign needs and requirements.

## Sovereign Landing Zone (SLZ) architecture

The SLZ architecture is based on the [Azure landing zone architecture](/azure/cloud-adoption-framework/ready/landing-zone/), which provides a scalable and secure foundation for deploying and managing workloads in Azure. SLZ applies the same underlying [design principles](/azure/cloud-adoption-framework/ready/landing-zone/design-principles) and [design areas](/azure/cloud-adoption-framework/ready/landing-zone/design-areas), while also incorporating additional [controls and principles](overview-controls-principles.md) to address specific sovereign requirements in the Sovereign Public Cloud.

# [Hub & Spoke](#tab/hubspoke)

:::image type="content" source="media/sovereign-landing-zone-hub-spoke.svg" alt-text="Diagram that shows a sovereign landing zone using a hub and spoke networking topology." lightbox="media/sovereign-landing-zone-hub-spoke.svg":::

*Sovereign landing zone conceptual architecture using a hub & spoke networking topology. Download a [Visio file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.vsdx) or [PDF file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.pdf) of this architecture.*

# [Virtual WAN](#tab/vwan)

:::image type="content" source="media/sovereign-landing-zone-wide-area-network.svg" alt-text="Diagram that shows a sovereign landing zone using the Virtual WAN networking topology." lightbox="media/sovereign-landing-zone-wide-area-network.svg":::

*Sovereign landing zone conceptual architecture using a Virtual WAN networking topology. Download a [Visio file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.vsdx) or [PDF file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.pdf) of this architecture.*

# [Management Group Hierarchy Only](#tab/mgonly)

:::image type="content" source="media/sovereign-landing-zone-management-group-hierarchy.svg" alt-text="Diagram that shows a sovereign landing zone management group hierarchy." lightbox="media/sovereign-landing-zone-management-group-hierarchy.svg":::

*Sovereign landing zone conceptual architecture's Management Group hierarchy only. Download a [Visio file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.vsdx) or [PDF file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.pdf) of this architecture.*

# [Management Group Hierarchy with Controls & Principles](#tab/mgandcontrols)

:::image type="content" source="media/sovereign-landing-zone-policy-controls.svg" alt-text="Diagram that shows a sovereign landing zone management group hierarchy." lightbox="media/sovereign-landing-zone-policy-controls.svg":::

*Sovereign landing zone conceptual architecture's Management Group hierarchy with the associated controls and principles applied. Download a [Visio file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.vsdx) or [PDF file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.pdf) of this architecture.*

---

## Design area differences in SLZ vs Azure landing zone

SLZ differs from Azure landing zone in specific design areas to meet sovereign requirements. The following tables show the key differences relative to the [design areas](/azure/cloud-adoption-framework/ready/landing-zone/design-areas).

:::image type="content" source="media/azure-landing-zone-design-areas.svg" alt-text="Diagram that shows the design areas of the conceptual Azure landing zone architecture." lightbox="media/azure-landing-zone-design-areas.svg":::

### Environment design areas

| Design Area                               | Difference in SLZ                                                                                                                        |
| :---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Azure billing and Active Directory tenant | No changes                                                                                                                               |
| Resource organization                     | Addition of the `Public`, `Confidential Corp`, and `Confidential Online` Management Groups beneath the `Landing Zones` Management Group. |
| Identity and access management            | No changes                                                                                                                               |
| Network topology and connectivity         | No changes                                                                                                                               |

### Compliance design areas

| Design Area                       | Difference in SLZ                                                                                                                                                                                                                                                                                                          |
| :-------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Security, Management & Governance | Additional Azure Policies either applied or required depending on organization sovereignty requirements. See [Controls and principles in Sovereign Public Cloud](overview-controls-principles.md) and details on implementation in [Implement controls and principles in SLZ](implement-controls-principles.md). |
| Platform automation and DevOps    | No changes                                                                                                                                                                                                                                                                                                                 |

## Next steps

- [Implement controls and principles in SLZ](implement-controls-principles.md)
- [Sovereign Landing Zone (SLZ) implementation options](implementation-options.md)
- [FAQs for Sovereign Landing Zone](questions-sovereign-landing-zone.md)
