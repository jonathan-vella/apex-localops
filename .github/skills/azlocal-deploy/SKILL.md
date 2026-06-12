---
name: azlocal-deploy
description: "**WORKFLOW SKILL** — Deploy an Azure Local instance via Azure portal or ARM template: prerequisites, software download, OS install, Arc registration, and cloud deployment. WHEN: \"deploy Azure Local\", \"install Azure Local\", \"Azure Local deployment\", \"deploy via portal\", \"Azure Local ARM template\", \"register Azure Local with Arc\", \"download Azure Local software\". USE FOR: running a fresh Azure Local 23H2+ deployment end to end. DO NOT USE FOR: planning/sizing (use azlocal-plan-size), SFF edge devices (use azlocal-sff), AKS clusters (use aksarc-on-azure-local)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Deploy

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/deploy/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Perform a fresh Azure Local deployment after planning is complete
- Choose between Azure portal and ARM-template deployment methods
- Register Azure Local machines with Azure Arc and complete cloud deployment

## Prerequisites

- Planning complete (see `azlocal-plan-size`): node count, network pattern, requirements verified.
- Azure subscription with the required RBAC roles and resource providers registered.

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/deploy/`; cite the exact file used.
2. Complete every prerequisite before installing the OS — do not skip validation.
3. Use the ARM-template path for repeatable, idempotent deployments.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Read the deployment overview** and complete all **prerequisites**.
2. **Download the software** (Azure Local OS) and **install the OS** on each node.
3. **Register the machines with Azure Arc** and assign deployment permissions.
4. **Deploy** via the Azure portal or an **ARM template** (idempotent, repeatable).
5. **Validate** the instance, then proceed to `azlocal-monitor` and `azlocal-security`.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/deploy/deployment-introduction>
- Related skills: `azlocal-plan-size` (before), `azlocal-networking`, `azlocal-update-upgrade` (after)
- This repo's nested deployment automation: [docs/deployment-quickstart.md](../../../docs/deployment-quickstart.md)

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/deploy/deployment-introduction.md](../../../docs/upstream/azure-local/deploy/deployment-introduction.md) | Deployment overview |
| [docs/upstream/azure-local/deploy/deployment-prerequisites.md](../../../docs/upstream/azure-local/deploy/deployment-prerequisites.md) | Completing prerequisites |
| [docs/upstream/azure-local/deploy/download-23h2-software.md](../../../docs/upstream/azure-local/deploy/download-23h2-software.md) | Downloading the OS software |
| [docs/upstream/azure-local/deploy/deployment-install-os.md](../../../docs/upstream/azure-local/deploy/deployment-install-os.md) | Installing the OS on nodes |
| [docs/upstream/azure-local/deploy/deploy-via-portal.md](../../../docs/upstream/azure-local/deploy/deploy-via-portal.md) | Deploying via the Azure portal |
| [docs/upstream/azure-local/deploy/deployment-azure-resource-manager-template.md](../../../docs/upstream/azure-local/deploy/deployment-azure-resource-manager-template.md) | Deploying via ARM template |
