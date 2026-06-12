---
name: sov-private-cloud
description: "**ANALYSIS SKILL** — Design with Microsoft Sovereign Private Cloud on Azure Local: connected vs disconnected operations, use cases, and Foundry Local AI (deploy/run models, BYOM, inference) for on-premises sovereign AI. WHEN: \"Sovereign Private Cloud\", \"sovereign Azure Local\", \"connected operations\", \"disconnected operations sovereign\", \"Foundry Local\", \"on-premises AI sovereign\", \"run models on Azure Local\", \"sovereign AI workloads\". USE FOR: designing on-premises sovereign solutions on Azure Local. DO NOT USE FOR: public-cloud sovereignty (use sov-public-cloud), air-gapped operational runbooks (use azlocal-disconnected)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: sovereign-cloud
---

# Microsoft Sovereign Private Cloud (on Azure Local)

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-sovereign-clouds/private/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Design a Sovereign Private Cloud solution on Azure Local
- Choose connected vs disconnected operations for sovereign requirements
- Run on-premises sovereign AI with Foundry Local (models, BYOM, inference)

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-sovereign-clouds/private/`; cite the exact file used.
2. Map sovereign requirements to private-cloud scenarios before choosing an operations model.
3. Route air-gapped operational runbooks to `azlocal-disconnected`.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Overview & use cases** — map sovereign requirements to private-cloud scenarios.
2. **Operations model** — choose connected or disconnected operations (see `azlocal-disconnected`).
3. **Sovereign AI** — deploy Foundry Local, run a first model, and plan inference/BYOM.

## References

- Canonical: <https://learn.microsoft.com/industry/sovereignty/sovereign-private-cloud>
- Related skills: `azlocal-disconnected`, `aksarc-on-azure-local`, `airunway-aks-setup`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-sovereign-clouds/private/overview/sovereign-private-cloud.md](../../../docs/upstream/azure-sovereign-clouds/private/overview/sovereign-private-cloud.md) | Private cloud overview |
| [docs/upstream/azure-sovereign-clouds/private/azure-local/azure-local-overview.md](../../../docs/upstream/azure-sovereign-clouds/private/azure-local/azure-local-overview.md) | Azure Local in sovereign private cloud |
| [docs/upstream/azure-sovereign-clouds/private/azure-local/connected-operations-overview.md](../../../docs/upstream/azure-sovereign-clouds/private/azure-local/connected-operations-overview.md) | Connected operations |
| [docs/upstream/azure-sovereign-clouds/private/azure-local/disconnected-operations-overview.md](../../../docs/upstream/azure-sovereign-clouds/private/azure-local/disconnected-operations-overview.md) | Disconnected operations |
| [docs/upstream/azure-sovereign-clouds/private/azure-local/ai-workloads-overview.md](../../../docs/upstream/azure-sovereign-clouds/private/azure-local/ai-workloads-overview.md) | AI workloads overview |
| [docs/upstream/azure-sovereign-clouds/private/foundry-local/overview.md](../../../docs/upstream/azure-sovereign-clouds/private/foundry-local/overview.md) | Foundry Local overview |
| [docs/upstream/azure-sovereign-clouds/private/foundry-local/deploy-run-first-model.md](../../../docs/upstream/azure-sovereign-clouds/private/foundry-local/deploy-run-first-model.md) | Running a first model |
| [docs/upstream/azure-sovereign-clouds/private/use-cases/use-cases.md](../../../docs/upstream/azure-sovereign-clouds/private/use-cases/use-cases.md) | Use cases |
