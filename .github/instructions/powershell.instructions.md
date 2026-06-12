---
description: "PowerShell cmdlet and scripting best practices (Microsoft guidelines) for owned modules under artifacts/PowerShell/workloads/."
applyTo: "artifacts/PowerShell/workloads/**/*.ps1, artifacts/PowerShell/workloads/**/*.psm1"
---

# PowerShell Cmdlet & Scripting Guidelines

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/powershell.instructions.md`, retargeted for apex-localops.

> [!IMPORTANT]
> **Scope is owned code only** (`artifacts/PowerShell/workloads/`). The rest of
> `artifacts/PowerShell/`, `artifacts/PowerShell/dsc/`, and `artifacts/sff/vendor/` is **vendored**
> from upstream (Arc Jumpstart LocalBox / Azure-Samples, CC BY 4.0 / MIT) — do **not** reformat it
> to these rules; see [ATTRIBUTION.md](../../ATTRIBUTION.md).

## Quick reference

| Rule | Standard |
| --- | --- |
| Naming | `Verb-Noun` with approved verbs (`Get-Verb`), PascalCase |
| Parameters | PascalCase, singular; use `ValidateSet`/`ValidateNotNullOrEmpty` |
| Variables | PascalCase (public), camelCase (private); no cryptic abbreviations |
| Aliases | Never in scripts — full cmdlet + parameter names |
| Indentation | 4 spaces; opening `{` on the same line |

## Mandatory patterns

### CmdletBinding + comment-based help

Every public function has `[CmdletBinding()]` and `.SYNOPSIS` / `.DESCRIPTION` / `.PARAMETER` /
`.EXAMPLE` help.

### Destructive operations

Use `[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]` for any function
that changes system state.

### Error handling

- `$ErrorActionPreference = 'Stop'` in the `begin` block.
- `try`/`catch` with specific exception types; prefer `$PSCmdlet.ThrowTerminatingError()`.
- `Write-Verbose` for operational detail, `Write-Warning` for warnings. Avoid `Write-Host`
  except for genuine console UI (note: vendored LocalBox scripts use `Write-Host` heavily — that
  is upstream style and out of scope here).

### Non-interactive design

Accept input via parameters — never `Read-Host` in automation scripts (this repo runs in
unattended deploy contexts). Document all required inputs.

## Validation

```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path artifacts/PowerShell/workloads -Recurse"
```

(`PSScriptAnalyzer` if available; otherwise rely on review. There is no PowerShell CI gate today.)
