---
title: "Microsoft Sovereign Cloud glossary"
description: "Key terms and abbreviations used across Microsoft Sovereign Cloud guidance."
author: ronmiab
ms.subservice: sovereign-public-clouds
ms.topic: concept-article
ms.date: 10/13/2025
ms.author: robess
ms.collection:
  - microsoftcloud-sovereignty
  - microsoftcloud-seo-priority
---

# Microsoft Sovereign Cloud glossary

Use this glossary to align on common terminology across sovereignty concepts, capabilities, and implementation guidance.

| Term | Definition |
|------|------------|
| ALZ (Azure Landing Zone) | Microsoft Cloud Adoption Framework reference architecture providing foundational design areas for Azure at scale. |
| SLZ (Sovereign Landing Zone) | Variant of ALZ incorporating sovereign control layers (region, encryption, confidential compute) via policy‑as‑code. |
| Sovereign controls | Technical and governance mechanisms enforcing data residency, encryption (at rest, in transit, or in use), service allowlists, and operational oversight. |
| Data residency | Restricting storage and processing of customer data to approved geographic regions. |
| CMK (Customer‑managed key) | Encryption key owned/managed by the customer in Azure Key Vault or Managed HSM (Hardware security module), used for service encryption at rest. |
| Managed HSM | FIPS 140‑3 Level 3 validated, single‑tenant Hardware Security Module service for hosting customer-managed keys. |
| External Key Management (EKM) | Capability allowing cryptographic operations with keys stored outside Microsoft's cloud boundary (Hold Your Own Key). |
| HYOK (Hold Your Own Key) | Pattern where encryption keys never leave customer‑controlled HSM infrastructure. |
| Confidential computing | Protecting data in use via hardware‑based Trusted Execution Environments (TEEs) with attestation. |
| TEE (Trusted Execution Environment) | Hardware‑backed isolated execution context providing confidentiality and integrity for code and data. |
| Attestation | Cryptographic verification of a TEE's identity and measured launch state before releasing secrets. |
| SKR (Secure Key Release) | Mechanism tying key release from Key Vault / Managed HSM to attestation policies for confidential workloads. |
| L1 / L2 / L3 | Sovereign policy levels: L1 (data residency and service scope), L2 (encryption at rest with CMK/HSM), L3 (confidential compute / in‑use encryption). |
| REM (Regulated Environment Management) | Unified orchestration and monitoring layer for sovereign operations. |
| Data Guardian | Capability providing supervised, approved, and logged provider operational access with a tamper evident ledger. |
| Advanced Data Residency in Microsoft 365 | A Microsoft 365 feature ensuring specified data categories remain within designated geography. |
| Model provenance | Traceability of AI model lineage including source model, fine‑tuning data, versions, and integrity hashes. |
| Drift (policy) | Divergence between current resource configuration and enforced/expected sovereign policies. |
| JIT (Just‑in‑time access) | Time‑bound elevation model for privileged operations, limiting standing administrative exposure. |
| Vector store | Specialized index or database holding embeddings derived from unstructured data for AI workload retrieval. |
| Embedding | Numerical representation of content used by AI systems for semantic similarity and retrieval. |
| vTPM | Virtual Trusted Platform Module attached to Gen2 / confidential VMs storing boot integrity and encryption protector artifacts. |
| RPO / RTO | Recovery Point Objective / Recovery Time Objective—core metrics for resilience planning. |
| Exception (sovereign policy) | Approved, time‑boxed deviation from a sovereignty control with documented justification and mitigation. |

## See also

- [Controls and principles](public/overview-controls-principles.md)
- [Sovereign landing zone](public/overview-sovereign-landing-zone.md)
- [Confidential computing](public/confidential-computing.md)
- [External key management](public/external-key-management.md)
- [Design sovereign policies](public/design-sovereign-policies.md)

