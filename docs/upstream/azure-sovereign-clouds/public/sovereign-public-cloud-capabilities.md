---
title: "Capabilities of Sovereign Public Cloud"
description: "Explore key capabilities available in Sovereign Public Cloud."
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

# Capabilities of Sovereign Public Cloud

Microsoft’s Sovereign Public Cloud approach lets governments and regulated industries use the hyperscale Microsoft cloud and add controls for data residency, operational oversight, and customer‑controlled encryption. This article introduces four foundational capabilities and provides links to more information.

## Data Guardian

Data Guardian enhances operational sovereignty by ensuring that authorized regional personnel approve and monitor remote access by Microsoft personnel to sovereign‑region services. All access is recorded in a tamper‑evident ledger.

Data Guardian helps customers:

- Establish local oversight for support and operator actions.
- Provide transparent, auditable operations via immutable logs.
- Build trust while retaining the benefits of the hyperscale cloud.

For more information, see [Data Guardian](data-guardian.md).

## External Key Management

External Key Management allows customers to generate, store, and manage encryption keys outside Microsoft’s cloud boundary (for example, in customer‑operated or trusted third‑party HSMs) while still using those keys with Azure services.

External Key Management enables customers to:

- Maintain exclusive control over encryption keys.
- Align with regulatory expectations for key ownership and residency.
- Add a defense‑in‑depth layer separating cloud operations from key custody.

For more information, see [External Key Management](external-key-management.md) and [Encryption overview](/azure/security/fundamentals/encryption-overview).

## Confidential Computing

Confidential Computing protects data in use by running computations inside hardware‑based Trusted Execution Environments (TEEs). Azure offers confidential options for VMs and containers.

Confidential Computing:

- Complements encryption at rest and in transit by protecting data in memory.
- Helps address operational access concerns by limiting visibility during processing.
- Aligns with sovereign landing zone patterns for confidential workloads.

For more information, see [Confidential Computing](confidential-computing.md) and [Sovereign Landing Zone](overview-sovereign-landing-zone.md).

## Sovereign Control Panel (SCP)

Sovereign Control Panel (SCP) is a unified Azure portal experience for viewing, managing, and evaluating sovereignty posture across tenant resources. It aggregates sovereignty signals into a centralized and intuitive console for end users and reviewers to view and verify sovereignty requirements.

For more information, see [Sovereign Control Panel](regulated-environment-management.md).

## Choose the right capability for your goal

The following table summarizes how these capabilities help address common sovereignty goals.

| Goal | Recommended capability | 
|------|------------------------|
| Ensure local oversight and tamper‑evident logging of provider operations | Data Guardian |
| Keep encryption keys under exclusive customer control | External Key Management (EKM) |
| Protect data in use during processing | Confidential Computing |
| Monitor sovereign workloads centrally | Sovereign Control Panel (SCP) |

## How these capabilities work together for sovereign workloads

Sovereign Public Cloud capabilities are most effective when used with policy‑as‑code guardrails and reference architectures. Sovereign Landing Zone (SLZ) applies region/location, encryption, and configuration policies to create a compliant baseline for workloads.

## See also

- [External Key Management](external-key-management.md)  
- [Data Guardian](data-guardian.md)  
- [Confidential Computing](confidential-computing.md)  
- [Sovereign Control Panel](regulated-environment-management.md)
- [Discover Microsoft Sovereign Cloud (product overview and EU focus)](../microsoft-sovereign-cloud.md)
- [Sovereign Landing Zone overview](overview-sovereign-landing-zone.md)
