---
title: "Key management controls"
description: Learn about key management controls in sovereign cloud.
author: ronmiab
ms.subservice: sovereign-public-clouds
ms.topic: overview
ms.date: 11/13/2025
ms.author: robess
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---

# Key management controls

This article details key management controls for sovereign cloud scenarios, focusing on the security considerations and trade-offs between different approaches to key management and sovereignty. It provides guidance for organizations evaluating where to store and manage their cryptographic keys based on sovereignty, compliance, and operational requirements.

For comprehensive information on Azure's key management solutions, including detailed product comparisons and selection guidance, see:

- [Key management in Azure](/azure/security/fundamentals/key-management)
- [How to choose the right key management solution](/azure/security/fundamentals/key-management-choose)
- [Managed HSM technical details](/azure/key-vault/managed-hsm/managed-hsm-technical-details)

## Azure Key Vault Managed HSM for key sovereignty

Cryptographic keys are essential for protecting sensitive data and ensuring the integrity and authenticity of digital transactions. Organizations evaluating key management approaches for sovereign cloud scenarios need to understand the options available and their trade-offs.

Azure Key Vault Managed HSM provides key sovereignty through FIPS 140-3 Level 3 validated security with full customer control of keys, single-tenant isolation, and customer-controlled security domains. It maintains Azure's service-level agreements and eliminates the operational overhead of physical HSM management. For more information, see [Azure Key Vault Managed HSM](/azure/key-vault/managed-hsm/overview).

Azure continues to expand its key management portfolio to address diverse sovereignty requirements. This article also discusses external key management as a conceptual approach where keys are hosted in customer-owned HSMs physically separated from cloud infrastructure, to provide context for evaluating different sovereignty models.

## Key protection architecture

When evaluating key management solutions, it's important to understand the attack vectors that could compromise key security:

**Private key material extraction**: The private key material is protected by many mechanisms that a physical HSM provides. Extracting the keys can lead to offline attacks, where an attacker needs a copy of the encrypted data and the private keys from the HSM. By default, an HSM protects private key material or private keys both inside and outside the HSM. For the protection, HSMs rely on Security Worlds or partitions to secure the key material inside and outside the HSM. The wrap and unwrap functions (encrypting or decrypting a data encryption key) of a key should only run inside the HSM's trusted environment. In addition, protected backups and protected external key storage are also available. The HSM handles the protection by wrapping all the material and leaves the HSM with a masking key, which is only known to the partition from which the key is released. Usually, only the combination of the masking key and key (HSM) backup can expose a private key. However, in some cases, keys might be marked as exportable, letting them leave the HSM in an unprotected state.

**Unauthorized use of the service**: Although the HSM protects the keys, attackers can misuse the service without necessarily leaking the keys. Unauthorized users capable of using the wrap/unwrap function of the key management API (fronting the HSM) can expose the data encryption key (DEK) by sending the encrypted DEK to the service, and therefore, compromise the data protected by the DEK. While the HSM protects the private key material, the API in front of the HSM that interacts between the calling service and the HSM also needs to be protected.

Securing keys requires both protecting the HSM boundary and the surrounding services and architectures that interact with the HSM.

## Azure Key Vault Managed HSM

Azure Key Vault Managed HSM is a fully managed, cloud-based HSM service that provides FIPS 140-3 Level 3 validated security with single-tenant isolation and full customer control of cryptographic keys. This service delivers key sovereignty while maintaining operational simplicity. For detailed information about the service, its capabilities, and architecture, see [What is Azure Key Vault Managed HSM?](/azure/key-vault/managed-hsm/overview)

The service addresses key security requirements through confidential computing architecture:

:::image type="content" source="media/managed-hsm-overview.png" alt-text="Managed HSM Architecture":::

### Security architecture highlights

Azure Key Vault Managed HSM leverages [Azure Confidential Computing](public/confidential-computing.md) to create an environment that matches or exceeds external HSM security. For comprehensive technical details, see [Managed HSM technical details](/azure/key-vault/managed-hsm/managed-hsm-technical-details).

