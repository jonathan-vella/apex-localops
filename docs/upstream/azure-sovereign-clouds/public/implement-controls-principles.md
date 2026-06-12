---
title: "Implement controls and principles in SLZ"
description: "Design for Sovereign Landing Zone (SLZ)."
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

# Implement controls and principles in SLZ

As outlined in [Controls and principles in Sovereign Public Cloud](overview-controls-principles.md), Azure Policy is a key tool to help your organization implement sovereignty controls across your Azure environment. However, to effectively manage and apply these policies at scale, you need a well-structured hierarchy that uses Management Groups. The Sovereign Landing Zone (SLZ) reference architecture provides a predefined hierarchy, recommended policies, and the scope to apply them, all built on top of the [Azure landing zone reference architecture](/azure/cloud-adoption-framework/ready/landing-zone/).

This article describes how to implement the controls and principles outlined in the previous article by using Azure management groups and policies in the context of the Sovereign Landing Zone (SLZ). The following diagram shows the SLZ reference architecture's Management Group hierarchy with the associated controls and principles. These controls and principles translate to various Azure Policy assignments, initiatives, and definitions, and the scope at which you should apply them against the reference architecture.

:::image type="content" source="media/sovereign-landing-zone-policy-controls.svg" alt-text="Diagram that shows a sovereign landing zone management group."::: lightbox="media/sovereign-landing-zone-policy-controls.svg":::

*Sovereign landing zone conceptual architecture's Management Group hierarchy with the associated controls and principles applied. Download a [Visio file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.vsdx) or [PDF file](https://github.com/MicrosoftDocs/cloud-adoption-framework/raw/main/docs/ready/enterprise-scale/media/enterprise-scale-architecture.pdf) of this architecture.*

> [!NOTE]
> The diagram shows controls that you can apply to help implement the sovereign principles. The actual policies and initiatives that you apply depend on your organization's specific requirements. The diagram shows the Sovereign Landing Zone (SLZ) default architecture and the controls it applies by default.

## Management Group hierarchy in SLZ

The following sections provide more detail on the management group hierarchy and the recommended controls to apply at each level.

### Platform

Use the platform management groups to centralize services such as connectivity, environment management, key management, and more. Because the platform services support sovereign workloads, they must also adhere to sovereignty and security controls. For example, if confidential workloads use identity services hosted in the identity subscription, those services should also use confidential computing to help ensure integrity. Therefore, most services under the platform management group require Level‑1 (data residency), Level‑2 (encryption-at-rest and in-transit), and—where possible—Level‑3 (confidential computing).

> [!NOTE]
> If you use multi-region or global implementations of Azure services, you might need to document exceptions to data residency (for example, global networking or DNS services).

Within the platform landing zone, services are hosted in different subscriptions under different management groups. This structure allows different centralized IT teams to manage these services and apply specific policies. This approach aligns with the reference architecture for Azure landing zones, with the addition of the Security management group (and subscription). Add this subscription specifically to address the components that make up the sovereign services, such as the Managed HSM instance hosting all service encryption keys.

### Landing zones

