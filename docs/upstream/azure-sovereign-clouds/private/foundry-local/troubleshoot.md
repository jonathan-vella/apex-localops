---
title: "Troubleshoot Foundry Local on Azure Local"
description: "Diagnose and resolve common issues in Foundry Local on Azure Local deployments, including certificates, GPU memory limits, model downloads, API crashes, and tool calling errors."
ms.service: azure
ms.subservice: sovereign-private-clouds
appliesto:
- Foundry Local on Azure Local
ms.topic: troubleshooting
ms.author: cwatson
author: cwatson-cat
ms.date: 06/04/2026
ai-usage: ai-assisted
customer intent: As a platform engineer or developer, I want to quickly diagnose and fix common failures in Foundry Local on Azure Local deployments so I can restore model deployment and inference operations.
---

# Troubleshoot Foundry Local on Azure Local

This article provides troubleshooting steps for common issues that might arise when deploying and running Foundry Local on Azure Local. Use the following guidance to identify and resolve problems related to certificates, GPU memory limits, model downloads, API crashes, tool calling, and support diagnostics.

[!INCLUDE [foundry-local-preview](includes/foundry-local-preview.md)]

## Before you troubleshoot

Collect baseline cluster state first. These checks help you identify whether the issue is installation, runtime capacity, or API behavior.

### Check core component health

Run the following commands to confirm operator, certificate, and deployment components are healthy.

```bash
kubectl get pods -n foundry-local-operator
kubectl get pods -n cert-manager
kubectl get certificates -n foundry-local-operator
kubectl get modeldeployment -A
```

### Check events for failing workloads

Run the following command to identify scheduling, certificate, or container startup failures.

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
```

## Pods stuck in Init or TLS secret not found

If workloads are stuck in `Init` state or you see errors about missing TLS secrets, validate cert-manager first.

1. Verify all cert-manager components are running:

    ```bash
    kubectl get pods -n cert-manager
    ```

1. Confirm certificates are issued and `Ready=True`:

    ```bash
    kubectl get certificates -n foundry-local-operator
    ```

1. Inspect cert-manager logs for issuance or webhook failures:

    ```bash
    kubectl logs -n cert-manager -l app=cert-manager --tail=200
    ```

If any cert-manager component isn't healthy, resolve that condition before retrying model deployment.

## Model deployment fails to start or reports GPU memory errors

If a deployment fails during startup, remains pending, or reports GPU memory pressure:

1. Start with default runtime settings. Remove custom vLLM tuning and let the planner select values.
1. Verify model size and context length fit available GPU VRAM.
1. Increase GPU capacity when model requirements exceed current hardware.
1. Validate CPU and memory requests and limits in your `ModelDeployment` spec.

### Check node and pod resource pressure

Run the following commands to determine whether node-level or pod-level resource pressure is blocking startup.

```bash
kubectl describe nodes
kubectl top nodes
kubectl top pods -A
```

## Model download is stuck or cache job fails

If model download doesn't progress or cache jobs repeatedly fail:

1. Deploy a smaller model first to validate end-to-end download and startup.
1. If smaller models succeed but larger models fail, inspect network path reliability.
1. Check proxy, firewall, and intermediate network devices that can interrupt long-lived downloads.

### Check cache and deployment events

Run the following commands to identify where model download or cache processing is failing.

Replace `<deployment-name>` with your model deployment name before running the following commands.

```bash
kubectl get jobs -A
kubectl describe modeldeployment <deployment-name> -n foundry-local-operator
kubectl get events -n foundry-local-operator --sort-by=.lastTimestamp
```

## inference-operator-api pod is in CrashLoopBackOff

If the `inference-operator-api` pod restarts continuously:

1. Check pod events for `OOMKilled`.
1. Reduce API worker count to one worker.
1. Increase API memory requests and limits.

Use the following values in extension configuration:

```yaml
api:
  config:
    server:
      workers: 1
  resources:
    requests:
      memory: 2Gi
    limits:
      memory: 2Gi
```

Then verify restart behavior and logs:

Replace `<inference-operator-api-pod>` with the pod name from your environment before you run the following commands.

```bash
kubectl get pods -n foundry-local-operator
kubectl describe pod <inference-operator-api-pod> -n foundry-local-operator
kubectl logs <inference-operator-api-pod> -n foundry-local-operator --previous
```

## Tool calling fails or produces malformed calls

If model tool calls fail, are malformed, or return unexpected structure:

1. Verify the deployed model supports tool calling.
1. Simplify your tool schema. Remove complex constructs incrementally, such as deep nesting, large arrays, and strict uniqueness constraints.
1. Reduce the number of tools included in a single request.
1. Test `tool_choice` with `auto` instead of forcing `required`.

When you troubleshoot request payload shape, start from a minimal request and add complexity one field at a time.

## Collect diagnostic logs for support

When opening a support request, include recent events, pod descriptions, and component logs.

Replace `<deployment-name>` with your model deployment name before running the following commands.

```bash
az k8s-extension troubleshoot --name foundry --namespace-list "foundry-local-operator"
kubectl get events -A --sort-by=.lastTimestamp
kubectl describe modeldeployment <deployment-name> -n foundry-local-operator
kubectl logs -n foundry-local-operator deployment/inference-operator-api --tail=500
```

## Related content

- [Known issues for Foundry Local on Azure Local](known-issues.md)
- [Troubleshoot Foundry Local on Azure Local in disconnected environments](disconnected-operations/how-to-troubleshoot.md)
- [Troubleshoot Azure Kubernetes Service (AKS) issues](/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes)
- [kubectl reference](https://kubernetes.io/docs/reference/kubectl/generated/)
