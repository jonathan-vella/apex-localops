---
name: azlocal-monitor
description: "**ANALYSIS SKILL** — Monitor Azure Local with Insights, metrics, and alerts (single and at-scale), plus observability concepts. WHEN: \"monitor Azure Local\", \"Azure Local Insights\", \"Azure Local metrics\", \"Azure Local alerts\", \"health alerts Azure Local\", \"monitor multiple Azure Local systems\", \"observability Azure Local\", \"monitor at scale\". USE FOR: Azure Local instance health monitoring. DO NOT USE FOR: app/Kubernetes runtime debugging on Azure (use azure-diagnostics / azure-kusto)."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---

# Azure Local — Monitor

> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE**
>
> This skill is grounded in the vendored Microsoft docs under `docs/upstream/azure-local/`. Prefer those files over prior knowledge, cite the file you used, and treat Microsoft Learn as canonical when the weekly mirror lags. For application/Kubernetes runtime debugging on Azure, prefer `azure-diagnostics` / `azure-kusto` — this skill is specific to **Azure Local instance** monitoring.

## Triggers

Activate this skill when the user wants to:
- Enable Insights for one or many Azure Local systems
- Configure metrics and Azure Monitor health/log/metric alerts
- Understand Azure Local observability options

## Rules

1. Prefer the vendored docs under `docs/upstream/azure-local/`; cite the exact file used.
2. Enable single-system Insights before scaling to multi-system monitoring.
3. Route app/Kubernetes runtime debugging to `azure-diagnostics` / `azure-kusto`.
4. Microsoft Learn / discovered governance wins over the mirror on any conflict.

## Steps

1. **Understand observability** options for Azure Local.
2. **Enable Insights** for a single system, then **at scale** (multi-system, Azure Policy).
3. **Metrics & alerts** — monitor cluster metrics and set up recommended alert rules.

## References

- Canonical: <https://learn.microsoft.com/azure/azure-local/concepts/monitoring-overview>
- Related skills: `azlocal-security`, `azlocal-troubleshoot`

## Reference Index

Load these on demand — do NOT read all at once:

| Reference | When to Load |
| --- | --- |
| [docs/upstream/azure-local/concepts/observability.md](../../../docs/upstream/azure-local/concepts/observability.md) | Observability concepts |
| [docs/upstream/azure-local/manage/monitor-single-23h2.md](../../../docs/upstream/azure-local/manage/monitor-single-23h2.md) | Monitoring a single system |
| [docs/upstream/azure-local/manage/monitor-multi-23h2.md](../../../docs/upstream/azure-local/manage/monitor-multi-23h2.md) | Monitoring multiple systems |
| [docs/upstream/azure-local/manage/monitor-cluster-with-metrics.md](../../../docs/upstream/azure-local/manage/monitor-cluster-with-metrics.md) | Cluster metrics |
| [docs/upstream/azure-local/manage/health-alerts-via-azure-monitor-alerts.md](../../../docs/upstream/azure-local/manage/health-alerts-via-azure-monitor-alerts.md) | Health alerts |
