---
title: "Regulated Environment Management (REM) overview"
description: "Overview of REM for managing regulated workloads in the Sovereign Public Cloud."
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

# What is Regulated Environment Management (REM)?

> [!NOTE]
> This article is a stub with minimal information. It primarily serves as a navigation anchor within the documentation. Its role is to provide a concise description of REM and help users understand the context of this article while maintaining a clear structure for related content.

Regulated Environment Management (REM) provides a unified customer experience to configure, deploy, and monitor workloads in support of sovereign operations in Microsoft’s public cloud. 

## Key features

- **Unified experience for sovereign operations**: Provides a single place to orchestrate configuration, deployment, and monitoring of workloads with sovereignty in mind.
- **Works with policy‑as‑code guardrails**: Complements Microsoft’s Sovereign Landing Zone (SLZ) patterns to enforce location, encryption, and configuration policies at scale.
- **Integrates with sovereignty frameworks**: Designed to work within Microsoft’s sovereignty approach, ensuring compliance and governance across regions.
- **Complements other Sovereign Public Cloud capabilities**: Operationally unifies [External Key Management](external-key-management.md), [Data Guardian](data-guardian.md), and [Confidential Computing](confidential-computing.md) with SLZ policy portfolios to help organizations apply sovereignty controls consistently at scale while retaining hyperscale cloud benefits.

## Who should use REM?

REM is intended for governments and regulated industries that need to operate in Microsoft’s Sovereign Public Cloud and maintain strong alignment with local laws, policies, and regulatory frameworks—all while accessing public‑cloud innovation, resiliency, and security.

## Prerequisites

Before adopting REM, ensure the following prerequisites are in place:

- Azure tenant and subscriptions aligned to an Azure Landing Zone or Sovereign Landing Zone hierarchy.
- Documented data classification model and associated sovereign control mapping (L1–L3).
- Key management approach (Managed HSM / CMK / optional External Key Management) defined.
- Initial policy initiatives stored in source control and assignable at management group scope.
- Logging destinations for policy compliance, key operations, and access events defined.

## Architecture and integration

REM sits on top of the Sovereign Landing Zone (SLZ) foundation and consumes existing policy initiatives (L1–L3) for region, encryption, and confidential compute controls. Conceptually:

1. SLZ provides policy‑as‑code guardrails and management group segmentation.
1. REM supplies an orchestration and monitoring layer to apply, validate, and report on those guardrails.
1. Operational capabilities (Data Guardian sessions, key usage telemetry, confidential compute attestation signals) surface as part of compliance and readiness dashboards.

> [!TIP]
> When designing REM adoption, define a minimal evidence model early (region compliance %, CMK coverage %, confidential compute adoption %, supervised access sessions) so dashboards evolve with actual stakeholder reporting needs.

## Common scenarios

Use REM to manage regulated workloads through the following scenarios:

- Configure sovereign guardrails before workload onboarding (regions, encryption, identity, networking).
- Deploy and validate workloads against policy baselines and architectural guidance.
- Monitor operational posture for alignment with sovereignty objectives (dashboards and alerting).
- Collect evidence for regulatory or internal assurance reviews.
- Centralize exception tracking workflow for region or service deviations.

## Related content

- [What is Microsoft Sovereign Cloud?](../microsoft-sovereign-cloud.md)
- [Sovereign Landing Zone overview](overview-sovereign-landing-zone.md)


## See also

- [External Key Management](external-key-management.md)
- [Data Guardian](data-guardian.md)
- [Confidential Computing](confidential-computing.md)
- [Sovereign Landing Zone](overview-sovereign-landing-zone.md)