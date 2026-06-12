---
title: "Data controls"
description: "Understand the concept of data controls in the context of cloud services and data management."
author: ronmiab
ms.subservice: sovereign-public-clouds
ms.topic: overview
ms.date: 10/06/2025
ms.author: robess
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---

# Data controls

Data sovereignty is a critical concept in cloud governance and compliance. It refers to the legal and regulatory authority that a country/region or organization has over data, particularly in relation to where that data is stored and processed. This concept shapes how sensitive workloads are architected, governed, and audited in cloud environments. In this article, you explore the principles of data sovereignty and how they apply to cloud environments.

## What is data sovereignty?

Data sovereignty is a multifaceted concept, which asserts that data is subject to the laws and governance of the country/region where the data is physically located regardless of who owns or manages the data. This concept means that nations have the right to exercise legal authority over data stored within their borders.

However, while Microsoft allows you to choose where your data resides, the rights of the hosting country/region are limited in the context of accessing that data. Regulators can't demand access to data solely based on its location. Instead, access is governed by legal processes and customer-controlled safeguards.

## Key principles

Data sovereignty is built on four foundational principles:

| Principle                  | Description                      |
|---------------------------|----------------------------------------------|
| Data Ownership         | Organizations retain ownership and control of their data, even when stored in third-party cloud services. |
| Data Protection & Privacy | Sensitive data must be protected through robust security measures and compliance with local privacy regulations. |
| Cross-Border Data Transfer | Movement of data across international borders is subject to regulatory scrutiny and is restricted by national laws. |
| Legal Jurisdiction     | The legal framework governing data is determined by its physical location, regardless of the data owner's origin. |

## Encryption as a sovereignty control

In cloud environments, encryption plays a central role in enforcing data sovereignty. Data is encrypted by default, ensuring that physical access to infrastructure doesn't grant access to readable data. Only the data owner or system holds the encryption keys, making encryption the primary mechanism for maintaining control over cloud-hosted data. To provide comprehensive protection across the data lifecycle, encryption is typically applied in three distinct states: at rest, in transit, and in use. Each encryption state addresses different stages of data handling and exposure risk.

| Encryption Type         | Description                                                                 |
|-------------------------|-----------------------------------------------------------------------------|
| Encryption in transit | Secures data as it moves across networks - between devices, services, or data centers. Typically implemented using TLS. |
| Encryption at rest  | Protects data stored on disk or other persistent storage, such as databases, file systems, and backups. |
| Encryption in use   | Protects data while it's actively being processed in memory or CPU. Often involves confidential computing technologies. |

By default, all Azure services use encryption in transit, including region-to-region communications. Services typically implement encryption by using TLS certificates, which are automatically generated when a service is provisioned and signed by a trusted public certificate authority. In some scenarios, you can bring your own certificates by either importing a PFX file (with the private key) into a service or [managing the certificate through Azure Key Vault](/azure/key-vault/certificates/about-certificates).

All services in Azure use server-side encryption for data at rest with platform-managed keys (PMKs). The platform generates and maintains these keys for you. Many services also support customer-managed keys (CMKs). Depending on the service, these keys can work in combination with the PMKs for even better protection.
You can store customer-managed keys in either Azure Key Vault (standard or Premium) or, in many cases, in Azure Key Vault managed HSM. For your most sensitive sovereign workloads, use Azure Key Vault managed HSM, as this service guarantees you have full control over the encryption keys in a single tenant environment. You're fully responsible for safeguarding the [security domain](/azure/key-vault/managed-hsm/security-domain), which [must be downloaded](/azure/key-vault/managed-hsm/security-domain#downloading-the-encrypted-security-domain) upon activating your Managed HSM instance.

You can also consider [External Key Management](./public/external-key-management.md) for specific regulated workloads. This service is an extension of Azure Key Vault managed HSM and allows you to own and manage your keys outside of Azure. External key management is a capability that allows customers to use their own Hardware Security Modules (HSMs) to support cryptographic operations for cloud services. By using external key management, you can store your keys in your own HSMs, which are physically separated from the cloud services. This capability, known as Hold Your Own Key (HYOK), ensures that you always retain full control over your keys. This full control comes with more responsibilities as you're responsible for the availability, scalability, and backups of all key material.

While most data security measures are based on at-rest and in-transit encryption of data, [Azure Confidential Computing](/azure/confidential-computing/overview) also extends those capabilities to encryption for data in use. This extension means that the actual compute instance interacting with the (decrypted) data uses encryption itself within its allocated memory space. Azure fully complies with the [Confidential Computing Consortium](https://confidentialcomputing.io/) standards that are available on Intel, AMD, and NVIDIA hardware.

## Data residency

Data residency primarily focuses on where your data physically resides. Practical considerations such as performance, compliance, and business continuity shape data residency. The following table outlines key aspects that influence data residency decisions:

| Aspect                        | Description              |
|------------------------------|---------------------------|
| Latency and performance  | Data residency decisions can impact the speed and performance of data access. Placing data closer to end users reduces latency and improves the overall user experience.                                |
| Compliance requirements  | Choose data residency options that align with local and industry-specific compliance requirements. This choice ensures that data is stored in a manner consistent with applicable regulations. |
| Legal jurisdiction       | Data residency revolves around the choice of data center or cloud region where data is stored. While data is typically subject to the laws of its physical location, some countries or regions assert legal authority over data held by domestic cloud providers, regardless of physical location. |
| Data availability and redundancy | Data residency considerations influence redundancy and disaster recovery strategies. Organizations and cloud providers might replicate data to multiple regions to ensure high availability and resilience. |

By using Azure, Microsoft 365, and Dynamics 365, you can choose where your data is stored to meet data residency requirements. By using strategically aligned data center regions within the same geography through [Azure region pairs](/azure/reliability/regions-paired), you can enhance geo-redundancy, ensure prioritized recovery, and benefit from staggered platform updates, all while maintaining compliance and improving data resilience.

## Next steps

- Determine required residency scope and allowed Azure regions per classification.
- Inventory encryption coverage (at rest, in transit, and in use) against current workloads.
- Define key ownership model (PMK → CMK → Managed HSM → EKM) per data tier.

## See also

- [Data encryption models](/azure/security/fundamentals/encryption-models)
- [Azure Rights Management encryption service](/purview/azure-rights-management-learn-about)
- [Managed HSM disaster recovery](/azure/key-vault/managed-hsm/disaster-recovery-guide)
- [Digital sovereignty](digital-sovereignty.md)
- [Key management](./key-controls.md)
- [Operational controls](./operational-controls.md)
- [Technological independence](./technological-independence.md)
- [Confidential computing?](public/confidential-computing.md)