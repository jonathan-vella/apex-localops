---
title: "Data Guardian overview"
description: "Understand Data Guardian and how it helps protect sensitive data in the Sovereign Public Cloud."
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


# What is Data Guardian?

Data Guardian is a sovereignty feature in the Sovereign Public Cloud that provides enhanced operational oversight and control. It ensures that remote access by Microsoft personnel to systems in defined regions like the EU+EFTA is subject to strict approval and monitoring by authorized European-resident personnel. All such access is logged in a tamper-evident ledger.

This capability helps governments and regulated industries meet operational sovereignty requirements while retaining the benefits of the hyperscale cloud model.

## Why it matters

The following reasons explain why Data Guardian is important for customers seeking sovereignty in the public cloud:

- **Operational sovereignty**: Customers gain confidence that Microsoft’s operational activities in regions are supervised locally and can't occur without explicit approval.
- **Transparency and accountability**: Every approved access session is logged to an immutable ledger, creating an auditable record for compliance and security reviews. The immutable ledger leverages [Azure confidential ledger](/azure/confidential-ledger/overview) for writing entries in a tamper evident manner.
- **Risk reduction**: By enforcing human-in-the-loop approval and regional oversight, Data Guardian mitigates the risks of unauthorized or unmonitored access to production systems.
- **Compliance alignment**: Supports regulatory requirements for operational transparency and local oversight.
- **Trust and assurance**: Reinforces Microsoft’s commitment to digital sovereignty and European Digital Commitments.

## Key features

The main features of Data Guardian include:

| Feature | Description |
|-----------|-------------|
| Regional oversight | Only authorized Microsoft personnel residing in the designated region (for example, the EU) can approve and monitor remote access to sovereign systems. |
| Approval workflow | Access requests require explicit, human-in-the-loop approval before operations occur. |
| Tamper-evident logging | All approved access sessions are recorded in an immutable ledger for audit and compliance purposes. |
| Transparency and accountability | The system provides traceability for operational actions to support regulatory reviews. |

## How it works (conceptual)

The Data Guardian process involves the following steps:

1. **Access request**: A Microsoft engineer requests just-in-time access to a production resource in a region.
1. **Approval by regional personnel**: The request is routed to an authorized European-resident approver for validation.
1. **Session monitoring**: Designated personnel monitor approved sessions in real time.
1. **Immutable logging**: All actions during the session are logged in a tamper-evident ledger for transparency and compliance.

## See also

- [Digital sovereignty](../digital-sovereignty.md)
- [What is Microsoft Sovereign Cloud?](../microsoft-sovereign-cloud.md)
- [Sovereign Landing Zone overview](overview-sovereign-landing-zone.md)
