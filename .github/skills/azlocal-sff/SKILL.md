---
name: azlocal-sff
description: "**WORKFLOW SKILL** — Deploy and operate Azure Local Small Form Factor (SFF) for ruggedized/edge single-host scenarios: subscription setup, install (incl. in a VM), connect via portal, run containerized/GPU workloads, and troubleshoot. WHEN: \"Azure Local small form factor\", \"SFF Azure Local\", \"ruggedized Azure Local\", \"edge single host Azure Local\", \"SFF install\", \"SFF in a VM\", \"SFF configurator app\", \"SFF containerized workloads\". USE FOR: SFF edge/single-host evaluation and operation. DO NOT USE FOR: multi-node cluster deployment (use azlocal-deploy)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Small Form Factor (SFF)

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> SFF docs are vendored **separately** at `docs/azure-local-sff/upstream/` (a pinned mirror) — not under `docs/upstream/`. Prefer those files and this repo's SFF guides, cite the file you used, and treat Microsoft Learn as canonical when the mirror lags.

## Triggers

Activate this skill when the user wants to:
- Evaluate or deploy Azure Local SFF (including testing in a Hyper-V VM)
- Connect an SFF device from the portal and run edge workloads
- Troubleshoot an SFF device

## Rules

1. Use the pinned SFF mirror under `docs/azure-local-sff/upstream/`; cite the exact file used.
2. Set up the subscription and prerequisites before installing SFF.
3. For production, require a validated SFF device (per the overview).
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Set up the subscription** and prerequisites for SFF.
2. **Install** SFF on hardware or **in a VM** for evaluation.
3. **Connect** from the Azure portal (Configurator App / zero-touch provisioning).
4. **Run workloads** (containerized / GPU) and **troubleshoot** with system logs.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-overview>
- This repo's SFF flow: [docs/sff-quickstart.md](../../../docs/sff-quickstart.md)
- Related skills: `azlocal-deploy`, `aksarc-on-azure-local`, `azlocal-workloads`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/azure-local-sff/upstream/small-form-factor-overview.md](../../../docs/azure-local-sff/upstream/small-form-factor-overview.md) | SFF overview |
| [docs/azure-local-sff/upstream/small-form-factor-subscription-setup.md](../../../docs/azure-local-sff/upstream/small-form-factor-subscription-setup.md) | Subscription setup |
| [docs/azure-local-sff/upstream/small-form-factor-vm-installation.md](../../../docs/azure-local-sff/upstream/small-form-factor-vm-installation.md) | Installing in a VM |
| [docs/azure-local-sff/upstream/small-form-factor-connect-portal.md](../../../docs/azure-local-sff/upstream/small-form-factor-connect-portal.md) | Connecting via the portal |
| [docs/azure-local-sff/upstream/small-form-factor-troubleshoot.md](../../../docs/azure-local-sff/upstream/small-form-factor-troubleshoot.md) | Troubleshooting |
