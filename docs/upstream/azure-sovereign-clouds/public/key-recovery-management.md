---
title: "Key Recovery Management with Managed HSM"
description: "Learn the operational impacts when using Managed HSM or External Key Stores"
author: lavanyapg
ms.topic: overview
ms.date: 11/14/2025
ms.author: rozome
ms.reviewer: lsuresh
ms.subservice: sovereign-public-clouds
ms.collection: 
  - microsoftcloud-sovereignty
  - microsoftcloud-seo-priority
---

# Key recovery management with Managed HSM

Azure Managed HSM is a cornerstone of **sovereign controls** within the Microsoft Sovereign Cloud architecture. It meets stringent regulatory and compliance requirements by ensuring that cryptographic operations and key material remain fully under your control. This sovereignty model provides unmatched assurance for data residency and compliance without impacting service SLAs, but it also shifts significant operational responsibilities to you.

For more information about key management controls and sovereignty considerations, see [Key management controls](../key-controls.md).

Unlike Azure Key Vault (standard and premium), where Microsoft is responsible for key durability and service continuity, Managed HSM requires you to manage the **Security Domain (recovery)**, **RSA key pairs**, and key **backups**. This operational overhead includes recovery key generation, offline storage, and disaster recovery planning - tasks that are critical to maintaining accessibility to your encryption keys for your sovereign workloads. For more information, see [Security domain in Managed HSM overview](/azure/key-vault/managed-hsm/security-domain).

> [!NOTE]
> The Security Domain is used to restore the Managed HSM service and to import HSM backups. It doesn't include backups of the actual keys inside your Managed HSM service. You can make individual backups of keys, or all contents separately. For more information, see [Full backup and restore and selective key restore](/azure/key-vault/managed-hsm/backup-restore).

## Customer responsibilities

When you adopt Azure Managed HSM for sovereign workloads, you need to assume several operational duties. The following tasks ensure that your workloads are sovereign and remain recoverable in an emergency:

### Generate and manage RSA key pairs securely

At least three RSA key pairs are required during initialization. These keys encrypt the Security Domain using Shamir’s Secret Sharing algorithm, allowing for a quorum of keys to be used during recovery. You can create the recovery keys offline and use them for service activation. For guidance on generating and managing recovery keys, see [Create and manage recovery keys for Managed HSM](/azure/key-vault/managed-hsm/security-domain#generate-recovery-keys).

### Store RSA key pairs and Security Domain offline and redundantly

You need to store the Security Domain and Recovery Keys (private and public) securely and redundantly, but **never in a location that depends on the Managed HSM service itself**. If they're inaccessible during a recovery scenario, the HSM and all associated keys can't be restored.

### Take regular, secure HSM backups
   
The Security Domain doesn't include any key material from the HSM. You're responsible for creating Managed HSM backups. While you can store these backups in an Azure Storage Account, **ensure that the storage account doesn't depend on an encryption key stored in Managed HSM**. During a recovery, those storage accounts aren't available and you risk losing access to your key backups. Either copy HSM backups to on-premises, ensure the backup storage account uses Platform Managed Keys, Key Vault (premium) keys for CMK encryption, or ensure that at least the storage account encryption key is available in another location.

### Plan for recovery scenarios

   To restore an HSM, you need:

   - the Security Domain file,
   - the (quorum of) recovery keys,
   - and the latest (full) HSM backup.

Make sure you have a detailed plan for where the Security Domain and its recovery keys are stored and how to retrieve them. For more information, see the [Disaster Recovery Guide](/azure/key-vault/managed-hsm/disaster-recovery-guide).


## Best practices for key recovery

- **Enable soft-delete and purge protection** for Managed HSM resources to prevent accidental or malicious deletion.  
- **Perform regular backups** of your HSM and store them securely.  
- **Document recovery procedures** and test them periodically to ensure readiness.

For more information, see [Business continuity and disaster recovery (BCDR) for sovereign workloads](bcdr-impacts-sovereign-controls.md).

## Consequences of neglect

If you lose the Security Domain or quorum keys:

- Microsoft can't recover your HSM for you.  
- All cryptographic material becomes unrecoverable.
- All data encrypted by that cryptographic material can be permanently lost.
- Business continuity and compliance obligations can be severely impacted.

## Alternative option - Azure Key Vault Premium

If you prefer **Microsoft-managed responsibility for service and key availability**, consider **Azure Key Vault Premium**. Unlike Managed HSM, where you own the Security Domain and recovery process, Key Vault Premium ensures Microsoft handles service continuity and key durability. This option reduces operational overhead and risk.

For more information about choosing the right key management solution, see [Key management controls](../key-controls.md) and [External key management](external-key-management.md).

For more information, see [Overview of Azure Key Vault Premium](/azure/key-vault/general/overview).

## Summary

Azure Managed HSM offers unmatched security and sovereignty, but with that control comes responsibility. **Protect your Security Domain and associated keys as if your entire sovereign workloads and data depends on them—because it does.**

## Related content

- [Key management controls](../key-controls.md) - Key management considerations for sovereign cloud
- [Business continuity and disaster recovery (BCDR) for sovereign workloads](bcdr-impacts-sovereign-controls.md) - BCDR impacts with sovereign controls
- [External key management](external-key-management.md) - External key management approaches
- [Implement workloads in the Sovereign Public Cloud](overview-implement-workloads.md) - Overview of implementing sovereign workloads
- [Security domain in Managed HSM](/azure/key-vault/managed-hsm/security-domain) - Detailed information about Security Domain
- [Disaster Recovery Guide for Managed HSM](/azure/key-vault/managed-hsm/disaster-recovery-guide) - Step-by-step recovery procedures
