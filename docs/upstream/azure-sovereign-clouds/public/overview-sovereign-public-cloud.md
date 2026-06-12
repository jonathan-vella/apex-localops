---
title: " What is Sovereign Public Cloud"
description: "Overview of Sovereign Public Cloud."
author: lavanyapg
ms.topic: overview
ms.date: 10/07/2025
ms.author: kerabun
ms.reviewer: lsuresh
ms.subservice: sovereign-public-clouds
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---


# What is Sovereign Public Cloud?

Sovereign Public Cloud is Microsoft’s approach to supporting the digital sovereignty goals of governments and regulated industries while using existing Microsoft hyperscale cloud regions. It combines public cloud innovation with added controls for data residency, operational oversight, and customer-controlled encryption, so organizations can meet local laws and policy requirements without leaving the hyperscale cloud model.

At a high level, Sovereign Public Cloud:

- Adds sovereignty capabilities on top of Azure and [Advanced Data Residency in Microsoft 365](/microsoft-365/enterprise/advanced-data-residency), [confidential computing](confidential-computing.md), and the ability to [bring and manage your own keys](external-key-management.md) in Hardware Security Modules (HSMs).
- Uses codified guardrails such as policy-as-code and [landing zones](overview-sovereign-landing-zone.md) so customers can configure, deploy, and monitor compliant environments at scale.
- Has specific sovereignty features for EU/EFTA Microsoft datacenters (data stays in Europe, under EU law and control), such as the [EU Data Boundary](/privacy/eudb/eu-data-boundary-learn) and [Data Guardian](data-guardian.md).

> [!NOTE]
> For more clarity on the definition of EU, EFTA, European please refer to [EU Data Boundary](/privacy/eudb/eu-data-boundary-learn).

## Why choose Sovereign Public Cloud

Public sector and regulated organizations need to modernize while complying with data, operational, and regulatory constraints. Sovereign Public Cloud preserves the benefits of the hyperscale public cloud—innovation, resiliency, and advanced cybersecurity—and layers on the [controls](overview-controls-principles.md) and transparency that support digital sovereignty.

The core features of Sovereign Public Cloud include:

### Data residency and data sovereignty

- Ability to keep data in-region, supporting compliance with local data residency and governance expectations.
- Alignment with Microsoft’s broader guidance for data sovereignty and data governance in the public cloud.

### Operational oversight and transparency

- Enhanced operational controls for access to European cloud services, controlled by European residents, and tracked by using tamper-evident logs to enable auditability and trust.
- Public documentation for operational transparency programs (for example, registering for [Data Guardian](data-guardian.md) logs) to give eligible customers greater visibility into provider operations.

### Customer-controlled encryption and key management

- Support for [bringing and managing your own keys](external-key-management.md) with HSM-based key stores, adding another layer of control over encryption keys used by Azure services.
- Complementary Microsoft Learn guidance on managing keys and certificates, and using [confidential computing](confidential-computing.md) to protect data in use.

### Policy as code guardrails with the Sovereign Landing Zone (SLZ)

- Availability of [Sovereign Landing Zone](overview-sovereign-landing-zone.md) with Bicep and Terraform implementations. Sovereign Landing Zone is an opinionated variant of the Azure Landing Zone that applies policy as code for sovereignty needs (for example, residency, confidential computing, and location controls).

## How does Sovereign Public Cloud work?

Sovereign Public Cloud builds on Microsoft’s hyperscale public cloud foundation and adds sovereign controls at the platform and deployment layers:

- Foundation – Hyperscale public cloud. Azure and Microsoft 365 deliver global innovation, elasticity, resiliency, and advanced security.
- Sovereignty guardrails – Policy initiatives and landing zones enforce service location, encryption, and configuration requirements to meet sovereignty objectives.
- Operational transparency – Operational access to European services is EU-resident controlled and tamper-evidently logged, improving oversight and audit.
- Customer-controlled keys and confidential computing – Customers can manage keys in their own HSMs and use confidential computing patterns to protect data in use.

## Who should consider Sovereign Public Cloud?

National, regional, and local governments, and regulated industries like energy, healthcare, and financial services operating in Europe should consider Sovereign Public Cloud. These organizations need to satisfy data residency, operational oversight, and compliance requirements when adopting public cloud services.

## See also

- [Sovereignty Controls and Principles](overview-controls-principles.md)
- [Confidential Computing](confidential-computing.md)
- [Sovereign Landing Zone](overview-sovereign-landing-zone.md)
- [Data Guardian](data-guardian.md)
- [External Key Management](external-key-management.md)
- [Regulated Environment Management](regulated-environment-management.md)
