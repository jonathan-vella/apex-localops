---
name: azlocal-plan-size
description: "**ANALYSIS SKILL** — Plan and size an Azure Local instance: node count, network reference pattern, system/physical-network/firewall requirements, and Active Directory prep. WHEN: \"plan Azure Local\", \"size Azure Local cluster\", \"Azure Local requirements\", \"how many nodes Azure Local\", \"network reference pattern\", \"Azure Local system requirements\", \"physical network requirements\", \"firewall requirements Azure Local\". USE FOR: pre-deployment planning and requirement validation. DO NOT USE FOR: running the deployment (use azlocal-deploy), SFF edge sizing (use azlocal-sff)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Plan & Size

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/plan/` and `docs/upstream/azure-local/concepts/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Decide how many nodes and which network reference pattern fits a workload
- Verify system, physical-network, and firewall requirements before a deploy
- Plan Active Directory preparation and naming

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/`; cite the exact file used.
2. Validate every requirement class (system, network, firewall) before handing off to deployment.
3. Microsoft Learn / discovered governance wins over the mirror on any conflict.
4. Record the chosen node count and network pattern so `azlocal-deploy` can consume them.

## Steps

1. **Pick a deployment type & node count** — compare single-server, two-node (switchless/switched), three-node, four-node, and multi-rack trade-offs.
2. **Choose a network reference pattern** and capture its IP/VLAN requirements.
3. **Validate requirements** — system (CPU/RAM/storage/TPM), physical network (NIC speeds, RDMA), firewall/endpoint allow-lists.
4. **Plan Active Directory** — OU, naming, and custom AD settings.
5. **Hand off** to `azlocal-deploy` once requirements pass.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/plan/>
- Related skills: `azlocal-deploy`, `azlocal-networking`, `azlocal-sff`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/plan/network-patterns-overview.md](../../../docs/upstream/azure-local/plan/network-patterns-overview.md) | Choosing a network reference pattern |
| [docs/upstream/azure-local/plan/single-server-deployment.md](../../../docs/upstream/azure-local/plan/single-server-deployment.md) | Single-node pattern |
| [docs/upstream/azure-local/plan/two-node-switchless-single-switch.md](../../../docs/upstream/azure-local/plan/two-node-switchless-single-switch.md) | Two-node switchless pattern |
| [docs/upstream/azure-local/plan/three-node-components.md](../../../docs/upstream/azure-local/plan/three-node-components.md) | Three-node components |
| [docs/upstream/azure-local/concepts/system-requirements-23h2.md](../../../docs/upstream/azure-local/concepts/system-requirements-23h2.md) | System requirements |
| [docs/upstream/azure-local/concepts/physical-network-requirements.md](../../../docs/upstream/azure-local/concepts/physical-network-requirements.md) | Physical network requirements |
| [docs/upstream/azure-local/concepts/firewall-requirements.md](../../../docs/upstream/azure-local/concepts/firewall-requirements.md) | Firewall / endpoint requirements |
| [docs/upstream/azure-local/plan/configure-custom-settings-active-directory.md](../../../docs/upstream/azure-local/plan/configure-custom-settings-active-directory.md) | Active Directory prep |
