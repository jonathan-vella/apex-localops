---
title: "Implement workloads in the Sovereign Public Cloud"
description: "Overview of how to implement workloads in the Sovereign Public Cloud."
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
# Implement workloads in the Sovereign Public Cloud

This article provides an overview of how to implement workloads in the Sovereign Public Cloud.

## Classify data for sovereignty

By categorizing data based on sensitivity and regulatory requirements, you can protect data, maintain compliance, and reduce risk. 

| Risk sensitivity | Description |
|--------------|-------------|
| Low | Loss of confidentiality, integrity, or availability has a limited adverse effect on organizational operations, assets, or individuals. |
|Moderate | Loss has a serious adverse effect on operations, assets, or individuals. |
|High | Loss has a severe or catastrophic adverse effect on operations, assets, or individuals. |

Not all organizational data requires the same controls. Classification enables teams to prioritize security and sovereignty efforts and allocate resources where they're most effective. High-risk data, such as personal data or state secrets, requires stronger safeguards and more rigorous monitoring. Low-risk data can be eligible for broader platform services that enable modernization and innovation.

Define clear, predefined criteria for classification. Formal classifications aren't mandated by standards such as NIST, so adopt a risk-based framework appropriate for your organization.

> [!TIP]
> You can find information on defining your organization's data classification model in the [Well-Architected Framework: Architecture strategies for data classification](/azure/well-architected/security/data-classification).

Risk criteria can include data type, sensitivity, regulatory obligations, and business value. Use tools that analyze attributes, patterns, and metadata to assign classifications consistently and efficiently. After labeling data, apply appropriate security controls, encryption, and policy actions for each classification.

Although NIST defines three impact levels, many organizations use a four-label classification scheme: Public, Internal, Confidential, and Secret.

## Evaluate Azure services for sovereignty controls

Azure offers hundreds of services, each with unique configuration and data-handling characteristics. Not all sovereign controls apply to every service. For example, some services don't support customer-managed keys (CMK), and others don't store customer data at all. To enforce meaningful data sovereignty controls, you need to understand how each service processes and stores data.

**Key considerations:**

- **Data storage:** Does the service store customer data? If not, some controls (like encryption at rest) don't apply.
- **CMK support:** Does the service support customer-managed keys, and can it use Azure Managed HSM?
- **Confidential computing:** Is confidential computing relevant (for example, if TLS traffic is inspected)?
- **Data residency:** Where is the data stored and processed?
- **Service role:** What type of data does the service handle (for example, sensitive data vs. metadata)?

**Examples:**

- A load balancer doesn't store data, so encryption at rest isn't required. However, confidential computing might be relevant if TLS traffic is inspected.
- Some services, like Azure Front Door CDN, cache data temporarily or distribute content globally.
- A metadata database with VM names or GUIDs requires less stringent controls than a VM hosting credit card data.
- Azure Network Manager stores network configuration but doesn't process actual network traffic.

**Best practices**

For each service, assess its capabilities, architectural role, and the type of data it handles. This assessment helps you apply the right level of control and ensures compliance with sovereignty requirements. You can document services using a matrix as follows: 

| Service residency | Data residency | Data transit encryption | Data at-rest encryption | ACC |
|-------------------|----------------|-------------------------|-------------------------|-----|
| The service instance runs in the chosen region. | Data stored by the service is located in the chosen region. (N/A indicates the service doesn't actively store customer data.) | Connectivity to and from the service is encrypted (for example, HTTPS/TLS). | If data is stored, use Customer Managed Keys (CMK) via Key Vault (Standard/Premium) or Managed HSM. "Platform" indicates default Azure encryption. | Indicates if the service can use Azure Confidential Computing (ACC) to protect in-memory data. |

## Establish governance policies for consistent compliance

- Require customer-managed keys (CMK) for persistent storage services, such as Azure Storage, Azure SQL Database, and Cosmos DB.
- Enforce regional affinity for services that might otherwise replicate or cache data globally, such as Front Door, CDN, or Traffic Manager.
- Restrict the use of services in sensitive workloads if they lack residency or encryption features.
- Enable confidential computing where applicable, such as VM series with AMD SEV-SNP or Intel TDX.

## How to use the matrix with your data classification model

Use the capability matrix as a reference when designing your application architecture. Mapping supported sovereign controls for each service helps architects and security teams understand which guarantees they can enforce.

- For services that process restricted or highly confidential data, such as financial transactions, health records, or government identifiers, enforce strict CMK usage, strong residency guarantees, and confidential computing (ACC) where applicable.
- For services that handle only operational metadata, such as VM names, topology configuration, or GUIDs, platform encryption or reduced controls might be sufficient.

By combining the capability matrix with your data classification model, you can design each workload with a clear, enforceable security posture. This approach helps you meet regulatory obligations and strengthens trust and operational resilience in sovereign cloud environments.

## See also

- [Design sovereign policies](./design-sovereign-policies.md)
- [Encryption overview](/azure/security/fundamentals/encryption-overview)
- [VPN private peering](/azure/vpn-gateway/site-to-site-vpn-private-peering)