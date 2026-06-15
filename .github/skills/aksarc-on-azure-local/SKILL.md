---
name: aksarc-on-azure-local
description: "**WORKFLOW SKILL** — Plan, create, and operate AKS (Arc) clusters on Azure Local: requirements, create via portal/CLI/API, node pools & autoscaling, upgrades, networking, storage, security/identity, and monitoring. WHEN: \"AKS on Azure Local\", \"AKS Arc\", \"create AKS cluster Azure Local\", \"Kubernetes on Azure Local\", \"AKS hybrid\", \"node pool Azure Local\", \"autoscale AKS Arc\", \"upgrade AKS Arc cluster\". USE FOR: AKS cluster lifecycle on Azure Local. DO NOT USE FOR: AKS in Azure cloud (use azure-kubernetes), model serving on AKS (use airunway-aks-setup)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: aks-arc
---

# AKS on Azure Local (AKS Arc)

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/aksarc/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags. For **cloud** AKS (Azure-hosted), use `azure-kubernetes` instead — this skill is for AKS on Azure Local.

## Triggers

Activate this skill when the user wants to:
- Stand up or operate an AKS cluster on Azure Local
- Configure node pools, autoscaling, upgrades, networking, storage, or identity for AKS Arc
- Verify AKS-on-Azure-Local requirements

## Rules

1. Prefer the vendored docs under `docs/upstream/aksarc/`; cite the exact file used.
2. Verify requirements before creating a cluster.
3. Route cloud AKS to `azure-kubernetes`; route model serving to `airunway-aks-setup`.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Verify requirements** for AKS on Azure Local.
2. **Create the cluster** via portal, CLI, or ARM/API.
3. **Scale** — configure node pools and the cluster autoscaler.
4. **Operate** — upgrade clusters, wire up networking/storage, and apply security/identity.
5. **Observe** — enable monitoring and logging.

## References

- Canonical: <https://learn.microsoft.com/azure/aks/aksarc/aks-overview>
- Related skills: `azlocal-workloads`, `azure-kubernetes` (cloud), `airunway-aks-setup`
- Repo-specific AKS on bare metal (SFF) flow: [docs/sff/aks-baremetal.md](../../../docs/sff/aks-baremetal.md)

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [references/cli-quickstart.md](references/cli-quickstart.md) | **Code samples** — `az aksarc` create / connect / nodepool / delete CLI flow |
| [docs/upstream/aksarc/aks-overview.md](../../../docs/upstream/aksarc/aks-overview.md) | Overview |
| [docs/upstream/aksarc/cluster-architecture.md](../../../docs/upstream/aksarc/cluster-architecture.md) | Cluster architecture |
| [docs/upstream/aksarc/aks-arc-local-requirements.md](../../../docs/upstream/aksarc/aks-arc-local-requirements.md) | Requirements |
| [docs/upstream/aksarc/aks-create-clusters-portal.md](../../../docs/upstream/aksarc/aks-create-clusters-portal.md) | Creating a cluster (portal) |
| [docs/upstream/aksarc/aks-create-clusters-cli.md](../../../docs/upstream/aksarc/aks-create-clusters-cli.md) | Creating a cluster (CLI) |
| [docs/upstream/aksarc/auto-scale-aks-arc.md](../../../docs/upstream/aksarc/auto-scale-aks-arc.md) | Autoscaling |
| [docs/upstream/aksarc/cluster-upgrade.md](../../../docs/upstream/aksarc/cluster-upgrade.md) | Upgrading clusters |
| [docs/upstream/aksarc/aks-networks.md](../../../docs/upstream/aksarc/aks-networks.md) | Networking |
| [docs/upstream/aksarc/concepts-storage.md](../../../docs/upstream/aksarc/concepts-storage.md) | Storage |
| [docs/upstream/aksarc/concepts-security.md](../../../docs/upstream/aksarc/concepts-security.md) | Security |
| [docs/upstream/aksarc/aks-monitor-logging.md](../../../docs/upstream/aksarc/aks-monitor-logging.md) | Monitoring & logging |
