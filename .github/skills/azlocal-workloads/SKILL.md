---
name: azlocal-workloads
description: "**WORKFLOW SKILL** — Run workloads on Azure Local: Arc VMs, AKS clusters, SQL Server, and Azure Virtual Desktop (AVD). Routes to the right workload path. WHEN: \"run workloads on Azure Local\", \"AVD on Azure Local\", \"Azure Virtual Desktop Azure Local\", \"SQL Server on Azure Local\", \"run AKS on Azure Local\", \"deploy app to Azure Local\", \"workloads Azure Local\". USE FOR: choosing and starting a workload type on an existing instance. DO NOT USE FOR: deep AKS cluster lifecycle (use aksarc-on-azure-local), VM image/NIC lifecycle (use azlocal-vm-management)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Run Workloads

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/` and `docs/upstream/aksarc/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Decide which workload type to run on an existing Azure Local instance
- Start SQL Server, AVD, Arc VMs, or AKS workloads
- Route a workload request to the most specific skill

## Rules

1. Prefer the vendored docs under `docs/upstream/`; cite the exact file used.
2. Route to the most specific skill: VMs → `azlocal-vm-management`, AKS → `aksarc-on-azure-local`.
3. Confirm the target instance is deployed and healthy before placing workloads.
4. **AVD on Azure Local**: the control plane (host pool, application group, workspace) lives in Azure; session hosts are Arc VMs on the instance. Use **Standard** host-pool management — "session host configuration" is **not supported** on Azure Local. Session hosts must be **AD DS domain-joined** (Entra-only join isn't supported) and have the Connected Machine agent (for IMDS).
5. **AVD registration token**: retrieve it with the REST action `POST .../Microsoft.DesktopVirtualization/hostPools/<hp>/retrieveRegistrationToken?api-version=2025-10-10` (`--query token`). The `az desktopvirtualization hostpool retrieve-registration-token` CLI command and `GET ?$expand=registrationInfo` can return empty on older extension versions.
6. **AVD agent install**: deliver it via an Arc **machine extension** (`CustomScriptExtension`) that installs the RDInfra Agent (with `REGISTRATIONTOKEN`) then the Agent Boot Loader — not run-commands (see `azlocal-vm-management` rule on in-guest execution). Win11/Win10 multi-session needs no RDSH role; Windows Server session hosts do.
7. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps (route by workload)

1. **Arc VMs** — use `azlocal-vm-management` for images, networks, and VM lifecycle.
2. **AKS / containers** — use `aksarc-on-azure-local`; see `docs/upstream/aksarc/aks-create-clusters-portal.md`.
3. **SQL Server** — follow `docs/upstream/azure-local/deploy/sql-server-23h2.md`.
4. **Azure Virtual Desktop** (AVD on Azure Local):
   1. Deploy the **control plane** in Azure (Bicep): host pool (Standard, Pooled/BreadthFirst) + Desktop application group + workspace.
   2. **Retrieve the registration token** via the REST `retrieveRegistrationToken` action (see Rules).
   3. Create the **session host** as an Arc VM via `azlocal-vm-management` (sized with `vmSize:'Custom'`, AD domain-joined).
   4. **Install the AVD agent** via a `CustomScriptExtension` machine extension using the token.
   5. **Verify** the host is registered: `GET .../hostPools/<hp>/sessionHosts?api-version=2025-10-10` → `status` reaches **Available**. Activate VMs (Azure verification for VMs) for usability.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/>
- AVD on Azure Local: <https://learn.microsoft.com/azure/virtual-desktop/azure-local-overview>
- Related skills: `aksarc-on-azure-local`, `azlocal-vm-management`, `airunway-aks-setup`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/deploy/sql-server-23h2.md](../../../docs/upstream/azure-local/deploy/sql-server-23h2.md) | Running SQL Server on Azure Local |
| [docs/upstream/azure-local/manage/create-arc-virtual-machines.md](../../../docs/upstream/azure-local/manage/create-arc-virtual-machines.md) | Creating Arc VMs |
| [docs/upstream/aksarc/aks-create-clusters-portal.md](../../../docs/upstream/aksarc/aks-create-clusters-portal.md) | Creating an AKS cluster |