- A Trusted Execution Environment (TEE) is created for each instance that the customer uses.
- The TEE is based on external trust and keys outside of Microsoft control (Intel Software Guard Extensions (SGX)).
- All secrets used by the service are generated inside the TEE-secured instance.
- No clear-text secrets in active memory on the physical hosts
- No human or system outside of the trusted environment has the HSM credentials.
- Access to the service is programmatically limited to the customer's Microsoft Entra ID instance.
- Only customers can request, download, and decrypt the security domain (including masking key). The cloud doesn't store this information.
- Private key material in the HSM is set to nonexportable unless requested for secure key release. Regular keys are nonexportable and the HSM therefore doesn't release the private key material in an unmasked state
- The HSM has an audit log to view interactions on the HSM partition.

### Security evaluation against attack vectors

Because Azure hosts the HSM and keys, you need to evaluate protection against the two primary attack vectors:

**Private key material extraction**:

- A Marvel Liquid HSM running regular firmware is used to provide the private key material protection
- The credentials to the HSM itself aren't humanly readable and are solely stored inside the trusted execution environments of the system
- The customer solely holds the masking key that protects the private key materials. The masking key is protected by the keys you generate and manage. It's the customer's responsibility to safeguard the masking key. This separation ensures the keys (backups) and the masking key (protection for those keys) are stored in two different places.
- While Microsoft Azure can take full backups of the physical HSM (including all partitions), each individual partition masking key protects this backup. Only the customer has access to this key, and it's protected by the key pairs that the customer creates and manages.
- Intended or unintended exposure of the security domain doesn't provide access to the keys. For attackers to gain access to private key material, they need to gain access to a (key) backup, the security domain, and the customer-generated keys used to protect the security domain.
- Intended or unintended exposure of the backup doesn't allow attackers to gain access to private key material as they also need to have the security domain and the customer-generated keys used to protect the security domain, which shouldn't be stored in Azure.

**Unauthorized access or usage**:

- Access to the service is limited to the customer's Microsoft Entra ID-signed authentication tokens. The service uses two ACL lists: Azure RBAC for creating and deleting instances, and HSM RBAC for HSM roles. While a single Entra ID is used, an Azure subscription owner can't take forced control of the Managed HSM if they don't have access to the HSM.
- An emergency HSM Administrator role exists for the "Entra ID Global Admins" group. Regardless of permissions on Azure subscriptions, access to the Managed HSM instance allows an Entra ID Global Admin to take control of the HSM. It doesn't provide them with access to private key materials, but it does allow them to change the HSM ACL list. Use caution on Global Admins memberships.
- The credentials of each individual HSM partition are never exposed, so unauthorized systems or persons can't misuse the credentials.
- The Trusted Execution Environment generates the TLS (https) certificates, making the private key of the service TLS connections solely available to the instance.
- The front-end service runs fully in confidential computing, and external access by other systems or humans isn't possible. The instance can't be moved to a compromised host as the TEE parameters can change. In addition, access to the "secrets store" that holds the credentials and service private keys is only possible on the original physical CPU due to the use of a CPU sealing key inside the TEE.

**Additional security features**:

- The service has built-in redundancies. Each created managed HSM service creates three individual backend instances. A database encryption key shared between all instances and the HSM partitions masking key secure the key exchange between the instances. This security ensures that private key material can only be exchanged between instances in the same service and that private key materials are only accessible when imported into the HSM partitions belonging to the same service instance.
- Management and operational procedures on the HSMs are limited to Azure Fabric controllers. Therefore out-of-bound operations that aren't built-into the service can't be called upon. Direct access to the partitions (and therefore key operations or partition wide operations) is restricted to each unique instance inside their respective TEEs. No human or out-of-bound access to the partition is possible, simply because the credentials to a partition are only known to each instance.

For comprehensive details on Managed HSM architecture, security features, and best practices, see:

- [What is Azure Key Vault Managed HSM?](/azure/key-vault/managed-hsm/overview)
- [Managed HSM best practices](/azure/key-vault/managed-hsm/best-practices)

## External key management architecture

