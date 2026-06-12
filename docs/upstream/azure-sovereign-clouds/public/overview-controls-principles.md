---
title: "Controls and principles in Sovereign Public Cloud"
description: "Foundational controls and principles guiding the Sovereign Public Cloud."
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

# Controls and principles in Sovereign Public Cloud

This article covers the three foundational sovereign controls: data residency, encryption (at rest, in transit, and in use), and confidential computing. It also details how Azure implements these controls through policy-as-code, key management, and confidential execution options. 

Organizations in government, finance, healthcare, and other regulated industries use the public cloud, making sovereignty a critical design principle. Sovereign controls help workloads comply with national regulations and organizational policies while letting you benefit from the agility of cloud platforms. Three pillars define this model:

- **Data residency** – Data remains within specific national or regional boundaries. Azure addresses this need by offering the EU Data Boundary to help ensure data for in-scope services stays within the EU jurisdiction.

- **Encryption** – Encryption is a cornerstone of data sovereignty that ensures sensitive information remains protected regardless of where it resides or travels. Encryption in transit protects data moving across networks, and encryption at rest secures data on disks, databases, and other persistent stores. These protections are standard. Sovereign cloud deployments use customer-managed keys, hardware security modules (HSMs), and integration with national cryptography standards to ensure that only authorized entities can access sensitive information.

- **Confidential computing** – Encryption in use extends protection to data while it’s being processed in memory. This encryption is achieved through confidential computing, a technology that uses secure enclaves and trusted execution environments (TEEs) to keep data protected even while it's processed. TEEs are isolated environments within the CPU that protect both the data and the code from unauthorized access, even from the cloud provider or system administrators. This pillar helps organizations meet high levels of security assurance, and prevents unauthorized access by cloud operators or foreign jurisdictions.

Together, these controls form the foundation of sovereign cloud architectures. They enable organizations to adopt the scalability of public cloud while retaining trust, compliance, and jurisdictional control over their most critical workloads.

## Sovereign data controls in Azure


Azure implements sovereign controls (also called compliance controls) through Azure Policy. Policies monitor or enforce settings for deployed services. Three foundational controls form the core: data residency (restrict deployment to approved regions), encryption at rest (customer-managed keys), and encryption in use (confidential compute), implemented by allowing only specific SKU types. Additional policies can control allowed services, security settings, private endpoints, network controls, and more.

Organizations can combine multiple policies and create an initiative for specific compliance requirements, then apply it to the corresponding data/workloads. Policies help ensure regulatory compliance and enforce security baselines. Azure provides several baseline security policy initiatives that complement sovereign controls. The content of initiatives varies per country/region, industry, and customer. However, in general, the sovereign policies monitor the following foundational controls:

| Classification level       | Public                     | Internal                  | Confidential              | Secret                     |
|----------------------------|----------------------------|---------------------------|----------------------------|----------------------------|
| Access                   | All Access                 | Employees/ Partners            | Employees/ Teams                | Individuals / Systems      |
| Level 1 - Data residency| Optional                   | Required                  | Required                   | Required                   |
| Level 2 - Encryption-at-rest/in-transit | Optional          | Optional                  | Required                   | Required                   |
| Level 3 - Encryption-in-use | Optional         | Optional                  | Optional                   | Required                   |
| Examples               | Public websites, manuals   | Email, documents, meeting invites | IP, Financials, HR, research | DNA, Credit Card           |

Apply Azure Policy definitions and initiatives to resource groups, subscriptions, or management groups. Deploy an Azure Sovereign Landing Zone to centrally manage workloads and sovereignty controls.

## Level 1 - Data residency

Data residency primarily focuses on where your data physically resides. Data residency control policies restrict your deployments to particular regions only. These policies are based on practical considerations such as performance, compliance, and business continuity. For sovereignty, however, it's important to understand the difference between regional and non-regional services that are available in Azure, as they handle data storage differently:

- **Data storage for regional services**: Most Azure services are deployed regionally and enable customers to specify the location into which the service and its data are deployed. Microsoft doesn't store your data outside the specified geography, except for a few regional services and preview services. This commitment helps ensure that data stored in a given region remains in the corresponding geography and isn't moved to another geography for most regional services.

