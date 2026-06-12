---
name: azlocal-migrate
description: "**WORKFLOW SKILL** — Migrate VMs to Azure Local using Azure Migrate (Hyper-V and VMware) or PowerShell: requirements, replication, migration, and IP preservation. WHEN: \"migrate to Azure Local\", \"Azure Migrate Azure Local\", \"migrate Hyper-V to Azure Local\", \"migrate VMware to Azure Local\", \"VM migration Azure Local\", \"replicate VMs Azure Local\", \"maintain static IP migration\". USE FOR: moving existing Hyper-V/VMware VMs onto Azure Local. DO NOT USE FOR: cross-cloud app migration (use azure-cloud-migrate), creating net-new VMs (use azlocal-vm-management)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Migrate workloads

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/migrate/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Plan or execute migration of VMs into an Azure Local instance
- Choose between Azure Migrate and PowerShell-based migration
- Preserve static IPs and enable guest management during migration

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/migrate/`; cite the exact file used.
2. Review requirements and prerequisites before replicating any VM.
3. Preserve networking (static IPs) and enable guest management as part of cutover.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Choose an approach** from the migration overview (Azure Migrate vs PowerShell).
2. **Hyper-V** — review requirements/prerequisites → replicate → migrate & verify.
3. **VMware** — follow the equivalent requirements → replicate → migrate path.
4. **Preserve networking** (static IPs), enable guest management, and troubleshoot as needed.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/migrate/migration-options-overview>
- Related skills: `azlocal-vm-management`, `azlocal-networking`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/migrate/migration-options-overview.md](../../../docs/upstream/azure-local/migrate/migration-options-overview.md) | Options overview |
| [docs/upstream/azure-local/migrate/migrate-hyperv-requirements.md](../../../docs/upstream/azure-local/migrate/migrate-hyperv-requirements.md) | Hyper-V requirements |
| [docs/upstream/azure-local/migrate/migrate-hyperv-replicate.md](../../../docs/upstream/azure-local/migrate/migrate-hyperv-replicate.md) | Replicating Hyper-V VMs |
| [docs/upstream/azure-local/migrate/migrate-azure-migrate.md](../../../docs/upstream/azure-local/migrate/migrate-azure-migrate.md) | Migrating & verifying |
| [docs/upstream/azure-local/migrate/migrate-via-powershell.md](../../../docs/upstream/azure-local/migrate/migrate-via-powershell.md) | Migrating via PowerShell |
| [docs/upstream/azure-local/migrate/migrate-troubleshoot.md](../../../docs/upstream/azure-local/migrate/migrate-troubleshoot.md) | Troubleshooting migration |
