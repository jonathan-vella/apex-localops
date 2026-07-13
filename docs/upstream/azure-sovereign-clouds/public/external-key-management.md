---
title: "What is External Key Management?"
description: "Learn about external key management as a sovereignty strategy and how Azure Key Vault Managed HSM supports it, including the new EKM preview feature."
author: lavanyapg
ms.topic: overview
ms.date: 07/07/2026
ms.author: kerabun
ms.reviewer: lsuresh
ms.subservice: sovereign-public-clouds
ai-usage: ai-assisted
ms.collection: 
    - microsoftcloud-sovereignty
    - microsoftcloud-seo-priority
---

# What is External Key Management?

External Key Management (EKM) is an approach where organizations generate, store, and manage encryption keys outside of cloud infrastructure, while using those keys to protect data in cloud services. This approach can address key sovereignty requirements for organizations that need greater control over cryptographic material for data sovereignty and compliance in regulated sectors.

## Azure Key Vault Managed HSM key sovereignty

Azure Key Vault Managed HSM helps you achieve key sovereignty by giving you full control of cryptographic keys through FIPS 140-3 Level 3 validated security, single-tenant isolation, and customer-controlled security domains. This approach delivers strong sovereignty guarantees while maintaining Azure's service-level agreements and eliminating the operational overhead of managing physical HSM infrastructure.

For most organizations, Managed HSM key sovereignty satisfies even stringent regulatory requirements. For more information, see [What is Azure Key Vault Managed HSM?](/azure/key-vault/managed-hsm/overview) and [Capabilities of Sovereign Public Cloud](sovereign-public-cloud-capabilities.md).

## Managed HSM External Key Management (preview)

For organizations with regulatory or contractual requirements that mandate key material physically reside outside Microsoft infrastructure, Azure Key Vault Managed HSM also supports External Key Management as a preview feature. With EKM, the Key Encryption Key lives in a customer-operated HSM outside Azure, and Managed HSM delegates wrap and unwrap operations to it through a customer-run EKM Proxy.

> [!IMPORTANT]
> Managed HSM External Key Management is in **preview**. Preview features are made available to you on the condition that you agree to the [supplemental terms of use](https://azure.microsoft.com/support/legal/preview-supplemental-terms/). Some aspects of this feature might change before general availability.

EKM trades availability, performance, and operational simplicity for physical key control outside Microsoft infrastructure. It's a last-resort option for organizations with a hard legal or contractual mandate - not a general-purpose upgrade to Managed HSM keys.

For full architecture details, operational requirements, and quickstarts, see [What is Managed HSM External Key Management?](/azure/key-vault/managed-hsm/external-key-management-overview).

## See also

- [Key management in Azure](/azure/security/fundamentals/key-management) - compare all Azure key management solutions.
- [How to choose the right key management solution](/azure/security/fundamentals/key-management-choose) - decision guide including EKM.
- [Key management controls](../key-controls.md) - key management security considerations for sovereign cloud.
- [Key recovery management](key-recovery-management.md) - operational responsibilities for Managed HSM.
- [Microsoft Sovereign Cloud overview](../microsoft-sovereign-cloud.md) - broader sovereignty capabilities.