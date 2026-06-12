---
title: "What is Microsoft Sovereign Cloud?"
description: "Understand Microsoft Sovereign Cloud and its role in addressing sovereignty requirements."
author: ronmiab
ms.subservice: sovereign-public-clouds
ms.topic: overview
ms.date: 03/31/2026
ms.author: robess
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---

# What is Microsoft Sovereign Cloud?

Microsoft Sovereign Cloud, formerly Microsoft Cloud for Sovereignty, is an evolution and expansion of the original offering. It's a suite of capabilities and deployment models designed to help governments and regulated industries meet stringent data residency, compliance, and operational sovereignty requirements without sacrificing the benefits of hyperscale cloud innovation. 

Microsoft Sovereign Cloud is available across European datacenter regions for European customers and supports enterprise services such as Microsoft Azure, Microsoft 365, Microsoft Security, and Power Platform. Although the foundation targets European datacenter regions, technical capabilities to enforce data sovereignty are available worldwide. 

Azure local and private clouds provide the strongest sovereignty controls by offering full control over hardware, software, data, location, and management. However, those environments don't deliver the full cloud value in areas such as cost-effectiveness, scalability, speed of innovation, security, and reliability.

In addition to Microsoft-operated and customer-operated models, Microsoft collaborates with approved national or regional partners to deliver National Partner Clouds. These localized sovereign cloud implementations operate with a trusted domestic partner to meet jurisdiction‑specific policy, regulatory, and digital transformation objectives. Availability, scope, and service coverage for National Partner Clouds vary by geography and align with national frameworks.

## Sovereignty in the hyperscale cloud

Microsoft Sovereign Cloud builds on Microsoft's experience delivering sovereignty solutions for highly regulated customers and government agencies. It lets organizations run Microsoft cloud services and AI workloads under enhanced sovereignty controls in public sovereign regions or private, disconnected environments.

Hyperscale cloud platforms deliver scale, agility, and advanced security, but they also introduce sovereignty challenges. Therefore, organizations must balance:

- Cloud value: Innovation, reliability, and cost efficiency.
- Sovereign controls: Data residency, operational transparency, and compliance guardrails.

:::image type="content" source="media/cloud-value-overview.png" alt-text="Screenshot shows the cloud value overview." lightbox="media/cloud-value-overview.png" :::

## Why Microsoft Sovereign Cloud is important

### Regulatory compliance and trust

Public sector agencies and regulated industries must meet strict legal and policy requirements for data handling, residency, and operational control. Microsoft Sovereign Cloud offers guardrails, controls, and transparency programs to help organizations meet these obligations while maintaining access to the latest cloud innovations.

### Operational sovereignty

Organizations can choose deployment models that align with their sovereignty needs:

- [Sovereign Public Cloud](public/overview-sovereign-public-cloud.md): This deployment model is hosted in Microsoft-operated datacenters within defined geopolitical boundaries (for example, EU Data Boundary). It offers data residency, customer-managed encryption keys, and operational transparency. In addition, the model is built on Microsoft's global Azure infrastructure with enhanced sovereignty controls, such as Data Guardian, External Key Management, and tamper-evident access logs.

- [Sovereign Private Cloud](private/overview/sovereign-private-cloud.md): This model runs in customer-controlled or partner-operated datacenters, supporting hybrid or disconnected operations. The model is delivered via Azure Local and Microsoft 365 Local. The model is ideal for defense, critical infrastructure, and national security scenarios.

- [National Partner Clouds](partner/overview-national-partner-clouds.md): These clouds are localized sovereign cloud instances delivered with an approved national or regional partner. The instances combine Microsoft sovereign capabilities with partner-operated or jointly governed operational processes to meet localized sovereignty, governance participation, and economic development requirements while retaining access to selected Microsoft cloud innovations under enhanced operational assurances. Their service scope, latency characteristics, and rollout sequencing can differ from those offered by global Azure. As a result, customers need to review the published service matrices for each national implementation.

### Security and confidentiality

Microsoft Sovereign Cloud uses hardware-based confidential computing, customer-managed keys, and policy-as-code templates to protect data at rest, in transit, and in use. These capabilities reduce risk from unauthorized access, including from cloud operators. 

## Core components

| Component | Purpose |
|-----------|---------|
|[Sovereign Landing Zone (SLZ)](public/overview-sovereign-landing-zone.md) | Preconfigured Azure environment with policy-as-code templates to enforce compliance and security baselines.|
|Azure Local | Brings core Azure services (compute, storage, networking) to customer premises, supporting disconnected and hybrid scenarios. | 
|Microsoft 365 Local | Runs Exchange, SharePoint, and Teams in a sovereign environment, built on Azure Local. | 
|[Confidential Computing](public/confidential-computing.md) | Protects data in use with Trusted Execution Environments (TEEs). |

## Customer value

- Compliance confidence: Align with local and sector-specific regulations.
- Operational control: Decide where data resides and who can access it.
- Security assurance: Use confidential computing and advanced encryption.
- Innovation access: Use the same Azure and Microsoft 365 services as the global cloud, with added sovereignty controls.
- Local partnership and ecosystem development: Use domestic partner participation to accelerate national digital capability, support local compliance interpretation, and foster a resilient regional supply and skills ecosystem.

## See also

- [European Digital Commitments](european-digital-commitments.md)
- [Digital sovereignty](digital-sovereignty.md)  
- [Sovereign Public Cloud](public/overview-sovereign-public-cloud.md)
- [Sovereign Private Cloud](private/overview/sovereign-private-cloud.md)
- [National Partner Clouds](partner/overview-national-partner-clouds.md)
