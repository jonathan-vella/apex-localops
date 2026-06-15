---
title: "Known issues for Foundry Local on Azure Local"
description: "Known issues, limitations, and workarounds for Foundry Local on Azure Local during the preview release."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: troubleshooting
ms.author: cwatson
author: cwatson-cat
ms.date: 03/25/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to know about current limitations and workarounds for Foundry Local on Azure Local so that I can plan deployments and avoid known problems.
---

# Known issues for Foundry Local on Azure Local

This article describes known limitations and workarounds for Foundry Local on Azure Local during the preview release.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Known issues and workarounds

### No automatic API key rotation when Inference API is disabled

**Issue:** The inference operator doesn't support automatic rotation of API keys.

**Workaround:** Delete the Kubernetes secret for the deployment. The operator recreates it automatically with new keys.

```bash
kubectl delete secret <deployment-name>-api-keys -n foundry-local-operator
```

### Secrets and certificates aren't synced to other namespaces

**Problem:** API key secrets and TLS certificates aren't automatically distributed to namespaces outside of `foundry-local-operator`.

**Workaround:** Install Trust Manager by using the following required flags:

***Install Extension***
```bash
az k8s-extension create \
    --cluster-name <cluster_name> \
    --name azure-cert-manager \
    --resource-group <resource_group> \
    --cluster-type connectedClusters \
    --extension-type Microsoft.CertManagement \
    --scope cluster \
    --release-train stable \
    --config config.enableGatewayAPI=true \
    --config cert-manager.crds.keep=true \
    --config trust-manager.defaultPackage.enabled=false \
    --config trust-manager.secretTargets.enabled=true \
    --config trust-manager.secretTargets.authorizedSecretsAll=tru
```

***Install Helm Chart***
```bash
helm upgrade --install trust-manager jetstack/trust-manager \
  --namespace cert-manager \
  --set defaultPackage.enabled=false \
  --set secretTargets.enabled=true \
  --set secretTargets.authorizedSecretsAll=true
```

These flags are required for cross-namespace secret distribution to work correctly. Helm is a supported deployment option, and installation instructions are provided during preview access onboarding.

## Related content

- [Troubleshoot Foundry Local on Azure Local](troubleshoot.md)
- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Update the Foundry Local Azure Arc extension in connected environments](how-to-update-arc-extension.md)
- [Configure TLS and authentication for Foundry Local on Azure Local](how-to-configure-tls-authentication.md)
- [What is Foundry Local on Azure Local?](overview.md)
