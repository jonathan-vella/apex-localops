---
title: "Confidential computing overview"
description: "Protect data in use with confidential computing in the Sovereign Public Cloud."
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

# What is confidential computing? 

Confidential computing protects data in use by running computation inside a hardware‑based, attested Trusted Execution Environment (TEE), as defined by the Confidential Computing Consortium (CCC). Microsoft is a founding member of the CCC and provides confidential computing capabilities in Azure aligned with this definition. For more information, see the [Azure confidential computing overview](/azure/confidential-computing/overview).

Azure confidential computing complements encryption at rest and in transit by extending protection to data while it's being processed. When you enable and properly configure confidential computing, Azure processes data inside attested TEEs designed to help prevent unauthorized access or modification—even from cloud operators.

In Sovereign Public Cloud, confidential computing is one of the sovereign controls that help public sector and regulated organizations adopt the hyperscale cloud while meeting sovereignty, compliance, and policy requirements.

## Why it matters

### Data sovereignty

Data sovereignty strengthens confidentiality beyond residency. The key aspects include:

- **Protect data in use**: Confidential computing helps ensure that sensitive data remains protected while processed in memory, adding a crucial layer that complements residency controls and encryption at rest/in transit.
- **Reduce exposure to operator access**: Processing inside hardware‑based, attested TEEs is designed to prevent access to plaintext data by cloud operators.

### Operational sovereignty

Operational sovereignty strengthens verifiability and reduces operator trust. The key aspects include:

- **Attestation for runtime integrity**: Confidential computing provides attestation so workloads can verify the TEE’s hardware and software measurements before releasing secrets or handling sensitive data, supporting auditable and policy‑driven operations.
- **Alignment with sovereignty guardrails**: Sovereign Public Cloud uses Azure policy sets and the Sovereign Landing Zone (SLZ) to codify controls (for example, service location and confidentiality options) so deployments can be configured and monitored consistently.

### Technological sovereignty

Technological sovereignty strengthens choice and control. The key aspects include:

- **Portfolio of confidential options**: Azure offers confidential computing across virtual machines and containers. Teams can select TEE models that fit application patterns while maintaining confidentiality assurances. For more information, see [Confidential containers](/azure/confidential-computing/confidential-containers).
- **Integrity services for audit data**: Azure Confidential Ledger provides an immutable, tamper‑resistant store for sensitive records and audit trails, supporting integrity and selective verification scenarios. For more information, see [Azure Confidential Ledger](/azure/confidential-ledger/overview).

## Key features

### Trusted Execution Environments (TEEs)

TEEs are hardware‑backed, attested environments that help prevent unauthorized access or modification of applications and data while in use. Azure’s approach aims to reduce the need to trust platform operators and other privileged layers by enforcing hardware‑rooted isolation and verification.

### Confidential Virtual Machines (VMs)

Confidential VMs provide memory‑encrypted compute with attestation, enabling lift‑and‑shift protection for many workloads. VM‑level confidentiality helps apply sovereign controls to broad classes of applications without major code changes.

### Confidential containers

Confidential containers run standard container images inside attested TEEs, offering data confidentiality and runtime code integrity with container‑native workflows. Teams can use familiar orchestration patterns while maintaining protections against unauthorized access during processing.

### Confidential ledger for audit integrity

Azure Confidential Ledger provides an immutable, verifiable store for sensitive logs and records, designed to protect against insider threats and enable selective sharing and verification.

## Architecture and policy considerations

Sovereign Landing Zone (SLZ) is an opinionated variant of Azure Landing Zone that incorporates policy‑as‑code to help enforce sovereignty controls—such as service location management, customer‑managed keys, and confidential computing considerations—across environments. 

## Common scenarios

The following common scenarios show how confidential computing can help you meet sovereignty, compliance, and policy requirements:

- Regulated workloads that require data‑in‑use protection to comply with policy or reduce operator access risk in multitenant infrastructure.
- Containerized applications that need enclave or VM‑based TEEs without major code changes and benefits from attestation and runtime integrity assurances.
- Audit‑critical systems that need tamper‑resistant, verifiable logs for compliance or oversight.

## See also

- [Azure confidential computing overview (concepts, threat model, attestation)](/azure/confidential-computing/overview)
- [Azure Confidential Containers with AKS](/azure/aks/confidential-containers-overview)
- [Confidential containers on Azure](/azure/confidential-computing/confidential-containers)
- [Azure Confidential Ledger](/azure/confidential-ledger/overview)  
- [Sovereign Landing Zone](overview-sovereign-landing-zone.md)
