# Instructions

This directory holds [GitHub Copilot custom instruction files](https://code.visualstudio.com/docs/copilot/customization/custom-instructions)
for apex-localops. Each `*.instructions.md` file declares an `applyTo` glob; VS Code auto-attaches
it to chat requests that touch matching files.

These were **adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex/tree/main/.github/instructions)**
and retargeted for this repository: apex-only machinery (npm/Node validators, `agent-output/`,
`AGENTS.md`, governance JSON, Astro `site/`) was removed, examples point at this repo's real tooling
(`az bicep`, `shellcheck`, [validate.yml](../workflows/validate.yml)), and `applyTo` globs are scoped
to **owned** source — vendored trees are excluded.

## Files

| File | applyTo (owned scope) | Purpose |
| --- | --- | --- |
| [shell.instructions.md](shell.instructions.md) | `scripts/**/*.sh` | Bash conventions (safety, quoting, `mktemp`, ShellCheck) |
| [powershell.instructions.md](powershell.instructions.md) | `artifacts/PowerShell/workloads/**` | PowerShell cmdlet style for owned modules (vendored LocalBox excluded) |
| [iac-bicep-best-practices.instructions.md](iac-bicep-best-practices.instructions.md) | `infra/bicep/**/*.bicep` | Bicep naming, secure params, `az bicep` validation |
| [github-actions.instructions.md](github-actions.instructions.md) | `.github/workflows/*.yml` | Workflow pinning (`@v5`), least-privilege, sync-mirror pattern |
| [markdown.instructions.md](markdown.instructions.md) | owned `docs/` + root `*.md` | Doc formatting (vendored mirrors excluded) |
| [code-quality.instructions.md](code-quality.instructions.md) | owned code roots | Comment WHY-not-WHAT, review priorities, security checklist |
| [no-heredoc.instructions.md](no-heredoc.instructions.md) | code + docs | Use file-editing tools, not shell redirects, to write files |
| [no-interactive-shell.instructions.md](no-interactive-shell.instructions.md) | chat-context files | No `-i` prompts / `read -p`; pipe long output to files |
| [instructions.instructions.md](instructions.instructions.md) | `**/*.instructions.md` | How to author instruction files here |
| [agent-skills.instructions.md](agent-skills.instructions.md) | `.github/skills/**/SKILL.md` | SKILL.md conventions + the `azlocal-*`/`aksarc-*`/`sov-*` namespace rule |

## Conventions

- **Scope to owned roots, never `**`.** `applyTo` globs cannot reliably negate, so owned paths are
  enumerated explicitly. Vendored trees are never targeted: `artifacts/PowerShell/` (except
  `workloads/`), `artifacts/sff/vendor/`, `docs/upstream/**`, `docs/azure-local-sff/upstream/**`.
- **Docs-only.** These files are guidance; no new CI gate enforces them. The existing
  [validate.yml](../workflows/validate.yml) covers Bicep, shell, and skills.