External key management is a conceptual approach where organizations use their own hardware security modules (HSMs) for cryptographic operations while consuming cloud services. This approach physically separates keys from data and cloud infrastructure.

This section provides educational context for understanding external key management architectures, their security considerations, and operational trade-offs. You can compare this architectural pattern against cloud-managed HSM services like Azure Key Vault Managed HSM when evaluating sovereignty requirements. For information about Azure's key management capabilities, see:

- [Key management in Azure](/azure/security/fundamentals/key-management)
- [What is Azure Key Vault Managed HSM?](/azure/key-vault/managed-hsm/overview)
- [Managed HSM technical details](/azure/key-vault/managed-hsm/managed-hsm-technical-details)
- [Encryption models - Host Your Own Key (HYOK)](/azure/security/fundamentals/encryption-models)

:::image type="content" source="media/external-key-management-architecture.png" alt-text="External Key Store Architectures":::

### Architecture components

An external key store architecture typically includes four components:

- The cloud service: This service calls a Key Management Service to provide the unencrypted DEK required to process/unlock the data. The cloud service usually uses a (managed) identity to authorize itself to the targeted Key Encryption Key.
- The cloud-based Key Management Service: This component is typically required as most cloud services are tightly integrated with the provider's key management service. The key management service can serve cloud-hosted keys or have reference or referral keys that point to an external key.
- The Key Management Proxy: As organizations can choose their own HSM (vendor/type), a translation between the Key Management Service and the actual HSM call needs to be made. The proxy has an (external) URL to which the Key Management Service forwards the wrap and unwrap calls. The proxy must convert those calls to the specific vendor HSM API calls. In many cases, the proxy also performs identity conversion and validation as the HSM identity provider might not be the same as the cloud service managed identity.
- The HSM: Various HSMs can be used in the backend, but as continuous access is required, the chosen HSM needs to be always online, and access must be granted on service principles or user accounts that the proxy manages. Given cloud services need regular usage of the keys, the HSM typically can't use quorum-based MFA controls, such as smart cards, for wrap and unwrap procedures.

### Operational considerations

In external key store architectures, customers have full control over the physical HSM and its operational processes, including MFA and multi-approval workflows for administrative operations such as key creation, backup, and restore.

Organizations are fully responsible for hosting and securing proxy components, which play a vital role in service communications. The proxy software must correctly translate API calls and often perform identity translations between cloud services and HSM key usage. Although HSM vendors often provide proxies, the open-standards-based specifications allow for custom implementations.

### Security evaluation against attack vectors

Organizations considering external key stores must evaluate protection against the same attack vectors:

**Private key material extraction**:

- The HSM backup (containing all keys in encrypted state) and the masking key (to unencrypt the backup) are in the same location, managed by the same entity, and protected by the same identity provider (with or without MFA).
- Human-readable credentials are necessary to take ownership of the HSM and perform daily tasks such as backups, key rotation, monitoring, and HSM root partition actions.
- The proxy component can be proprietary, open-source, or self-managed, but it always has full access to the HSM, keys, and interactions. A compromise of the proxy service can lead to a compromise of key material. Depending on how secure the proxy is designed and written, it could have "all keys usage" privileges, which makes its compromise scope larger.
- The Key Management Proxy hosts an externally accessible URL that's protected by a TLS certificate. It's vital that the communications between the cloud Key Management Service and Key Management Proxy aren't interrupted or compromised while the (unencrypted) DEK is returned.

**Unauthorized usage of the service**:

- Storing or handling the credentials for the actual HSM usage (wrap and unwrap operations) by the proxy poses a risk of credential theft. By using those credentials, an unauthorized system can make direct HSM calls for wrap and unwrap operations without validation.
- The cloud-based Key Management Service requires trust as a component in the architecture. This service proxies requests from cloud services to the key management proxy by using a referral key. A compromise of that service could allow unauthorized key replacements or improper wrap and unwrap instructions.
- The cloud-based Key Management Service is responsible for authorizing the cloud service to use the referral key. Once the referral key is called upon, the forwarded request to the key management proxy doesn't necessarily know the calling service or have the ability to validate if the request is properly authorized, other than by validating the Key Management Service's request.

