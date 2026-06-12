---
name: sov-cloud-foundations
description: "**ANALYSIS SKILL** — Explain Microsoft Sovereign Cloud foundations: digital sovereignty, European digital commitments, and the data / operational / technological-independence / key-management controls. WHEN: \"what is Microsoft Sovereign Cloud\", \"digital sovereignty\", \"sovereignty controls\", \"data controls sovereign\", \"operational controls sovereign\", \"technological independence\", \"key management controls\", \"European digital commitments\". USE FOR: explaining sovereignty concepts and the control taxonomy. DO NOT USE FOR: implementing public-cloud (use sov-public-cloud) or private-cloud (use sov-private-cloud) solutions."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: sovereign-cloud
---

# Microsoft Sovereign Cloud — Foundations

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-sovereign-clouds/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Answer "what is sovereign cloud" and explain the control taxonomy
- Establish shared vocabulary before designing a public or private sovereign solution
- Understand digital sovereignty and the European digital commitments

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-sovereign-clouds/`; cite the exact file used.
2. Distinguish the control families (data, operational, technological, key management) precisely.
3. Hand off implementation to `sov-public-cloud` or `sov-private-cloud`.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Digital sovereignty** — explain data, operational, and technological sovereignty goals.
2. **Control families** — cover data controls, operational controls, technological independence, key management.
3. **Commitments** — relate the European digital commitments to the controls.

## References

- Canonical: <https://learn.microsoft.com/industry/sovereignty/>
- Related skills: `sov-public-cloud`, `sov-private-cloud`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-sovereign-clouds/microsoft-sovereign-cloud.md](../../../docs/upstream/azure-sovereign-clouds/microsoft-sovereign-cloud.md) | What is Sovereign Cloud |
| [docs/upstream/azure-sovereign-clouds/digital-sovereignty.md](../../../docs/upstream/azure-sovereign-clouds/digital-sovereignty.md) | Digital sovereignty |
| [docs/upstream/azure-sovereign-clouds/european-digital-commitments.md](../../../docs/upstream/azure-sovereign-clouds/european-digital-commitments.md) | EU commitments |
| [docs/upstream/azure-sovereign-clouds/data-controls.md](../../../docs/upstream/azure-sovereign-clouds/data-controls.md) | Data controls |
| [docs/upstream/azure-sovereign-clouds/operational-controls.md](../../../docs/upstream/azure-sovereign-clouds/operational-controls.md) | Operational controls |
| [docs/upstream/azure-sovereign-clouds/technological-independence.md](../../../docs/upstream/azure-sovereign-clouds/technological-independence.md) | Technological independence |
| [docs/upstream/azure-sovereign-clouds/key-controls.md](../../../docs/upstream/azure-sovereign-clouds/key-controls.md) | Key management controls |
| [docs/upstream/azure-sovereign-clouds/glossary.md](../../../docs/upstream/azure-sovereign-clouds/glossary.md) | Glossary |
