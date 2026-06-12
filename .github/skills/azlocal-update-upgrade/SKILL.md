---
name: azlocal-update-upgrade
description: "**WORKFLOW SKILL** — Keep Azure Local current: apply solution updates (PowerShell, Azure Update Manager, offline) and perform OS/solution upgrades with readiness validation. WHEN: \"update Azure Local\", \"Azure Local solution update\", \"Azure Update Manager Azure Local\", \"upgrade Azure Local\", \"22H2 to 23H2\", \"update via PowerShell Azure Local\", \"offline update Azure Local\", \"validate upgrade readiness\". USE FOR: applying updates and OS/solution upgrades. DO NOT USE FOR: troubleshooting failed updates beyond the update flow (use azlocal-troubleshoot)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Update & Upgrade

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/update/` and `docs/upstream/azure-local/upgrade/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Plan or apply Azure Local solution updates
- Upgrade the OS/solution (for example 22H2 → 23H2) with readiness checks
- Choose between Azure Update Manager, PowerShell, and offline update paths

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/`; cite the exact file used.
2. Review update phases and best practices before applying anything.
3. Always validate solution upgrade readiness before applying an upgrade.
4. On failure, hand off to `azlocal-troubleshoot`; Microsoft Learn / governance wins on conflict.

## Steps

1. **Understand update phases** and review **best practices** before acting.
2. **Apply updates** via Azure Update Manager (portal), PowerShell, or the offline/limited-connectivity path.
3. **Upgrade** — read the upgrade overview, **validate solution upgrade readiness**, then apply.
4. **On failure**, hand off to `azlocal-troubleshoot` (update troubleshooting).

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/update/about-updates-23h2>
- Related skills: `azlocal-troubleshoot`, `azlocal-security`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [references/update-via-powershell.md](references/update-via-powershell.md) | **Code samples** — `Get-SolutionUpdate` / `Start-SolutionUpdate` PowerShell flow |
| [docs/upstream/azure-local/update/about-updates-23h2.md](../../../docs/upstream/azure-local/update/about-updates-23h2.md) | About updates |
| [docs/upstream/azure-local/update/update-phases-23h2.md](../../../docs/upstream/azure-local/update/update-phases-23h2.md) | Update phases |
| [docs/upstream/azure-local/update/azure-update-manager-23h2.md](../../../docs/upstream/azure-local/update/azure-update-manager-23h2.md) | Updating via Azure Update Manager |
| [docs/upstream/azure-local/update/update-best-practices.md](../../../docs/upstream/azure-local/update/update-best-practices.md) | Update best practices |
| [docs/upstream/azure-local/upgrade/about-upgrades-23h2.md](../../../docs/upstream/azure-local/upgrade/about-upgrades-23h2.md) | About upgrades |
| [docs/upstream/azure-local/upgrade/validate-solution-upgrade-readiness.md](../../../docs/upstream/azure-local/upgrade/validate-solution-upgrade-readiness.md) | Validating upgrade readiness |