**Other considerations**:

- Organizations are fully responsible for procuring, hosting, and maintaining complex, redundant HSM and proxy infrastructures, including training, operational procedures, and risk management for both unintentional and intentional security incidents.
- Organizations control HSM policies, including the ability to mark keys as exportable, which could reduce security if not properly managed.
- Loss of keys, proxy service availability, or API connectivity results in immediate and irrecoverable data inaccessibility for dependent cloud services.

> [!NOTE]
> While external access to the Key Management Proxy is indicated, host this traffic on customer or cloud provider-controlled networks, such as direct connections and WAN connections. It doesn't require public internet accessibility.

## Evaluating key management approaches

### Trust and security model considerations

Trust in key management extends beyond the physical location of key material. Regardless of approach, trust is required in encryption methods, firmware, and services that mediate between consuming applications and key storage.

**External key management approach:**

- Physical separation of keys from cloud infrastructure
- Requires trust in proxy components that translate cloud-initiated calls into HSM-specific operations
- Maintains dependency on cloud-based key management service integration points
- Places full responsibility for security, reliability, durability, and performance on the organization

**Azure Key Vault Managed HSM:**

- Delivers key sovereignty through [Azure Confidential Computing](public/confidential-computing.md) architecture with Intel SGX-protected credentials
- Provides FIPS 140-3 Level 3 validated HSM protection within Azure datacenters
- Enables multifactor authentication, multi-approval processes, and quorum requirements through Microsoft Entra ID and security domain quorum
- Uses unique security domains with customer-controlled masking keys and protection mechanisms
- Supports standard Azure Key Vault API with RSA-HSM and OCT-HSM key types and algorithms
- Root of trust is external to the cloud provider (both HSM and Intel CPU silicon)
- Responsibility balance: Microsoft handles performance, key integrity, service reliability, and durability; customers safeguard the security domain and protection keys

For detailed comparisons of Azure key management solutions, see [How to choose the right key management solution](/azure/security/fundamentals/key-management-choose).

## Conclusion

Organizations evaluating key sovereignty approaches must balance security requirements, operational capabilities, and trust models. Different architectural patterns exist for protecting key material, each with distinct trade-offs.

Azure Key Vault Managed HSM delivers key sovereignty today through FIPS 140-3 Level 3 validated protection with confidential computing architecture, offering single-tenancy and customer control of keys while Microsoft handles operational responsibilities. External key management architectures offer maximum control over HSM access and policies but require organizations to manage complex infrastructure and maintain service availability for dependent cloud workloads.

Organizations should evaluate approaches based on compliance requirements, operational capacity, integration needs, and the balance of responsibility that aligns with their sovereignty objectives.

## Next steps

- Classify workloads by required key control strength (platform-managed keys → customer-managed keys → Managed HSM)
- Document rotation cadences and revocation triggers for each key domain.
- Evaluate confidential computing and secure key release feasibility for high-sensitivity workloads.

## See also

- [Key management in Azure](/azure/security/fundamentals/key-management) - comprehensive overview of all Azure key management solutions.
- [How to choose the right key management solution](/azure/security/fundamentals/key-management-choose) - decision guidance based on requirements and scenarios.
- [Azure Key Vault overview](/azure/key-vault/general/overview) - details on Azure Key Vault Standard and Premium tiers.
- [What is Azure Key Vault Managed HSM?](/azure/key-vault/managed-hsm/overview) - Managed HSM architecture and capabilities.
- [What is External Key Management?](public/external-key-management.md) - understanding external key management approaches.
- [Azure Confidential Computing](public/confidential-computing.md) - foundational technology for Managed HSM security.
- [Data controls](data-controls.md) - complementary data sovereignty controls.
- [Operational controls](operational-controls.md) - operational sovereignty considerations.
- [Digital sovereignty](digital-sovereignty.md) - overall sovereignty framework.
- [Technological independence](technological-independence.md) - technology sovereignty principles.