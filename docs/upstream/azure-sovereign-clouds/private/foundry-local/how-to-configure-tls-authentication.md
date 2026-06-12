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

Foundry Local on Azure Local encrypts all internal service communication by using TLS. Each model service uses self-signed certificates that the cluster manages. This article explains how the TLS setup works and how to configure secure connections inside the cluster, across namespaces, and through external ingress.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Prerequisites

Automated certificate management requires cert-manager and trust-manager installed on your cluster:

- **cert-manager** issues a self-signed root CA and per-service certificates.
- **trust-manager** distributes the root CA certificate as a trust bundle to all namespaces so other pods can trust the internal certificates.

How you install these components depends on your deployment method:

- **Arc extension (recommended):** Install cert-manager for Arc-enabled Kubernetes (CME) by using `az k8s-extension create` with the `Microsoft.CertManagement` extension type. CME installs both cert-manager and trust-manager as a managed Arc extension. For installation steps, see [Install cert-manager and trust-manager](deploy-foundry-local-arc-extension.md#step-1-install-cert-manager-and-trust-manager).
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

## Configure external access through ingress

For access outside the cluster, use a Kubernetes ingress controller (such as NGINX Ingress) in front of Foundry's services. Foundry Local automatically configures ingress resources with specific NGINX annotations to enable secure communication. Foundry Local doesn't deploy an ingress controller itself - you bring your own.

> [!IMPORTANT]
> Install the ingress controller before you deploy the inference operator.

```bash
# Install ingress-nginx (NodePort)
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.hostPort.enabled=true \
  --wait
```

To configure external TLS with your own certificate:

```bash
# Step 1: Create a TLS secret from existing certificate files
kubectl create secret tls my-custom-tls \
  --namespace foundry-inference \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key
```

Then reference the secret in your ModelDeployment:

```yaml
# Step 2: Deploy with a custom certificate
apiVersion: foundrylocal.azure.com/v1
kind: InferenceService
metadata:
  name: phi-3-mini
  namespace: foundry-inference
spec:
  name: phi-3-mini
  inferenceType: generative
  hardware: cpu
  modelSource:
    foundry:
      modelName: Phi-3-mini-128k-instruct-generic-cpu:2
  replicas: 1
  port: 5000
  resources:
    requests:
      cpu: "1"
      memory: "4Gi"
    limits:
      cpu: "4"
      memory: "8Gi"
  tls:
    enabled: true
  ingress:
    enabled: true
    host: inference.customer-domain.com
    path: /models/phi-3-mini(/|$)(.*)
    rewritePath: /$2
    tls:
      enabled: true
      secretName: my-custom-tls
```



## Related content

- [Deploy Foundry Local as an Azure Arc extension](deploy-foundry-local-arc-extension.md)
- [Run inference on Foundry Local on Azure Local](how-to-run-inference.md)
- [ModelDeployment and operator configuration reference](reference-model-deployment-operator.md)
