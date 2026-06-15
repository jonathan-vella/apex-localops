---
title: "Update the Foundry Local Azure Arc Extension in Connected Environments"
description: "Learn how to update the Foundry Local Azure Arc extension in connected environments for minor, patch, and major versions."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 06/05/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to update the Foundry Local Azure Arc extension so that my cluster stays supported with required feature and security updates.
---

# Update the Foundry Local Azure Arc extension in connected environments

Complete the steps in this article when you need to apply minor or patch updates for security and reliability fixes, or when you need to move to a required major version of the Foundry Local Azure Arc extension in connected environments.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Before you begin, make sure the following prerequisites are met.

- A Kubernetes cluster connected to Azure Arc.
- Azure CLI configured and signed in.
- Foundry Local already deployed as an Azure Arc extension. For first-time deployment steps, see [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md).

## Update the extension

Use the following steps to check your current configuration, apply the required update path, and validate extension health.

1. Check the current extension state, version, and auto-upgrade settings.

   Replace all placeholder values in angle brackets (for example, `<resource_group_of_the_arc_cluster>`) before you run the command.

   ```bash
   az k8s-extension show \
     --resource-group <resource_group_of_the_arc_cluster> \
     --cluster-name <arc_cluster_name> \
     --name "inference-operator" \
     --cluster-type connectedClusters \
     --query "{name:name,state:provisioningState,version:version,autoUpgrade:autoUpgradeMinorVersion,train:releaseTrain}" \
     -o table
   ```

1. Choose the update option that matches your scenario.

   **Option 1: `--auto-upgrade-minor-version` is `true`**

   If automatic minor-version updates are enabled, you don't run a manual update command for minor and patch releases. Arc applies them automatically in the configured release train.

   Use the Step 1 output to confirm `autoUpgrade` is `true`. If you want to check again, run:

   Replace all placeholder values in angle brackets before you run the command.

   ```bash
   az k8s-extension show \
     --resource-group <resource_group_of_the_arc_cluster> \
     --cluster-name <arc_cluster_name> \
     --name "inference-operator" \
     --cluster-type connectedClusters \
     --query "{autoUpgrade:autoUpgradeMinorVersion,train:releaseTrain}" \
     -o table
   ```

   **Option 2: `--auto-upgrade-minor-version` is `false` (manual minor or patch update)**

   If automatic minor-version updates are disabled, the extension stays on its current version until you manually update.

   Replace all placeholder values in angle brackets before you run the command.

   ```bash
   az k8s-extension update \
     --resource-group <resource_group_of_the_arc_cluster> \
     --cluster-name <arc_cluster_name> \
     --name "inference-operator" \
     --cluster-type connectedClusters \
     --auto-upgrade-minor-version false \
     --version <target_minor_or_patch_version>
   ```

   **Option 3: Major version update**

   Major version updates are never applied automatically. To move to a major version, set `--auto-upgrade-minor-version false` and pin the target major version explicitly.

   Replace all placeholder values in angle brackets before you run the command.

   ```bash
   az k8s-extension update \
     --resource-group <resource_group_of_the_arc_cluster> \
     --cluster-name <arc_cluster_name> \
     --name "inference-operator" \
     --cluster-type connectedClusters \
     --auto-upgrade-minor-version false \
     --version <target_major_version>
   ```

1. Verify extension health after update.

   Replace all placeholder values in angle brackets before you run the command.

   ```bash
   az k8s-extension show \
     --resource-group <resource_group_of_the_arc_cluster> \
     --cluster-name <arc_cluster_name> \
     --name "inference-operator" \
     --cluster-type connectedClusters \
     --query "{name:name,state:provisioningState,version:version}" \
     -o table

   kubectl get pods -n foundry-local-operator
   ```

   Expected result:

   - Extension state is `Succeeded`.
   - Extension version shows the target version.
   - Pods in `foundry-local-operator` are healthy (`Running` or `Completed` where expected).

1. Optional. Re-enable automatic minor upgrades after a pinned rollout.

   Replace all placeholder values in angle brackets before you run the command.

   ```bash
   az k8s-extension update \
     --resource-group <resource_group_of_the_arc_cluster> \
     --cluster-name <arc_cluster_name> \
     --name "inference-operator" \
     --cluster-type connectedClusters \
     --auto-upgrade-minor-version true
   ```

## Related content

- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Troubleshoot your Foundry Local deployment](deploy-foundry-local-arc-extension.md#troubleshoot-your-deployment)
