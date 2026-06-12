---
title: "Operational controls"
description: "Learn about operational controls in cloud services and data management."
author: ronmiab
ms.subservice: sovereign-public-clouds
ms.topic: overview
ms.date: 10/07/2025
ms.author: robess
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---

# Operational controls

Operational controls are a foundational pillar of digital sovereignty. They let organizations maintain transparency, accountability, and autonomy over their cloud operations and infrastructure. These controls ensure that digital environments align with local laws, organizational policies, and strategic priorities, especially in regulated industries like finance, healthcare, and government.

Operational controls go beyond compliance. They enable self-determined governance and resilient operations in a globally distributed cloud ecosystem.

## Why operational controls matter

As organizations increasingly rely on cloud services, they face challenges such as:

- Regulatory compliance across jurisdictions
- Visibility into provider operations
- Control over production environments and access
- Auditability and incident response

Operational controls help address these challenges by letting organizations monitor, restrict, and validate operational activities, whether performed by internal teams or external cloud providers.

## Key capabilities

### Access governance

Operational controls define who can access production systems, when, and how. The entities that can access the production systems include:

- Customer Lockbox: Requires explicit approval before Microsoft engineers can access customer content.
- Data Guardian: Records production touches for audit and compliance.

### Policy enforcement

By using Azure Policy and Sovereign Landing Zones, organizations can enforce operational standards across cloud environments. These standards include:

- Baseline configurations for virtual machines, databases, and networking.
- Policy sets that align with sovereignty requirements, such as the EU Digital Commitments.
- Open-source templates for regulated deployments.

### Monitoring and incident response

Operational controls include tools and processes for:

- Security event logging and alerting.
- Automated evidence collection.
- Business continuity and disaster recovery planning.

Services like Microsoft Sentinel, Defender for Cloud, and Data Guardian often surface these capabilities.

### Operational transparency

Transparency is a core principle of operational sovereignty. Organizations must be able to:

- Audit provider operations.
- Validate compliance independently.
- Control operational workflows across jurisdictions.

## Next steps

- Establish baseline policy compliance dashboards (L1–L3, exceptions, drift).
- Implement supervised access (Data Guardian / Lockbox) for regulated workloads.
- Define evidence capture scripts for audits (region, key usage, attestation).

## See also

- [Data controls](data-controls.md)
- [Digital sovereignty](digital-sovereignty.md)
- [Key controls](key-controls.md)
- [Technological independence](technological-independence.md)
- [Data Guardian](public/data-guardian.md)
- [Regulated Environment Management](public/regulated-environment-management.md)