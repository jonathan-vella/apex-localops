---
title: Connected Operations for Azure Local
description: Learn about connected operations for Azure Local, a deployment model that enables periodic connectivity to Azure while keeping workloads and data on‑premises, using Azure-based management, governance, and lifecycle services.
author: ronmiab
ms.topic: overview
ms.date: 05/14/2026
ms.author: robess
ms.service: azure
ms.subservice: sovereign-private-clouds
---

# Connected operations overview

This article provides an overview of connected operations for Azure Local.

Connected operations enable you to run Azure Local with periodic connectivity to Azure while keeping workloads and data on-premises. This deployment model is designed for organizations that want a broad set of Azure Local capabilities on their private cloud, while using Azure-based management and operational services.

By using connected operations, systems rely on periodic connectivity to Azure to deliver services such as monitoring, governance, and lifecycle management, while maintaining local control over infrastructure and data.

Industries such as retail, healthcare, manufacturing, and financial services commonly use connected operations, where centralized visibility and compliance are important, alongside on-premises data residency.

## What does "connected" mean?

Connected operations provide a balance between on-premises control and cloud-based operational efficiency, while allowing for intermittent loss of connectivity.

In a connected Azure Local deployment, the system maintains periodic connectivity to Azure for control plane activities. The system supports intermittent disconnections up to 30 days without impacting running workloads. Azure Local is designed to tolerate short periods of disconnection, such as temporary ISP outages, while workloads continue to run on-premises.

In a connected deployment, you can:

- Run hardware on-premises while keeping workloads and data local.
- Manage Azure Local through the Azure portal as a single control plane for deployment and operations.
- Deploy clusters, add nodes, and scale resources by using Azure portal workflows.
- Initiate and coordinate cluster lifecycle actions from the Azure portal, with Azure services validating and orchestrating changes.
- Apply identity, access control, and governance by using Azure services and the Azure portal.
- Monitor and manage your environment by using Azure services when connectivity is available.
- Drive capacity and scaling through cloud-based, policy-governed controls to ensure consistent configuration across sites.
- Update the platform through Azure using Microsoft-validated platform software and supported Original Equipment Manufacturer (OEM) components.

## Deployment options

Connected operations support Azure Local deployment options that scale from single-node systems to large, clustered environments, from one node to thousands of nodes. You can start small and grow as capacity, performance, or availability requirements increase.

### Hyperconverged deployments

Hyperconverged deployments combine compute, storage, and networking on the same physical hardware to provide a simple, scalable architecture. They’re a good fit for general‑purpose workloads that operationalize simplicity and ease of scaling.

Key characteristics:

- Support single-node and multi-node clusters, scaling up to 16 nodes on a single rack.
- Use local storage on each node, with optional support for storage area network (SAN) integration in supported configurations.
- Support high-speed Ethernet networking, with options to configure converged or dedicated networks for storage, management, and virtual machine (VM) traffic.
- Support adding GPU-enabled nodes for AI, graphics, and compute-intensive workloads.

For more information, see [What are hyperconverged deployments of Azure Local?](/azure/azure-local/overview/hyperconverged-overview)

### Disaggregated deployments

Disaggregated deployments of Azure Local separate compute and storage into dedicated resources. This separation enables flexible scaling and performance optimization across diverse infrastructures. These deployments support configurations ranging from a single node to up to 64 nodes with SAN-based storage.

Disaggregated deployments use a unified Azure control plane to enable consistent cloud operations and accelerate modern workloads across cloud and edge environments.

Key characteristics:

- Scale compute and storage to match workload needs. Grow each independently based on application and data demand.
- Use local storage on compute nodes with integration to SAN systems. Support both simple and high-capacity deployments.
- Optimize performance by isolating storage on dedicated infrastructure. Improve consistency for performance-sensitive workloads.
- Support data-intensive and modern workloads, including AI and analytics, with flexible, high-capacity storage architectures.
- Integrate validated partner hardware and existing storage environments, extending current investments.
- Provide unified management through the Azure control plane, using consistent tools, governance, and automation.

For more information, see [What are disaggregated deployments of Azure Local?](/azure/azure-local/overview/disaggregated-overview)

### Multi-rack deployments

Multi-rack deployments scale Azure Local across multiple racks to support larger environments that require higher capacity, performance, and tenant isolation.

