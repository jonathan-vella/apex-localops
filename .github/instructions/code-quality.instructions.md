---
description: "Code quality: commenting best practices (WHY not WHAT) and review priorities with security checks, scoped to owned source."
applyTo: "scripts/**/*.sh, infra/bicep/**/*.bicep, artifacts/PowerShell/workloads/**/*.ps1, artifacts/PowerShell/workloads/**/*.psm1, .github/workflows/*.yml"
---

# Code Quality Guidelines

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/code-quality.instructions.md`, retargeted for apex-localops
> (apex's npm validators, `site/`, and Python references removed).

## Language-specific precedence

Language files take precedence over this general guidance:

- **Shell** ([shell.instructions.md](./shell.instructions.md)) — header comment + `set -euo pipefail`.
- **PowerShell** ([powershell.instructions.md](./powershell.instructions.md)) — comment-based help on public functions.
- **Bicep** ([iac-bicep-best-practices.instructions.md](./iac-bicep-best-practices.instructions.md)) — `@description` on parameters and outputs.

## Commenting: comment WHY, not WHAT

### Avoid

- Obvious: `count=0  # set count to zero`
- Redundant: comment restates the code.
- Outdated: comment no longer matches the code.

### Write

- Complex logic (WHY a calculation is done this way).
- Non-obvious algorithm or ordering choices.
- Regex intent; external API constraints/gotchas (this repo has many Azure Local quirks worth noting).

### Anti-patterns

- Commented-out code — delete it (git has history).
- Journal/changelog comments — use git log / [CHANGELOG.md](../../CHANGELOG.md).
- Closing-brace comments — refactor into smaller units.

## Review priorities

- 🔴 **CRITICAL** (block): security vulns, logic errors, breaking changes, data loss.
- 🟡 **IMPORTANT** (discuss): missing validation, perf bottlenecks, drift from repo conventions.
- 🟢 **SUGGESTION** (non-blocking): readability, docs.

## Security checklist

- No passwords, API keys, tokens, or PII in code or logs (this repo resolves secrets at deploy time
  and uses Bastion-only access — keep it that way).
- Validate inputs at boundaries; never string-concatenate into shell/SQL.
- Prefer managed identity over keys; TLS 1.2+ minimum.

## Project context

- **IaC**: Azure Bicep under `infra/bicep/`. **Scripts**: bash (`scripts/`), PowerShell (vendored + owned `workloads/`).
- **CI**: [.github/workflows/validate.yml](../workflows/validate.yml) — `az bicep build`/`lint`, `shellcheck`, and `./scripts/validate-skills.sh`.
- **Style**: Conventional Commits; LF line endings; ASCII in workflow YAML.
