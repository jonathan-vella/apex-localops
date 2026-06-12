---
name: azlocal-networking
description: "**WORKFLOW SKILL** — Configure Azure Local host and tenant networking: Network ATC intents, software-defined networking (SDN), Network Controller, datacenter firewall, and network security groups (NSGs). WHEN: \"Azure Local networking\", \"Network ATC\", \"configure SDN Azure Local\", \"Network Controller\", \"datacenter firewall\", \"network security groups Azure Local\", \"NSG Azure Local\", \"logical networks Azure Local\". USE FOR: host networking intents and tenant SDN/firewall/NSG configuration. DO NOT USE FOR: VM lifecycle (use azlocal-vm-management), cloud Azure networking (use azure-enterprise-infra-planner)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Networking (Network ATC & SDN)

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/concepts/` and `docs/upstream/azure-local/manage/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Define or modify Network ATC intents (management/compute/storage)
- Enable SDN, deploy Network Controller, or manage the datacenter firewall
- Create and apply network security groups to tenant workloads

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/`; cite the exact file used.
2. Define Network ATC intents before enabling tenant SDN.
3. Treat SDN (Network Controller) as optional — only when overlay networks, load balancing, or gateways are required.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Host networking** — review Network ATC concepts and define intents for the cluster.
2. **Enable SDN** (optional) when tenant overlay networks, load balancing, or gateways are needed.
3. **Network Controller** — plan and deploy as the SDN control plane.
4. **Segmentation** — create and manage NSGs; apply the datacenter firewall to tenant traffic.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/concepts/network-atc-overview>
- Related skills: `azlocal-plan-size`, `azlocal-vm-management`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/concepts/network-atc-overview.md](../../../docs/upstream/azure-local/concepts/network-atc-overview.md) | Network ATC overview |
| [docs/upstream/azure-local/concepts/software-defined-networking-23h2.md](../../../docs/upstream/azure-local/concepts/software-defined-networking-23h2.md) | SDN overview |
| [docs/upstream/azure-local/concepts/network-controller-overview.md](../../../docs/upstream/azure-local/concepts/network-controller-overview.md) | Network Controller |
| [docs/upstream/azure-local/concepts/datacenter-firewall-overview.md](../../../docs/upstream/azure-local/concepts/datacenter-firewall-overview.md) | Datacenter firewall |
| [docs/upstream/azure-local/manage/create-network-security-groups.md](../../../docs/upstream/azure-local/manage/create-network-security-groups.md) | Creating NSGs |
| [docs/upstream/azure-local/manage/manage-network-security-groups.md](../../../docs/upstream/azure-local/manage/manage-network-security-groups.md) | Managing NSGs |
