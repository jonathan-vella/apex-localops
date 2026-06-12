---
name: sov-public-cloud
description: "**ANALYSIS SKILL** — Design with Microsoft Sovereign Public Cloud: capabilities, Data Guardian, external/confidential key management, confidential computing, Sovereign Landing Zone, sovereign policies, and AI workload sovereignty. WHEN: \"Sovereign Public Cloud\", \"Sovereign Landing Zone\", \"Data Guardian\", \"external key management sovereign\", \"confidential computing sovereign\", \"sovereign policy initiatives\", \"AI workloads sovereignty\". USE FOR: designing sovereign solutions in Azure public regions. DO NOT USE FOR: on-premises sovereign (use sov-private-cloud), foundational concepts (use sov-cloud-foundations)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: sovereign-cloud
---

# Microsoft Sovereign Public Cloud

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-sovereign-clouds/public/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Design a sovereign solution that stays in Azure public cloud
- Select capabilities (Data Guardian, external key management, confidential computing) and a Sovereign Landing Zone
- Address AI workload sovereignty and BCDR impacts of sovereign controls

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-sovereign-clouds/public/`; cite the exact file used.
2. Map each requirement to a concrete capability before recommending a design.
3. Adopt the Sovereign Landing Zone and design sovereign policy initiatives for governance.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Overview & capabilities** — map requirements to Sovereign Public Cloud capabilities.
2. **Controls** — apply Data Guardian, external key management, and confidential computing.
3. **Landing zone** — adopt the Sovereign Landing Zone and design sovereign policy initiatives.
4. **Workloads** — address AI workload sovereignty and BCDR impacts of sovereign controls.

## References

- Canonical: <https://learn.microsoft.com/industry/sovereignty/sovereign-public-cloud>
- Related skills: `sov-cloud-foundations`, `sov-private-cloud`, `azure-enterprise-infra-planner`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-sovereign-clouds/public/overview-sovereign-public-cloud.md](../../../docs/upstream/azure-sovereign-clouds/public/overview-sovereign-public-cloud.md) | Overview |
| [docs/upstream/azure-sovereign-clouds/public/sovereign-public-cloud-capabilities.md](../../../docs/upstream/azure-sovereign-clouds/public/sovereign-public-cloud-capabilities.md) | Capabilities |
| [docs/upstream/azure-sovereign-clouds/public/data-guardian.md](../../../docs/upstream/azure-sovereign-clouds/public/data-guardian.md) | Data Guardian |
| [docs/upstream/azure-sovereign-clouds/public/external-key-management.md](../../../docs/upstream/azure-sovereign-clouds/public/external-key-management.md) | External key management |
| [docs/upstream/azure-sovereign-clouds/public/confidential-computing.md](../../../docs/upstream/azure-sovereign-clouds/public/confidential-computing.md) | Confidential computing |
| [docs/upstream/azure-sovereign-clouds/public/overview-sovereign-landing-zone.md](../../../docs/upstream/azure-sovereign-clouds/public/overview-sovereign-landing-zone.md) | Sovereign Landing Zone |
| [docs/upstream/azure-sovereign-clouds/public/design-sovereign-policies.md](../../../docs/upstream/azure-sovereign-clouds/public/design-sovereign-policies.md) | Sovereign policies |
| [docs/upstream/azure-sovereign-clouds/public/ai-workloads-sovereignty.md](../../../docs/upstream/azure-sovereign-clouds/public/ai-workloads-sovereignty.md) | AI workload sovereignty |
