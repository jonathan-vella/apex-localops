---
title: "Foundry Local on Azure Local in Disconnected Environments Overview"
description: "Deploy and run AI models on Azure Local with Arc-enabled Kubernetes for secure inference in disconnected environments."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: concept-article
ms.author: cwatson
author: cwatson-cat
ms.date: 06/01/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to understand disconnected operations in Foundry Local on Azure Local so that I can run and manage AI inference workloads disconnected on-premises.
---

# Foundry Local on Azure Local in disconnected environments overview

You can deploy Foundry Local on Azure Local in disconnected environments by using a deployment model that largely matches connected scenarios. However, several key differences exist when internet connectivity isn't available.

This article explains how disconnected deployments of Foundry Local on Azure Local differ from connected deployments, so you can plan secure, offline model operations.

## What changes in disconnected deployments

In disconnected environments, extension availability, certificate management, model artifact sourcing, telemetry behavior, identity, and access flows differ from connected deployments.

* **Extension availability**: Before you can install the Foundry Local Azure Arc extension, you must download and import the Foundry Local expansion pack into the disconnected environment.

* **Model catalog source**: Foundry Local pulls model artifacts from the local `edgeartifacts` container registry. Model expansion packs populate this registry.

* **Certificate management**: The `azure-cert-manager` extension isn't available in disconnected environments. Instead, you must install:
  
  `cert-manager`
  `trust-manager`
  
  These Helm charts and container images are included in the Foundry Local expansion pack.
  
* **Telemetry**: Telemetry isn't transmitted to Microsoft. To collect diagnostics for support, use the `az k8s-extension troubleshoot` command.

* **Authentication**: Authentication doesn't use public Microsoft Entra ID endpoints. Instead, Foundry Local integrates with the Active Directory infrastructure configured in the disconnected Azure Local environment.

* **Authorization**: Authorization uses standard Azure RBAC roles on the Foundry extension resource:

   * `Reader` is for read-only operations, such as listing and getting model catalog entries.
   * `Contributor` is required for control plane write operations (for example `POST`, `PUT`, `PATCH`, `DELETE` for models and deployments) and for data plane inference operations such as `predict` and `chat/completions`.

   This authorization model differs from connected deployments, which typically use roles such as Cognitive Services OpenAI User to grant access to inference endpoints.

## Next step

> [!div class="nextstepaction"]
> [Prepare to deploy Foundry Local on Azure Local in disconnected environments](how-to-prepare.md)

## Related content

* [Deploy Foundry Local on Azure Local in a disconnected environment](deploy-platform.md)
* [Deploy your first model in a disconnected environment](how-to-deploy-first-model.md)
* [Configure authentication and authorization for Foundry Local on Azure Local in disconnected environments](how-to-authenticate.md)
* [Troubleshoot Foundry Local on Azure Local in disconnected environments](how-to-troubleshoot.md)
