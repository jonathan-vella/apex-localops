---
name: azlocal-vm-management
description: "**WORKFLOW SKILL** — Create and manage Arc VMs on Azure Local: VM images, logical networks, network interfaces, GPU (DDA/partitioning), and Trusted Launch. WHEN: \"create Azure Local VM\", \"Arc VM Azure Local\", \"manage Azure Local VMs\", \"Azure Local VM image\", \"attach GPU Azure Local\", \"GPU partitioning Azure Local\", \"Trusted Launch Azure Local\", \"VM extensions Azure Local\". USE FOR: Arc VM lifecycle on an Azure Local instance. DO NOT USE FOR: cluster networking design (use azlocal-networking), choosing a workload type (use azlocal-workloads)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Arc VM Management

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/manage/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Create Azure Local VM images, logical networks, NICs, and VMs
- Attach or partition GPUs for VM workloads
- Enable Trusted Launch (vTPM, Secure Boot, guest attestation) for VMs

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/manage/`; cite the exact file used.
2. Create VM resources in dependency order: storage path → image → logical network → NIC → VM.
3. Prepare GPUs before assigning them via DDA or partitioning.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Create the VM resources** — storage path → VM image → logical network → NIC → VM.
2. **Operate VMs** — start/stop/resize, manage resources and extensions.
3. **GPU workloads** — prepare GPUs, then assign via DDA or GPU partitioning.
4. **Harden** — enable Trusted Launch for sensitive VMs.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/manage/azure-arc-vm-management-overview>
- Related skills: `azlocal-networking`, `azlocal-workloads`, `azlocal-security`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/manage/create-arc-virtual-machines.md](../../../docs/upstream/azure-local/manage/create-arc-virtual-machines.md) | Creating Azure Local VMs |
| [docs/upstream/azure-local/manage/manage-arc-virtual-machines.md](../../../docs/upstream/azure-local/manage/manage-arc-virtual-machines.md) | Managing VMs |
| [docs/upstream/azure-local/manage/gpu-preparation.md](../../../docs/upstream/azure-local/manage/gpu-preparation.md) | Preparing GPUs |
| [docs/upstream/azure-local/manage/attach-gpu-to-linux-vm.md](../../../docs/upstream/azure-local/manage/attach-gpu-to-linux-vm.md) | Attaching a GPU to a VM |
| [docs/upstream/azure-local/manage/trusted-launch-vm-overview.md](../../../docs/upstream/azure-local/manage/trusted-launch-vm-overview.md) | Trusted Launch overview |
