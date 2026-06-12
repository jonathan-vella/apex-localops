---
title: What is Sovereign Private Cloud?
description: Learn about Sovereign Private Cloud and how it runs on Azure Local. Understand other features and how they support sovereignty on Azure Local.
author: ronmiab
ms.author: robess
ms.reviewer: robess
ms.date: 04/15/2026
ms.topic: overview
ms.subservice: sovereign-private-clouds
---

# What is Sovereign Private Cloud?

Sovereign Private Cloud is a portfolio of Microsoft solutions designed to help organizations run cloud services in **sovereign, regulated, and disconnected environments**. Sovereign Private Cloud provides a consistent Microsoft cloud experience while allowing customers to retain full control over infrastructure, data residency, and operations.

Microsoft Sovereign Private Cloud provides a consistent, private cloud infrastructure that supports multiple workload types on the same foundation. You can run Microsoft AI services, productivity workloads, and your own applications side by side, using the execution model that fits each workload. All workloads are built on the same secure, Sovereign Private Cloud infrastructure, enabling shared governance, identity, and operations while giving you flexibility to modernize at your own pace.

:::image type="content" source="media/sovereign-private-cloud/sovereign-private-cloud.png" alt-text="Sovereign Private Cloud overview diagram showing supported components." lightbox="media/sovereign-private-cloud/sovereign-private-cloud.png":::

## Private cloud infrastructure: Azure Local

Azure Local is the foundation of the Sovereign Private Cloud. Azure Local provides the core infrastructure layer - compute, storage, networking, and lifecycle management - on which sovereign workloads run. All Sovereign Private Cloud solutions are built on and depend on Azure Local to deliver Azure-consistent services in customer-managed environments. Azure Local supports running workloads as virtual machines (VMs) or on Azure Kubernetes Service (AKS) Arc-enabled clusters.

For more information, see [Azure Local for Microsoft Sovereign Private Cloud](/azure/azure-local/overview).

## AI suite: Foundry Local on Azure Local

Foundry Local on Azure Local enables you to bring AI closer to your data by deploying and running AI models entirely within your Azure Local environment. Foundry Local supports scenarios where you need AI sovereignty, low-latency inference, and control over where your data is processed. It integrates with Arc-enabled Kubernetes so you can operationalize AI using familiar Kubernetes-native workflows while keeping AI workloads on-premises.

Foundry Local on Azure Local also supports a **Model-as-a-Service (MaaS)** approach, enabling you to deploy, manage, and consume AI models locally without building and operating the full model lifecycle yourself.

For more information, see [Foundry Local for Microsoft Sovereign Private Cloud](../foundry-local/what-is-foundry-local-on-azure-local.md).

## Productivity suite: Microsoft 365 Local

Microsoft 365 Local enables you to run Exchange Server, SharePoint Server, and Skype for Business Server on Azure Local infrastructure that you own and manage. You gain enhanced control over data residency, access, and compliance, helping you meet your sovereignty requirements.

If you need productivity tools in a private cloud environment, Microsoft 365 Local provides an Azure-consistent management experience with a unified control plane. It simplifies deployment and streamlines updates for easy infrastructure management, supporting both hybrid and fully disconnected deployments.

For more information, see [Microsoft 365 Local on Azure Local infrastructure](../m365-local/microsoft-365-local-overview.md).

## Next step

[What is Azure Local?](../azure-local/azure-local-overview.md)