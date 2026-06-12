---
name: azlocal-security
description: "**ANALYSIS SKILL** — Manage Azure Local security: security baseline/defaults, BitLocker encryption, Secure Boot, Microsoft Defender for Cloud, and compliance assurance (ISO 27001, PCI DSS, HIPAA, FedRAMP). WHEN: \"Azure Local security\", \"security baseline Azure Local\", \"BitLocker Azure Local\", \"Secure Boot Azure Local\", \"Defender for Cloud Azure Local\", \"Azure Local compliance\", \"application control WDAC\". USE FOR: hardening an Azure Local instance and mapping to compliance standards. DO NOT USE FOR: cloud subscription compliance scans (use azure-compliance)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Security & Compliance

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Review or adjust the security baseline / security defaults
- Manage BitLocker, Secure Boot updates, and Application Control
- Connect Defender for Cloud, or map the platform to a compliance standard

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/`; cite the exact file used.
2. Start from the secured-core baseline before layering additional controls.
3. Map controls to the relevant standard (ISO 27001 / PCI DSS / HIPAA / FedRAMP) via the security book.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Baseline** — review security features and manage the secured-core baseline/defaults.
2. **Data & boot protection** — manage BitLocker encryption and Secure Boot updates.
3. **Threat protection** — enable Microsoft Defender for Cloud.
4. **Assurance** — map controls to ISO 27001 / PCI DSS / HIPAA / FedRAMP via the security book.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/concepts/security-features>
- Related skills: `azlocal-update-upgrade`, `azlocal-monitor`, `sov-private-cloud`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [references/bitlocker-powershell.md](references/bitlocker-powershell.md) | **Code samples** — `Get/Enable/Disable-ASBitLocker` PowerShell cmdlets |
| [docs/upstream/azure-local/concepts/security-features.md](../../../docs/upstream/azure-local/concepts/security-features.md) | Security features overview |
| [docs/upstream/azure-local/manage/manage-secure-baseline.md](../../../docs/upstream/azure-local/manage/manage-secure-baseline.md) | Security baseline/defaults |
| [docs/upstream/azure-local/manage/manage-bitlocker.md](../../../docs/upstream/azure-local/manage/manage-bitlocker.md) | BitLocker encryption |
| [docs/upstream/azure-local/manage/manage-security-with-defender-for-cloud.md](../../../docs/upstream/azure-local/manage/manage-security-with-defender-for-cloud.md) | Defender for Cloud |
| [docs/upstream/azure-local/security-book/overview.md](../../../docs/upstream/azure-local/security-book/overview.md) | Security book |
| [docs/upstream/azure-local/assurance/azure-stack-security-standards.md](../../../docs/upstream/azure-local/assurance/azure-stack-security-standards.md) | Compliance standards |
