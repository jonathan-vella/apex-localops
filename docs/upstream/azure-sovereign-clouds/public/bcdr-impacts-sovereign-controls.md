---
title: "Business continuity and disaster recovery (BCDR) for sovereign workloads"
description: "Learn BCDR impacts for workloads in a sovereign public cloud."
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

# Business continuity and disaster recovery (BCDR)

Business continuity and disaster recovery (BCDR) in Azure refers to the strategic approach and set of capabilities designed to ensure that applications, services, and data remain available and recoverable during unexpected disruptions. These capabilities apply even when sovereign controls are in place. A comprehensive BCDR strategy encompasses both *resiliency* and *recoverability*. Resiliency is the ability to withstand disruptions and continue operating. Recoverability is the ability to restore normal operations after a disruption occurs.

By using Azure's robust infrastructure, designing geo-redundant architectures, and using automated backup and restore solutions, organizations can minimize downtime, maintain compliance, and safeguard critical operations during outages or cyber threats.

As sovereign policies are applied to workloads in Azure, you can distribute the components of the workload across availability zones and regions. Azure Availability Zones are a critical component in architecting resilient cloud solutions. Each zone is a physically separate location within an Azure region, engineered to provide isolation from failures in other zones.

By distributing resources across multiple Availability Zones, you can achieve higher availability and robust fault tolerance. This design ensures that if an event impacts one zone, applications and data remain accessible and operational in the other zones. Availability Zones use synchronous replication for their zone-resilient workloads (where possible) and thus can provide near-zero RTO and zero RPO for most zone-redundant workloads.

While Availability Zones protect against the outage of a single (or at most two) zones, a complete region failure can be mitigated by deploying workloads in multiple regions. Because regions are farther apart, synchronous replication is difficult, so you must consider asynchronous architectures.

## Level 1 (data residency) impacts

When you deploy services within a single region, level 1 policies prohibit services that aren't available in that region or don't store data solely in the chosen region. When you consider BCDR across regions, you must expand level 1 policies to include other regions, and ensure that policies include all common services available in both regions.

When you consider zone resiliency within a single region, level 1 policies might limit services and configurations to those regions that support and enforce zone resiliency, such as disallowing GRS storage.

## Level 2 (encryption at rest) impacts

Use Azure Key Vault Premium or Managed HSM for storing the key-encryption-keys used in level 2 compliant sovereign workloads and also for confidential disk encryption in combination with confidential computing. Managed HSM keys aren't used for memory encryption keys in AMD SEV-SNP, Intel SGX, or Intel TDX technologies. As such, it's an important foundational building block that you must consider in any BCDR scenario.

Managed HSM uses three instances upon deployment, and where possible these instances are spread out over two or three zones. To ensure cross-region BCDR, cross-region instances (multi-region replication) are required. The standard architecture for Managed HSM uses a traffic manager load balancer for both regions, ensuring that all instances are available under a single (master) URL.

Managed HSM uses a multi-master replication architecture, utilizing an encrypted (cross-region replicating) Cosmos DB, essentially ensuring that all individual instances across the regions can fully serve any workload. This means that even during a zonal or cross-region failover, the Managed HSM service can fully support any workload, including generating, wrapping/unwrapping, and configuring settings.

For auditing and monitoring, two options are available and both can be used simultaneously.  Azure Monitor can ingest the audit logs for both Managed HSM instances. However, it's also possible to directly log to an immutable storage account with GRS replication. This option ensures that when a full region goes down, the second region instance can continue to write raw audit logs to the GRS storage copy in its own region.

The Azure Key Vault Premium built-in failover mechanism is limited to a paired region or within availability zones. It also has a different cross-region failover (where supported) architecture, where the failover instance runs only in read mode. While the read mode is sufficient for most workloads, workloads that use secure key release architectures, including confidential disk encryption, are affected in cross-region failovers.

## Level 3 (encryption in use) impacts

When you consider confidential computing services for BCDR scenarios, it's important to understand the components involved. While confidential computing itself uses CPU-based derivative keys and doesn't rely on external key storage, you can host any confidential VM on any CPU that supports the same encryption technologies (SEV-SNP or Intel TDX). However, you must consider other components surrounding the confidential virtual machine in any resiliency design.

### Attestation services

Attestation services verify that confidential VMs and related services operate within trusted execution environments. Although not required for all workloads, the validation is mandatory for secure key release, confidential disk encryption, and similar controls. It's vital to ensure that application architectures account for multiple attestation services.

In many Azure regions, an attestation service exists and is available through public URLs. While the URLs all provide the same information, it's important to ensure that key release policies (for keys in Managed HSM or Key Vault Premium) include all the service URLs in the regions where you anticipate restoring a service.

### vTPM

Generation 2 virtual machines and confidential VMs include a virtual Trusted Platform Module (vTPM). It securely stores sensitive material, such as encryption and bootloader keys, to help protect VM integrity and confidentiality. By isolating and encrypting these secrets, the vTPM keeps data secure when VMs are backed up, restored, or moved. It enables features like BitLocker while reducing unauthorized reuse risk.

In Azure, the vTPM isn't a separate device. Its state (encrypted) is stored with the VM’s OS disk and is tied to the VM configuration and environment. VM backups (Azure Backup) capture required components. If someone manually snapshots the disk and creates a new VM, the vTPM identity is regenerated. In edge cases, this action can result in loss of keys (including BitLocker keys), making data drives inaccessible on the rebuilt VM.

