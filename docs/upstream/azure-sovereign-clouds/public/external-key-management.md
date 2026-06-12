---
title: "External Key Management overview"
description: "Learn about external key management approaches for encryption key control in sovereign cloud scenarios."
author: lavanyapg
ms.topic: overview
ms.date: 10/22/2025
ms.author: kerabun
ms.reviewer: lsuresh
ms.subservice: sovereign-public-clouds
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---

# What is External Key Management?

External Key Management is an approach where organizations generate, store, and manage encryption keys outside of cloud infrastructure, while using those keys to protect data in cloud services. This approach can address key sovereignty requirements for organizations that need greater control over cryptographic material for data sovereignty and compliance in regulated sectors.

Azure Key Vault Managed HSM provides key sovereignty by giving customers full control of cryptographic keys through FIPS 140-3 Level 3 validated security, single-tenant isolation, and customer-controlled security domains. This approach delivers strong sovereignty guarantees while maintaining Azure's service-level agreements and eliminating the operational overhead of managing physical HSM infrastructure. For more information about Sovereign Public Cloud capabilities, see [Capabilities of Sovereign Public Cloud](sovereign-public-cloud-capabilities.md).

For information about Azure's key management solutions and how they address sovereignty requirements, see:

- [Key management in Azure](/azure/security/fundamentals/key-management)
- [How to choose the right key management solution](/azure/security/fundamentals/key-management-choose)
- [What is Azure Key Vault Managed HSM?](/azure/key-vault/managed-hsm/overview)

## See also

- [Azure Key Vault](/azure/key-vault/general/about-keys-secrets-certificates) - Azure Key Vault documentation
- [Key management controls](../key-controls.md) - key management considerations for sovereign cloud
- [Microsoft Sovereign Cloud overview](../microsoft-sovereign-cloud.md) - broader sovereignty capabilities
- [Customer-managed keys and encryption options in Azure](/azure/security/fundamentals/encryption-overview) - encryption fundamentals