- **Data storage for non-regional services**: Certain Azure services, also called global services, don't let you specify the region where the services are deployed. These services use a combination of regional deployments with global replication. While data can be encrypted, it isn't guaranteed to remain within a single region. Examples include Azure Front Door, Traffic Manager, Azure Policy, Azure DNS, and more.

> [!NOTE]
> While a service might be locally available in a region, the data characteristics of a service might still replicate or move data out of the chosen region. For data residency requirements, it's important to understand each service's data handling characteristics. For more information on the list of services per regional and non-regional services, see [*product availability by region*](https://azure.microsoft.com/explore/global-infrastructure/products-by-region/table).

## Level 2 - Encryption at-rest/in-transit

### Encryption at-rest

All Azure services implement server-side encryption for data at rest by using platform-managed keys (PMKs). Microsoft automatically generates, stores, and maintains these keys to ensure baseline encryption without requiring customer configuration. However, for data sovereignty controls, use customer-managed keys (CMKs) that can be stored in Azure Key Vault (Standard or Premium tiers) or Azure Key Vault Managed HSM.

For workloads with elevated sovereignty or compliance requirements, Azure Key Vault Managed HSM is recommended. This service provides exclusive control over encryption keys, ensuring that only the customer can access or manage them. However, not all Azure services support Azure Key Vault Managed HSM for CMK storage. An updated list of supported CMKs can be found on the [Services that support customer managed keys (CMKs)](/azure/security/fundamentals/encryption-customer-managed-keys-support) page.

Azure Managed HSM External Key Storage allows you to protect resources with cryptographic keys that are physically held outside of Microsoft premises. This capability is aimed at highly regulated workloads where encryption must use keys stored at a customer-controlled facility. This approach, known as Hold Your Own Key (HYOK), ensures that services rely on encryption keys that never leave customer control but has an impact on the SLAs of the dependent services. The decision of when to use External Key Storage must be based on several factors that are explained in the [Sovereign Concepts - Key Management](../key-controls.md) chapter.

> [!NOTE]
> Each service uses its own implementation of customer-managed key-based encryption. Some services store temporary data unencrypted by using platform-managed keys. Make sure you understand the service implementation of customer-managed keys. For more information, see the [service documentation pages](/azure/security/fundamentals/encryption-customer-managed-keys-support).

### Encryption in transit

By default, most services in Azure use in-transit encryption. Most services utilize a TLS certificate generated by the service upon provisioning and signed by a public certificate authority. You can find more information on in-transit encryption for services on the [Data Security and encryption page](/azure/security/fundamentals/encryption-overview#encryption-of-data-in-transit).

Whenever Azure customer traffic moves between datacenters, outside physical boundaries that Microsoft doesn't control (or on behalf of Microsoft), a data-link layer encryption method using IEEE 802.1AE MAC Security Standards (MACsec) is applied from point to point across the underlying network hardware. This mode helps ensure all Azure traffic traveling within or between regions is encrypted by default.

When data is sent to non-Microsoft endpoints (including customer environments), the encryption in transit depends on the service protocol or underlying connection. For example, unencrypted HTTP traffic can be intercepted at multiple points, which is why TLS/HTTPS is always recommended for transmitting confidential data. Alternatively, you should make the connection over a VPN to provide an encrypted link over which packets can be sent and received regardless of protocol encryption.

A Virtual Private Network (VPN) provides secure, private connectivity to Azure virtual networks by using industry-standard encryption protocols. You can configure VPNs for User VPN (dial-up VPN) for individual end users, or site-to-site VPN for connecting on-premises networks to Azure virtual networks. VPN encryption can be based on pre-shared keys (most common) or certificates, and you can choose different algorithms to balance security strength versus processing overhead.

You can also use ExpressRoute to connect to Azure networks. The dedicated, SLA-backed private connection operates at Layer 2 by default and is commonly used for larger enterprises. However, ExpressRoute connections in their default configuration don't provide native encryption. While many Azure services apply TLS-based encryption to their own traffic, it isn't universal (for example, some server-to-server replication). To provide an encrypted underlying connection for all traffic, use VPN over ExpressRoute or ExpressRoute MACsec. This feature ensures confidentiality regardless of higher-level protocol.

## Level 3 - Encryption in use

[Azure Confidential Computing (ACC)](/azure/confidential-computing/overview) supporting services implement encryption in use. By using ACC, you establish a hardware-based encryption of the memory of an entire VM or application, ensuring that no operator, system, or third-party outside the trusted environment can access memory space or make a memory dump. This encryption means secrets, application code, and data are protected from intrusions outside of the workload. For many ACC workloads, attestation is available through the Azure attestation service. The service provides a signed JSON report with the details of the TEE specifically for that workload. Developers use this report in their applications to ensure a trusted environment is created before executing or handling sensitive data or loading encryption keys. Azure Confidential Computing uses third-party attested and implemented encryption methods that don't require Azure Key Vault or Azure Key Vault Managed HSM. However, these services are required when ACC is combined with Azure Disk Encryption, Azure Confidential Disk Encryption, or in specific scenarios. The keys used for memory encryption are embedded in the physical CPU and aren't extractable or humanly readable.

The combination of attestation and confidential computing enables a powerful architecture known as [Secure Key Release](/azure/confidential-computing/concept-skr-attestation). In this architecture, applications use client-side encryption with customer-managed keys (CMKs) stored in Azure Key Vault (Premium) or Azure Key Vault Managed HSM. By default, these services enforce non-exportability of keys. Customers can define release policies that let private keys be released only under specific conditions - for example, requiring the application to prove it's running inside an AMD SEV-SNP–protected environment by using the attestation service.

By using Secure Key Release, the decryption key is only released into a Trusted Execution Environment (TEE) after the application provides its identity and an attestation report that satisfies the key's release policy. This feature ensures encrypted data can ever be decrypted only inside the TEE, never outside it. While other cloud providers offer confidential computing and attestation, Azure is unique in natively integrating these capabilities with Key Vault and/or Managed HSM, providing a policy-driven mechanism that directly ties key release to TEE attestation.

> [!TIP]
> Treat Level 3 as progressive. Start by measuring confidential compute readiness (attestation signals, supported SKUs) before enforcing hard deny policies.

## Custom levels - Data masking and advanced encryption

With the three levels for sovereignty, some services have capabilities that fall in-between the levels. For example, while a database might not run on confidential computing, [Transparent Database Encryption (TDE)](/azure/azure-sql/database/transparent-data-encryption-tde-overview) achieves a nearly identical result (a memory dump shows encrypted data). Similarly, a storage account can use a platform-managed key if the data stored on that storage account uses client-side encrypted (CSE) data with a Customer Key.

These services provide the following (minimal) two extra levels:

- Level 2+ (using customer data encryption in memory or CSE for storage on regular compute)
- Level 3+ (using advanced ACC and CSE)

These custom levels can directly impact the sovereign policies applied to your workloads. For example, organizations might run a standard database with TDE enabled for level-3 classified workloads. Depending on the chosen technology, Azure policies can be enforceable.

Similarly, some applications can require only [Intel SGX](/azure/confidential-computing/confidential-computing-enclaves) with secure key release in combination with client-side encryption. These configurations need to be incorporated into the policy pack (as level 3+, for example) or directly into the architecture of an application and hosted as level 3 classified workloads.

## Next steps

- Review the [Sovereign Landing Zone](overview-sovereign-landing-zone.md) architecture to map controls to management groups.
- Plan policy layering with the [Design sovereign policies](design-sovereign-policies.md) article.
- Identify encryption scope and key strategy using [Key management controls](../key-controls.md).
- Assess confidential compute applicability via [Confidential Computing](confidential-computing.md).

## See also

- [Implementing sovereign Azure workloads](overview-implement-workloads.md)
- [Confidential Computing](confidential-computing.md)
- [External Key Management](external-key-management.md)
- [Data controls](../data-controls.md) 
- [Operational controls](../operational-controls.md)