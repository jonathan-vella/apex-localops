---
title: "FAQs for Sovereign Landing Zone"
description: "Frequently asked questions about the Sovereign Landing Zone (SLZ)."
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

# FAQs for Sovereign Landing Zone

This article answers common questions about the Sovereign Landing Zone (SLZ).

## We already have an Azure landing zone deployed. Do we need SLZ?

Not necessarily. The Sovereign Landing Zone (SLZ) is a variant of Azure landing zone and not a replacement.

You can extend your existing Azure landing zone with [sovereign controls (Level 1–3)](overview-controls-principles.md) instead of deploying a separate SLZ or redeploying if you already:

- Use a structured management group hierarchy (platform vs. workload)
- Enforce region restrictions for sensitive workloads
- Apply customer-managed keys consistently for classified data
- Have a process (or roadmap) for confidential computing adoption

Adopt SLZ patterns when you face:

- Regulatory deadline pressure
- Lack of workload separation (confidential vs. standard)
- Ungoverned region sprawl
- Mixed or inconsistent key strategies
- Need for structured onboarding at scale

> [!TIP]
> Start with a 'policy overlay' (audit mode) on top of Azure landing zone to measure impact before introducing deny effects. See [Adopt policy-driven guardrails](/azure/cloud-adoption-framework/ready/enterprise-scale/dine-guidance) for a way of using policy enforcement modes to assist with this.

## What is the difference between Level 1, Level 2, and Level 3 sovereign controls?

The three levels represent a progressive maturity model for [sovereign controls](overview-controls-principles.md):

| Level   | Scope                            | Common controls                                                                                                 |
| ------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Level 1 | Data residency and service scope | Region allowlist; disallow global services (where required); service allow/deny; in-transit encryption defaults |
| Level 2 | Encryption at rest/in-transit    | CMK/Managed HSM required; disallow platform-only encryption for targeted resource types                         |
| Level 3 | Encryption in-use                | Enforce confidential VM/container SKUs; require attestation evidence for key release                            |

## How do exceptions work?

The SLZ framework assumes some exceptions are inevitable. Use these guidelines:

- Document business justification, duration, mitigation, and owner.
- Apply via parameterization (for example, allowed regions list) rather than disabling entire initiatives.
- Track exception count and age; stale exceptions indicate governance erosion.
- Utilize [Azure Policy's exemption](/azure/governance/policy/concepts/exemption-structure) capabilities for visibility, tracking, and reporting.

## How does SLZ relate to other compliance frameworks?

SLZ focuses on three foundational sovereign control domains (residency, encryption, and confidential compute) and operational enablement. It's complementary to frameworks such as ISO, NIST, PCI, or sector-specific addenda. Where overlap occurs (for example, encryption requirements), reuse the same policies to avoid duplication.

## What is the role of External Key Management (EKM)?

External Key Management (EKM—hold-your-own-key) is typically applied selectively to the highest classification workloads where exclusive key custody is a legal or contractual requirement. Use a tiered key strategy: platform-managed (baseline) → CMK/Managed HSM (default for classified) → EKM (select high-impact workloads). Avoid universal EKM unless mandated; it adds latency and operational complexity.

## See also

- [Sovereign Landing Zone overview](overview-sovereign-landing-zone.md)
- [Implementation options](implementation-options.md)
- [Implement the controls and principles](implement-controls-principles.md)
- [Design sovereign policies](design-sovereign-policies.md)