Each VM gets a unique TPM identity. Endorsement‑hierarchy keys (AK/EK) are refreshed per VM/vTPM instance (distinct Azure-assigned vmid) by regenerating the EPS (Endorsement Primary Seed). While the endorsement hierarchy (identity and attestation keys) is reset, the storage hierarchy (for example, SRK and nvindex) is retained to preserve features like BitLocker across backup and restore. UEFI variables and related state in a confidential VM are encrypted and integrity‑protected by two keys - one tenant‑owned and one Azure‑owned - both required to reopen the state. Recovery succeeds only when a new VM (same tenant) is fully rebuilt from an Azure-created snapshot/backup preserving all VM components (OS and data disks).

### Back up and site replication

One of the primary methods to implement recoverability and resiliency for single-instance VMs is to use Azure Backup and Azure Site Recovery services. It's important to understand the limitations of these services in a BCDR scenario, especially for confidential computing workloads. For more information about these limitations, see [About Azure confidential VMs](/azure/confidential-computing/confidential-vm-overview#feature-support).

Azure Managed Disks are also available as ZRS disks, where their data is replicated synchronously throughout the three zones of a region, ensuring an RPO of 0. However, while the RPO is 0, restoring a VM based on these disks is more complex. You must build a new VM from a snapshot of the original ZRS disks. As indicated earlier, this change means the loss of the vTPM contents (which could include drive encryption unlock keys). As the keys are tied to the full VM state, you can only recover without impact by cloning the entire VM. Otherwise, the storage hierarchy in the vTPM isn't opened. This means that you need access to the original VM configuration to be cloned. You must also take into account the impact of the original VM coming back online. While RPO might be 0, the RTO is high due to the manual or scripted processes.

Avoid single-instance VMs where possible. The recovery procedure is either based on Azure Backups with high RPOs or on custom scripts in combination with ZRS disks that require secrets and BitLocker/dm-crypt recovery keys to be available when restoring (partial) VMs.

### Disk encryption

When you use customer-managed keys, Azure offers several disk encryption methods for virtual machines. Some of these methods, like storage encryption and host encryption, operate outside the VM scope and use external wrap and unwrap keys in the key management service. In this case, key availability is sufficient. Azure Key Vault automatically replicates its contents through the three zones. If it's a paired region, it also replicates a copy of Key Vault information to the paired region, which functions in read-only mode upon failover. These server-side encryption methods are highly resilient and offer multiple options for recovery.

Other disk encryption options use keys or unlock materials generated and processed inside the VM operating system. For example, Azure Disk Encryption stores the DMCrypt/BitLocker unlock key in Azure Key Vault Premium. The same protections for Azure Key Vault apply. You can create new VMs based on ZRS snapshots or backups, but cross-region deployments aren't supported.

Another option is to encrypt the disks from within the VM itself. In this case, the BitLocker keys are solely stored on the vTPM for automatic unlock. The BitLocker enabling wizard prompts you to secure the BitLocker recovery keys or is mandated by policy. Failure to save these keys might result in data loss if the original vTPM can't be restored. If you build a new VM with a new operating system disk, the automount fails for the data disks on the new VM and recovery keys must be used.

When you work with disk encryption mechanisms, ensure that you safely store the recovery keys in remote locations, such as printed files or saved files in a remote storage location. When using Azure Disk Encryption or encryption sets, recovery of a VM is possible in the same region (in another zone), but cross-region recovery requires more effort and might require third-party replication services.

### Confidential disk encryption

In confidential disk encryption, the disk itself is unlocked by using external keys stored in Azure Key Vault or Managed HSM. For DR scenarios, the original keys and the correct key release policies must be available. Each key used for confidential disk encryption has a release policy attached to it. This policy usually indicates the required confidential computing technology to be used (SEV-SNP, TDX, or SGX) and indicators of trusted execution environments proof. They often also include the URLs of the approved attestation services. For BCDR, it's vital that multiple URLs are used to ensure the key can be released upon failover. Trying to add a new policy to a key automatically generates a new version of the key and doesn't append the policy to an existing key.

Because the keys for confidential disk encryption are stored as keys (Azure Disk Encryption uses the secrets objects in Key Vault), you can use cross-region replication when Managed HSM is used. This means that confidential VMs can be restored in any region that has a copy of these keys available, and if the Managed HSM is part of the same Managed HSM geo cluster. The attestation URL in the release policy for the used key must cover multiple service endpoints.

## Conclusion

BCDR in Azure relies on zone and region redundancy, encryption across three control levels, and proper key/attestation design. The most critical success factor is ensuring that encryption keys and recovery processes are available across zones and regions, with careful consideration for confidential workloads where vTPM and attestation add complexity.

## See also

- [Azure Backup Overview](/azure/backup/backup-overview)
- [Azure Managed HSM Multi-Region Replication](/azure/key-vault/managed-hsm/multi-region-replication)
- [Azure Key Vault Reliability](/azure/reliability/reliability-key-vault)
- [Azure Attestation Services](/azure/attestation/overview)
- [Azure Disk Encryption Options](/azure/virtual-machines/disk-encryption-overview)