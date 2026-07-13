---
title: "Configure TLS for Foundry Local on Azure Local"
description: "Configure TLS encryption to secure communication between model inference endpoints on Foundry Local on Azure Local."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: how-to
ms.author: cwatson
author: cwatson-cat
ms.date: 05/12/2026
ai-usage: ai-assisted
customer intent: As a platform engineer, I want to configure TLS encryption for Foundry Local on Azure Local so that I can secure AI inference endpoints in my environment.
---

# Configure TLS for Foundry Local

Foundry Local on Azure Local encrypts all internal service communication by using TLS. Each model service uses self-signed certificates that the cluster manages. This article explains how the TLS setup works and how to configure secure connections inside the cluster, across namespaces, and through the gateway API for external access.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Automated certificate management requires cert-manager and trust-manager installed on your cluster:

- **cert-manager** issues a self-signed root CA and per-service certificates.
- **trust-manager** distributes the root CA certificate as a trust bundle to all namespaces so other pods can trust the internal certificates.

How you install these components depends on your deployment method:

- **Arc extension (recommended):** Install cert-manager for Arc-enabled Kubernetes (CME) by using `az k8s-extension create` with the `Microsoft.CertManagement` extension type. CME installs both cert-manager and trust-manager as a managed Arc extension. For installation steps, see [Install cert-manager and trust-manager](deploy-foundry-local-arc-extension.md#step-2-install-cert-manager-and-trust-manager).
- **Helm-based deployment:** The Foundry Local Helm chart doesn't automatically install cert-manager and trust-manager. Manually install the open-source [cert-manager](https://cert-manager.io/) and [trust-manager](https://cert-manager.io/docs/trust/trust-manager/) components before you deploy Foundry Local on Azure Local. Helm installation instructions are provided during preview access onboarding.

> [!IMPORTANT]
> For Arc-enabled Kubernetes clusters, use cert-manager for Arc-enabled Kubernetes (CME) as the supported installation path. Generic open-source cert-manager is only required when you deploy Foundry Local by using Helm without the Arc extension.

## How internal TLS works

All traffic between Foundry Local components is encrypted by using TLS. Each service pod runs an NGINX sidecar proxy that:

- Terminates TLS on port 443.
- Forwards requests to the main container over HTTP on localhost (typically port 8001 or 5000).

The main application only listens on localhost, so all external communication must go through the sidecar.

### Root CA and certificate issuance

On first deployment, cert-manager creates a self-signed root Certificate Authority in the Foundry Local namespace and stores it in a Kubernetes secret named `root-ca-secret`. Using this root CA, cert-manager issues TLS certificates for Foundry services through a ClusterIssuer:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: foundry-local-ca-issuer
spec:
  ca:
    secretName: root-ca-secret
    namespace: foundry-local
```

By default, Foundry uses a wildcard certificate (for example, `*.foundry-local.svc.cluster.local`) that covers multiple internal services:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: inference-service-tls
  namespace: foundry-local
spec:
  secretName: inference-service-tls-secret
  commonName: inference-service.foundry-local.svc.cluster.local
  dnsNames:
    - inference-service.foundry-local.svc.cluster.local
    - "*.foundry-local.svc.cluster.local"
  issuerRef:
    name: foundry-local-ca-issuer
    kind: ClusterIssuer
```

cert-manager automatically rotates service certificates before they expire - for example, renewing 30 days before a 90-day expiry. The rotation is seamless: Kubernetes updates the secret and NGINX picks up the new certificate without downtime.

All Foundry sidecars present certificates issued by the internal CA. Because the CA certificate is distributed cluster-wide, every service trusts calls from other services. By default, sidecars use one-way TLS and don't require client certificates for internal calls.

## Configure cross-namespace access

If your application runs in a different Kubernetes namespace and needs to call Foundry inference services, you can do so over TLS using internal DNS names.

trust-manager publishes the root CA to a ConfigMap across all namespaces by default. Create a Bundle resource to distribute it:

```yaml
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: foundry-local-ca-bundle
spec:
  sources:
    - secret:
        name: root-ca-secret
        key: ca.crt
  target:
    configMap:
      key: ca-bundle.crt
    namespaceSelector: {}
```

This creation adds a `foundry-local-ca-bundle` ConfigMap in every namespace containing the root CA certificate. Your application can mount this ConfigMap as a file or import it into its trust store.

To call a Foundry service from another namespace, use its internal DNS name, for example `https://inference-service.foundry-local.svc.cluster.local`. Configure your HTTP client to trust the CA by appending `ca-bundle.crt` to your system trust store or setting it explicitly on the client.

When your application makes an HTTPS request, the Foundry service's NGINX sidecar presents a certificate signed by the internal CA. Because your client trusts that CA through the bundle, the TLS handshake succeeds. API key authentication for inference requests is covered in [Configure authentication for Foundry Local enabled by Azure Arc](how-to-configure-authentication.md).

## Configure external access through gateway API

Foundry Local no longer uses a Kubernetes ingress controller for external inference traffic. External access routes through the Kubernetes Gateway API. The inference operator creates `HTTPRoute` resources for model endpoints and attaches them to the internal gateway by default. When you set `spec.endpoint.exposure: external` on a model deployment, the operator also creates an external gateway backed by a load balancer and attaches the route to that gateway.

To expose a model endpoint externally, configure the ModelDeployment endpoint exposure:

```yaml
apiVersion: foundrylocal.azure.com/v1
kind: ModelDeployment
metadata:
  name: phi-3-mini
  namespace: foundry-local-operator
spec:
  model:
    catalog:
      name: phi-3-mini
  workloadType: generative
  runtime: vllm
  compute: gpu
  replicas: 1
  endpoint:
    exposure: external
    path: /phi-3-mini
```

When you enable external exposure, the external gateway terminates TLS. By default, if cluster TLS is enabled and you don't configure a customer certificate, the operator auto-generates a certificate signed by the internal cluster CA. Off-cluster clients must trust that CA to connect successfully. For production external access, provide a customer-managed TLS secret for the external gateway by setting `operatorConfig.networking.externalGateway.tls.secretName` during extension installation or Helm configuration. The secret must be a Kubernetes TLS secret in the external gateway namespace.

The gateway forwards traffic to the model service over HTTPS. The operator creates a `BackendTLSPolicy` so the gateway validates the backend service certificate against the Foundry Local CA bundle.

### Configuration reference

The following settings control external gateway exposure and TLS for model deployments:

| Setting | Purpose |
|---|---|
| `spec.endpoint.exposure: external` | Exposes an individual model data-plane endpoint through the external gateway. |
| `spec.endpoint.path` | Sets the URL path for the model endpoint on the gateway. If omitted, the operator derives a path from the deployment name. |
| `operatorConfig.networking.externalGateway.tls.secretName` | Optional customer-managed TLS secret used by the external gateway for TLS termination. |
| `operatorConfig.networking.externalGateway.serviceAnnotations` | Optional cloud-provider annotations applied to the LoadBalancer service created for the external gateway. |


## Related content

- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md)
