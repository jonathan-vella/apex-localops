---
name: azlocal-troubleshoot
description: "**ANALYSIS SKILL** — Troubleshoot Azure Local deployment, registration, and update failures: collect logs, use the diagnostic support tools, and open support. WHEN: \"troubleshoot Azure Local\", \"Azure Local deployment failed\", \"collect logs Azure Local\", \"Azure Local registration issue\", \"deployment validation failed\", \"diagnostic support tool\", \"update failed Azure Local\", \"Configurator app issue\". USE FOR: diagnosing Azure Local infrastructure failures. DO NOT USE FOR: tenant app/Kubernetes debugging (use azure-diagnostics)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Troubleshoot

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags.

## Triggers

Activate this skill when the user wants to:
- Diagnose a deployment, registration, or update that did not complete
- Collect logs or engage Microsoft support with the right diagnostics
- Run the diagnostic support tools

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/`; cite the exact file used.
2. Scope the failure class (deployment validation vs registration vs update) before acting.
3. Collect logs and run the diagnostic support tools before opening a support case.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Reproduce/scope** the failure (deployment validation vs registration vs update).
2. **Collect logs** and run the diagnostic support tools.
3. **Apply targeted fixes** from the matching troubleshooting doc.
4. **Open support** with collected diagnostics if unresolved.

## Workload VM / AVD symptoms

For workload (Arc VM, SQL, AVD) failures rather than infrastructure failures, also see
`azlocal-vm-management` and `azlocal-workloads`. Common symptoms observed in practice:

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| VM shows **0 CPU / 0 MB**, won't boot, guest agent never installs | Sized with an Azure SKU name / `Default`, or `--hardware-profile` without `vm-size="Custom"` | Recreate with `hardwareProfile.vmSize:'Custom'` + `processors` + `memoryMB` (Bicep). A post-create resize cannot revive a 0/0 VM. |
| `guestAgentInstallStatus.status` is `null` on a healthy VM | Expected on Azure Local — that field is unreliable | Judge health by `instanceView.vmAgent.statuses[0].displayStatus` + Arc machine `status=Connected` and non-null `agentVersion`. |
| In-guest run-command returns `Unknown` / empty; `az stack-hci-vm run-command` not found | HybridCompute `runCommands` doesn't dispatch reliably on Azure Local; that CLI verb doesn't exist | Use an Arc **machine extension** (`JsonADDomainExtension`, `CustomScriptExtension`) instead. |
| `az stack-hci-vm show --query` returns empty | CLI quirk for these resource types | Read via `az rest GET .../virtualMachineInstances/default?api-version=2024-01-01`. |
| AVD registration token comes back empty | Older `desktopvirtualization` CLI ext / `GET ?$expand=registrationInfo` | Use REST `POST .../hostPools/<hp>/retrieveRegistrationToken?api-version=2025-10-10`. |
| Marketplace VM **image create fails** | `Microsoft.EdgeMarketplace` RP not registered | Register the provider, then recreate the image; confirm `Succeeded` before VM create. |
| AVD session host stuck **Unavailable** | Agent/boot-loader not installed, not AD-joined, or no outbound 443 to the AVD broker / IMDS | Verify domain join + Connected Machine agent, install the AVD agent via extension, and confirm egress. |

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/manage/collect-logs>
- Related skills: `azlocal-deploy`, `azlocal-update-upgrade`, `azlocal-monitor`, `azlocal-vm-management`, `azlocal-workloads`
- Repo-specific recovery automation: [docs/localbox/troubleshooting.md](../../../docs/localbox/troubleshooting.md)

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/manage/troubleshoot-deployment.md](../../../docs/upstream/azure-local/manage/troubleshoot-deployment.md) | Deployment validation issues |
| [docs/upstream/azure-local/manage/collect-logs.md](../../../docs/upstream/azure-local/manage/collect-logs.md) | Collecting logs |
| [docs/upstream/azure-local/manage/get-support-for-deployment-issues.md](../../../docs/upstream/azure-local/manage/get-support-for-deployment-issues.md) | Support for deployment issues |
| [docs/upstream/azure-local/manage/get-support.md](../../../docs/upstream/azure-local/manage/get-support.md) | Opening a support case |
| [docs/upstream/azure-local/update/update-troubleshooting-23h2.md](../../../docs/upstream/azure-local/update/update-troubleshooting-23h2.md) | Update troubleshooting |
