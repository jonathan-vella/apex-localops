---
title: "Design sovereign policy initiatives in Azure"
description: "Learn how to design sovereign policy initiatives"
author: lavanyapg
ms.topic: overview
ms.date: 10/13/2025
ms.author: rozome
ms.reviewer: lsuresh
ms.subservice: sovereign-public-clouds
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---

# Design sovereign policy initiatives in Azure

Sovereign policies in Azure help organizations enforce requirements around data residency, encryption, and confidential compute. While Azure provides the technical capabilities, you need to codify these requirements into policies that ensure every deployment remains compliant. By translating regulatory and organizational controls into Azure Policy, initiatives, and blueprints, you can apply consistent governance across subscriptions and regions, reduce the risk of misconfiguration, and build workloads that are sovereign by design.

The diagram shows how sovereign policy components relate within the broader governance framework.

:::image type="content" source="media/policy-framework.png" alt-text="Diagram shows the policy framework overview." lightbox="media/policy-framework.png":::

## Sovereign policy initiatives

A policy initiative is a collection of individual Azure Policy definitions that work together to enforce a broader governance objective. By grouping policies into initiatives, you can apply a single assignment that ensures a sovereign control across multiple Azure services. Policy initiatives let you quickly add or retire policies. Within an initiative, you can also allow or deny specific services that don't (yet) fulfill your sovereign needs.

The sovereign controls are classified as Level‑1 (enforcing data locality and in‑transit encryption), Level‑2 (encryption at-rest with CMK controls), and Level‑3 (encryption in-use/confidential computing). However, each service in Azure requires its own policy for these controls. Because new services and features are added frequently, create individual sovereign policies per service, then aggregate them into Level‑1, Level‑2, and Level‑3 initiatives.

The image illustrates how you can design policy initiatives in Azure to enforce sovereign controls across multiple services.

:::image type="content" source="media/policy-initiatives.png" alt-text="Diagram shows the Sovereign Policy Initiative." lightbox="media/policy-initiatives.png":::

Azure offers several baseline security policy initiatives that complement sovereign controls. The exact contents of sovereign and security policy initiatives vary by countries/regions, industry, and customer requirements. Organizations can use these starter policies as a baseline:

- [Sovereignty Baseline – Global Policies](/azure/governance/policy/samples/mcfs-baseline-global)
- [Sovereignty Baseline – Confidential Policies](/azure/governance/policy/samples/mcfs-baseline-confidential)

Organizations should extend and customize these baselines by creating their own policy initiatives. Some organizations keep their policy initiatives private, while others share them as reference models such as the [NL BIO Cloud Theme](/azure/governance/policy/samples/nl-bio-cloud-theme) policy initiative.

In practice, apply sovereign policies initially in *audit mode* to ease implementation and allow for exceptions, but you can also set them to *deny/enforce* for strict compliance environments.

While sovereign policies are important, they represent just one layer of the broader policy framework that organizations must implement based on their specific workloads. For instance, established compliance standards such as PCI-DSS or NIST might also be required. Sovereign policies are designed to complement and not replace these existing industry compliance and security configurations.

## Azure Sovereign Landing Zone

The Azure Sovereign Landing Zone builds on the Cloud Adoption Framework and Secure Landing Zone architectures. Its essence is applying a layered set of policies (L1–L3 + security) across workloads to control data residency, encryption requirements, and the use of approved services in combination with security controls. By combining the three levels, organizations can align controls with their data classifications and apply the appropriate set of requirements to each management group in the Sovereign Landing Zone.

The Azure Sovereign Landing Zone includes the Secure Landing Zone initiative, a comprehensive set of policy definitions that enforce critical security controls. These controls include configurations for private endpoints, Microsoft Defender for Cloud, and many other essential security settings to help ensure a secure and compliant cloud environment.

Implement policies through management groups to ensure that workloads are logically separated from each other. In the following image, the three different levels indicate the different data classification levels in the workloads.

:::image type="content" source="media/sovereign-landing-zone-policy-controls.svg" alt-text="Diagram shows the management group policy overview." lightbox="media/sovereign-landing-zone-policy-controls.svg":::

> [!NOTE]
> The diagram shows controls that you can apply to help implement the sovereign principles. The actual policies and initiatives that you apply depend on your organization's specific requirements. The diagram shows the Sovereign Landing Zone (SLZ) default architecture and the controls it applies by default.

Apply the sovereign policies to platform‑level supporting services (Identity, Management, Security, and Connectivity).

For more information, see [Sovereign Landing Zones](overview-sovereign-landing-zone.md).

## How it works

- Create multiple policy initiatives, each mapped to a specific sovereign control such as data residency, encryption at-rest, and encryption in use.
- Include policies that apply to different Azure services at the same time in a single initiative. For example, an initiative for encryption at rest can enforce *customer-managed keys (CMK)* for Azure SQL Database while also requiring *disk encryption* for AKS nodes and *CMK encryption* for storage accounts.
- Alongside sovereign controls, you can include default security configurations such as TLS, RBAC, and private endpoints to strengthen the baseline posture. The initiatives can also include other compliance initiatives such as PCI‑DSS and NIST controls.

Apply these initiatives to Management Groups in the Landing Zones so you can easily apply data classifications and their corresponding controls to specific workloads.

## Key takeaways and success factors

By structuring your Azure governance into policy initiatives, you can:  

- Start with data classification controls for your workloads.
- Align Azure services with sovereign requirements, such as residency, encryption, and confidentiality.  
- Apply consistent policies across services with one assignment.  
- Combine sovereign controls with default security configurations to build a secure and compliant cloud environment.
- Introduce initiatives in audit mode, validate signal quality, then transition critical controls to deny for new deployments.
- Integrate policy compliance dashboards into regular governance reviews.

## See also

- [Example sovereign policies by RZomerman](https://github.com/RZomermanMS/SovControls)
- [Tutorial: Create and manage policies to enforce compliance](/azure/governance/policy/tutorials/create-and-manage)