The Azure landing zone architecture categorizes workloads into `online` and `corp` workloads based on their networking architecture, as detailed in [Network topology and connectivity](/azure/cloud-adoption-framework/ready/landing-zone/design-area/network-topology-and-connectivity#design-area-overview). This segregation distinguishes workloads that require direct internet access from corporate applications that are hosted only on internal networks. This management group layout is especially useful for organizations that run online services alongside corporate workloads and where data classification isn't immediately apparent.

In the Sovereign Landing Zone reference architecture, three additional management groups support the various sovereign policies: `Public`, `Confidential Online`, and `Confidential Corp`. These management groups help segregate workloads based on their data classification and the required sovereignty controls for each classification. The following table summarizes the management groups, their parent management group, the data classification they support and host, and the recommended controls to apply based on [Controls and principles in Sovereign Public Cloud](overview-controls-principles.md).

| Management Group      | Parent Management Group | Data classification most suited | Networking model                                                                                                | Controls                                            |
| --------------------- | ----------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `Public`              | `Landing Zones`         | Public/General                  | Internet only, no Layer 3 connectivity to other application landing zone subscriptions                          | ALZ defaults + Organization specific                |
| `Online`              | `Landing Zones`         | General/Confidential            | Internet, with controlled connectivity via the connectivity hub to other application landing zone subscriptions | ALZ defaults + L1 + L2 + Organization specific      |
| `Corp`                | `Landing Zones`         | General/Confidential            | Internal only, controlled connectivity via the connectivity hub to other application landing zone subscriptions | ALZ defaults + L1 + L2 + Organization specific      |
| `Confidential Online` | `Landing Zones`         | Highly Confidential/Secret      | Internet, controlled connectivity via the connectivity hub to other application landing zone subscriptions      | ALZ defaults + L1 + L2 + L3 + Organization specific |
| `Confidential Corp`   | `Landing Zones`         | Highly Confidential/Secret      | Internal only, controlled connectivity via the connectivity hub to other application landing zone subscriptions | ALZ defaults+ L1 + L2 + L3 + Organization specific  |

> [!TIP]
> You can find information on defining your organization's data classification model in the [Well-Architected Framework: Architecture strategies for data classification](/azure/well-architected/security/data-classification).

#### Public

Because most sovereign controls apply to business workloads, the Public management group hosts publicly available information. Publicly available information shouldn't be restricted by sovereign controls such as data residency or encryption at rest or in use, which is why this management group has only standard security policies. While services hosted in this management group are less restricted, don't allow any private network connectivity from these workloads into the Online/Corp and Confidential Online/Confidential Corp services. Any required communication should follow a zero-trust principle. In some cases, it might be possible to use private endpoints from services hosted in these management groups to make them available to Public management group–hosted applications. Otherwise, API calls to workloads in Online and Confidential Online are also possible. These network restrictions help ensure full isolation between sovereign and highly controlled workloads and publicly available services.

#### Online / Confidential Online

You can host services that require end users to sign in from the internet in subscriptions in the Online and Confidential Online management groups. These services can also have corporate network access. However, no unauthenticated network traffic should traverse these networks (zero‑trust principle). Given the various data classifications these applications handle, use Level 1 (data residency) and Level 2 (encryption-at-rest and in-transit) controls alongside the default Azure landing zone policies, while Confidential Online workloads also implement Level 3 (encryption in use) controls.

#### Corp / Confidential Corp

Use Corp and Confidential Corp workloads for internal users or systems only. They aren't published directly to the internet and have tightly controlled networking policies. Standard security policies from the secure landing zone framework regarding the use of public IPs and routing are applicable. From a sovereignty perspective, Online and Corp share Level 1 (data residency) and Level 2 (encryption-at-rest and in-transit) controls; Confidential Corp adds Level 3 (encryption-in-use).

### Data classification management groups (alternative approach)

You can also change the default Sovereign Landing Zone architecture. By representing the data classifications in the management group structure, you can deviate from the default Management Groups, beneath `Landing Zones`, to instead align to your organization's data classification model, following the guidance in [Tailor the Azure landing zone architecture to meet requirements](/azure/cloud-adoption-framework/ready/landing-zone/tailoring-alz).

In this model, you apply the policies at the Management Group scope to monitor compliance across all workloads of a particular data classification. You can also remove the `corp` and `online` management groups if your organization doesn't need these management groups in relation to network access controls, as described in [Network topology and connectivity](/azure/cloud-adoption-framework/ready/landing-zone/design-area/network-topology-and-connectivity#design-area-overview).

## Summary

Sovereign controls are layered on top of existing or newly deployed Azure landing zones or Sovereign landing zones. You can apply them to various data or workload classifications together with other compliance initiatives. The Sovereign landing zone reference architecture provides a recommended hierarchy, but you should determine whether this layout is applicable or if adaptations are required as per the tailoring guidance in [Tailor the Azure landing zone architecture to meet requirements](/azure/cloud-adoption-framework/ready/landing-zone/tailoring-alz).

## Next steps

- [Sovereign Landing Zone (SLZ) implementation options](implementation-options.md)
- [FAQs for Sovereign Landing Zone](questions-sovereign-landing-zone.md)