Key characteristics:

- Support larger-scale clusters that span multiple racks within a datacenter, scaling up to 128 nodes each.
- Increase scale and resiliency through rack-aware designs and fault domain isolation.
- Use SAN-based storage, where an external SAN provides storage and enables independent scaling of compute and storage.
- Separate management, storage, and workload traffic by using dedicated or logically isolated networks.
- Support GPU-enabled nodes for AI, graphics, and other accelerated workloads.
- Enable scale-out, rack-aware networking designs, including:
  - Dedicated storage networks for SAN or disaggregated storage configurations.
  - High-speed east-west fabrics optimized for traffic between racks.
  - Dedicated or logically isolated networks for management, storage, and workload traffic.
  
For more information, see [What are multi-rack deployments of Azure Local?](/azure/azure-local/multi-rack/multi-rack-overview)

## Workloads and services

Azure Local deployments support a broad set of Azure Local infrastructure workloads and enable scenarios that benefit from centralized management. The following sections identify some supported services available when Azure Local operates in a connected environment, including management capabilities, workloads, and platform services available with Azure connectivity.

### Management and security

Azure-based management experiences enable you to monitor, secure, govern, and operate Azure Local environments.

The following table highlights some of the management and security services available in connected Azure Local environments:

| Service | Description |
|--|--|
| [Azure Monitor](/azure/azure-monitor/fundamentals/overview) | Collect and analyze metrics to monitor the health, performance, and availability of on-premises resources with integrated alerts and insights. |
| [Entra ID](/entra/fundamentals/what-is-entra) | Secure access to Azure Local by managing identities, authentication, and authorization with centralized identity and access control. |
| [Key Vault](/azure/key-vault/general/basic-concepts) | Securely store and manage secrets, keys, and certificates used by applications and services. |
| [Update Manager](/azure/update-manager/overview) | Coordinate and manage updates for infrastructure and workloads to help keep systems secure, compliant, and up to date. |

### Workloads and applications

Infrastructure and application workloads run on Azure Local, supporting virtual machines, containers, productivity services, and edge scenarios.

The following table provides an overview of some of the workloads and application services supported by Azure Local:

| Service | Description |
|--|--|
| [IoT Operations](/azure/iot-operations/overview-iot-operations) | Collect, process, and manage data from connected devices locally, supporting industrial, edge, and sovereign IoT scenarios. |
| [Kubernetes](/azure/aks/what-is-aks) | Orchestrate and manage containerized workloads using Kubernetes, providing consistent deployment and scaling across environments. |
| [Virtual Desktop](/azure/virtual-desktop/overview) | Provide users with secure access to virtual desktops and applications hosted on local infrastructure. |
| [Virtual Machines](/azure/virtual-machines/overview) | Run Windows and Linux VMs for enterprise applications, shared services, and infrastructure workloads. |

### Data and AI

Data services and AI capabilities enable analytics, search, and AI‑powered applications using local and connected data.

The following table provides an overview of some of the data and AI services available for Azure Local:

| Service | Description |
|--|--|
| [Edge RAG](/azure/azure-arc/edge-rag/overview) | Ground generative AI responses using local and connected enterprise data to deliver relevant, context‑aware outputs. |
| [Foundry Local on Azure Local](../foundry-local/what-is-foundry-local-on-azure-local.md) | Build, deploy, and run AI models and workloads locally using a consistent Azure AI development experience. |
| [Machine Learning](/azure/machine-learning/overview-what-is-azure-machine-learning) | Train, deploy, and manage machine learning models to support predictive and analytical workloads on Azure Local. |
| [SQL Server enabled by Azure Arc](/sql/sql-server/azure-arc/overview) | Store, query, and manage relational data for applications and services running on Azure Local. |

## Related content

- Learn more about Azure Local by exploring the full, linked documentation set: [Azure Local documentation](/azure/azure-local).
- Review the [Azure Local FAQs](/azure/azure-local/faq).
- Explore [Disconnected operations for Azure Local](/azure/azure-local/manage/disconnected-operations-overview).
<!--- **GitHub Enterprise Local:** enable modern DevSecOps and keep code, identity, and operations fully on-premises with GitHub Enterprise Local on Azure Local-->
