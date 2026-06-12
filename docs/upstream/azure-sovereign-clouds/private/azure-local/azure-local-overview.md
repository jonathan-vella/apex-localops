---
title: Azure Local Overview and Key Benefits
description: Learn how Azure Local accelerates cloud and AI innovation by delivering applications, workloads, and services from cloud to edge.
author: sipastak
ms.topic: overview
ms.date: 04/15/2026
ms.author: sipastak
ms.service: azure
ms.subservice: sovereign-private-clouds
---

# What is Azure Local?

Azure Local is a distributed infrastructure solution that you can use to run Azure services and workloads in your own environment.

Azure Local runs on customer-managed, on-premises infrastructure. It uses Microsoft software to deliver a consistent Azure experience across edge, datacenter, and sovereign environments. Azure Local supports both connected and disconnected operations to meet regulatory, operational, and connectivity requirements.

## Connectivity and deployment flexibility

Azure Local supports multiple connectivity models and deployment options, so you can use the same Azure-based platform across different environments.

### Connectivity models

Azure Local can run in **connected** environments. In this model, systems maintain periodic connectivity to Azure for management, updates, and integration with Azure services. For connected deployments, at a minimum, Azure Local must sync successfully with Azure once per 30 consecutive days.

Azure Local can also run in **disconnected** environments. In this model, systems operate without a connection to the Azure public cloud. You can build, deploy, and manage virtual machines (VMs) and containerized applications by using select Azure Arc-enabled services from a local control plane. This approach is useful for sovereign, regulated, or isolated scenarios where workloads must remain fully local.

:::image type="content" source="media/azure-local-overview/connected-disconnected-environments.png" alt-text="Diagram showing Azure Local connected and disconnected environments." border="true" lightbox="media/azure-local-overview/connected-disconnected-environments.png":::

### Deployment sizes

Azure Local supports multiple deployment sizes to meet different scale and operational needs. You can deploy Azure Local as a single-node system for isolated sites, development and test environments, or lightweight edge locations. Small-cluster deployments are commonly used for branch offices, factories, or regional sites that require local resiliency.

For larger environments, Azure Local supports large, multi-node clusters and multi-rack deployments. These configurations are typically used for centralized datacenters, shared platforms, or sovereign environments that need higher capacity and consistent operations across multiple racks.

:::image type="content" source="media/azure-local-overview/scale-points.png" alt-text="Diagram showing composable scale points from single nodes up to multiple racks clusters." border="true" lightbox="media/azure-local-overview/scale-points.png":::

## Run specialized workloads on Azure Local

Azure Local provides a platform for running both traditional and cloud-native workloads. It supports Azure-consistent tools and services, so you can modernize applications while meeting local operational and compliance requirements. Some of the most popular services include, but aren't limited to:

- Run **virtual machines** (VMs) for existing and modernized applications.

- Run **Azure Kubernetes Service** (AKS) workloads for containerized applications.

- Use **Azure Monitor** to monitor the health and performance of infrastructure and workloads.

- Use **External SAN** for existing external SAN storage.

- Use **Azure IoT Operations** to run and manage IoT workloads at the edge.

- Use **Azure Site Recovery** to replicate and recover workloads for business continuity.

- Use **AI Custom Vision** to train and run custom image and recognition models.

- Use **AI Video Indexer** to analyze and extract insights from video content.

- Bring your own workloads using familiar Azure APIs and tools.

- Run selected Microsoft and Azure-aligned workloads, including productivity and AI scenarios that benefit from local execution.

## Next steps

To learn more about Azure Local, see the following article:

[Azure Local Scalability and Deployments](/azure/azure-local/scalability-deployments)