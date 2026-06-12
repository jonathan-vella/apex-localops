---
name: azlocal-vm-management
description: "**WORKFLOW SKILL** — Create and manage Arc VMs on Azure Local (single or at scale via Bicep): VM images, logical networks, NICs, GPU (DDA/partitioning), and Trusted Launch. WHEN: \"create Azure Local VM\", \"create Azure Local VMs at scale\", \"Azure Local VM Bicep\", \"deploy multiple Azure Local VMs\", \"Arc VM Azure Local\", \"manage Azure Local VMs\", \"Azure Local VM image\", \"attach GPU Azure Local\", \"GPU partitioning Azure Local\", \"Trusted Launch Azure Local\", \"VM extensions Azure Local\". USE FOR: Arc VM lifecycle and at-scale Bicep VM deployment on an Azure Local instance. DO NOT USE FOR: cluster networking design (use azlocal-networking), choosing a workload type (use azlocal-workloads)."
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
- Create many VMs **at scale** from a reusable Bicep template (a module loop over a VM array)
- Attach or partition GPUs for VM workloads
- Enable Trusted Launch (vTPM, Secure Boot, guest attestation) for VMs

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/manage/`; cite the exact file used.
2. Create VM resources in dependency order: storage path → image → logical network → NIC → VM.
3. Prepare GPUs before assigning them via DDA or partitioning.
4. For at-scale Bicep, deploy **one module per VM** (a `[for]` loop). Each VM needs its own Arc machine + NIC + a `virtualMachineInstance` named `'default'`. Resolve `adminPassword` at deploy time (env var) — never commit secrets.
5. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Create the VM resources** — storage path → VM image → logical network → NIC → VM.
2. **Create at scale with Bicep** — customize [templates/main.bicep](templates/main.bicep) + [templates/main.sample.bicepparam](templates/main.sample.bicepparam) (which fan out [templates/azlocal-vm.bicep](templates/azlocal-vm.bicep) once per VM in the `vms` array), then `export AZLOCAL_VM_ADMIN_PASSWORD=...` and `az deployment group create -g <rg> --template-file templates/main.bicep --parameters templates/main.sample.bicepparam`.
3. **Operate VMs** — start/stop/resize, manage resources and extensions.
4. **GPU workloads** — prepare GPUs, then assign via DDA or GPU partitioning.
5. **Harden** — enable Trusted Launch for sensitive VMs.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/manage/azure-arc-vm-management-overview>
- Create VMs (Bicep tab): <https://learn.microsoft.com/azure/azure-local/manage/create-arc-virtual-machines?tabs=biceptemplate>
- Bicep conventions: [iac-bicep-best-practices.instructions.md](../../instructions/iac-bicep-best-practices.instructions.md)
- Related skills: `azlocal-networking`, `azlocal-workloads`, `azlocal-security`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [templates/main.bicep](templates/main.bicep) | At-scale orchestrator — deploy N VMs via a module loop |
| [templates/azlocal-vm.bicep](templates/azlocal-vm.bicep) | Single-VM module (Arc machine + NIC + data disks + VM instance) |
| [templates/main.sample.bicepparam](templates/main.sample.bicepparam) | Example batch of VMs to customize and deploy |
| [docs/upstream/azure-local/manage/create-arc-virtual-machines.md](../../../docs/upstream/azure-local/manage/create-arc-virtual-machines.md) | Creating Azure Local VMs (Azure CLI / portal / ARM / Bicep tabs) |
| [docs/upstream/azure-local/manage/manage-arc-virtual-machines.md](../../../docs/upstream/azure-local/manage/manage-arc-virtual-machines.md) | Managing VMs |
| [docs/upstream/azure-local/manage/gpu-preparation.md](../../../docs/upstream/azure-local/manage/gpu-preparation.md) | Preparing GPUs |
| [docs/upstream/azure-local/manage/attach-gpu-to-linux-vm.md](../../../docs/upstream/azure-local/manage/attach-gpu-to-linux-vm.md) | Attaching a GPU to a VM |
| [docs/upstream/azure-local/manage/trusted-launch-vm-overview.md](../../../docs/upstream/azure-local/manage/trusted-launch-vm-overview.md) | Trusted Launch overview |
