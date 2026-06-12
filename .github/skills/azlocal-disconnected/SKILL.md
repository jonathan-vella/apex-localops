---
name: azlocal-disconnected
description: "**WORKFLOW SKILL** — Plan, deploy, and operate Azure Local disconnected operations (air-gapped / no continuous Azure connectivity): network, identity, security, PKI, control-plane appliance, and local management via CLI/PowerShell. WHEN: \"Azure Local disconnected operations\", \"air-gapped Azure Local\", \"Azure Local without internet\", \"disconnected operations deploy\", \"local control plane appliance\", \"disconnected identity\", \"disconnected PKI\", \"sovereign air gap Azure Local\". USE FOR: air-gapped Azure Local deployments and local operations. DO NOT USE FOR: connected-instance deployment (use azlocal-deploy)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Disconnected Operations

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/manage/` (the `disconnected-operations-*` pages). Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Design an air-gapped Azure Local deployment with a local control plane
- Operate VMs, registry, identity, and policy without Azure reachability
- Plan disconnected network, identity, security, or PKI

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/manage/`; cite the exact file used.
2. Plan the dedicated management cluster (network/identity/security/PKI) before deploying.
3. Use the local CLI/PowerShell control path — never assume outbound Azure connectivity.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Plan** the dedicated management cluster: network, identity, security, PKI.
2. **Acquire & prepare** nodes, then **deploy** disconnected operations and **register**.
3. **Operate locally** via Azure CLI / PowerShell; run Arc VMs and a local container registry.
4. **Monitor & recover** with on-demand/fallback log collection and backup/restore.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/manage/disconnected-operations-overview>
- Related skills: `sov-private-cloud`, `azlocal-security`, `azlocal-vm-management`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/manage/disconnected-operations-overview.md](../../../docs/upstream/azure-local/manage/disconnected-operations-overview.md) | Overview |
| [docs/upstream/azure-local/manage/disconnected-operations-prepare.md](../../../docs/upstream/azure-local/manage/disconnected-operations-prepare.md) | Preparing nodes |
| [docs/upstream/azure-local/manage/disconnected-operations-deploy.md](../../../docs/upstream/azure-local/manage/disconnected-operations-deploy.md) | Deploying |
| [docs/upstream/azure-local/manage/disconnected-operations-network.md](../../../docs/upstream/azure-local/manage/disconnected-operations-network.md) | Network planning |
| [docs/upstream/azure-local/manage/disconnected-operations-identity.md](../../../docs/upstream/azure-local/manage/disconnected-operations-identity.md) | Identity planning |
| [docs/upstream/azure-local/manage/disconnected-operations-security.md](../../../docs/upstream/azure-local/manage/disconnected-operations-security.md) | Security planning |
| [docs/upstream/azure-local/manage/disconnected-operations-pki.md](../../../docs/upstream/azure-local/manage/disconnected-operations-pki.md) | PKI planning |
| [docs/upstream/azure-local/manage/disconnected-operations-cli.md](../../../docs/upstream/azure-local/manage/disconnected-operations-cli.md) | Managing via CLI |
