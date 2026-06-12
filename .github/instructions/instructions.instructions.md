---
description: "Guidelines for authoring custom instruction files (.instructions.md) in this repository: frontmatter, applyTo scoping, structure."
applyTo: "**/*.instructions.md"
---

# Custom Instruction File Guidelines

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/instructions.instructions.md`, retargeted for apex-localops.
> See the VS Code
> [custom instructions docs](https://code.visualstudio.com/docs/copilot/customization/custom-instructions)
> for the official reference.

## Frontmatter

```yaml
---
description: "One sentence: what this governs and when it applies."
applyTo: "scripts/**/*.sh"
---
```

| Field | Required | Notes |
| --- | --- | --- |
| `description` | Recommended | 1–500 chars; states purpose + scope |
| `applyTo` | Recommended | Comma-separated glob(s). Without it, the file is manual-attach only |

## applyTo scoping rules (this repo)

- **Scope to owned source roots**, not `**`. Owned: `scripts/`, `infra/bicep/`,
  `artifacts/PowerShell/workloads/`, `.github/workflows/`, `docs/` (owned subset), `.github/skills/`.
- **Never** target vendored trees: `artifacts/PowerShell/` (except `workloads/`),
  `artifacts/sff/vendor/`, `docs/upstream/**`, `docs/azure-local-sff/upstream/**`.
- `applyTo` globs **cannot negate** reliably — enumerate the owned globs explicitly instead of
  excluding with `!`.

## Structure

1. `#` Title + one-line intro.
2. A short provenance blockquote when the file is adapted from another repo.
3. Core sections as **tables and bullets** (scannable), not prose.
4. Good/Bad examples in fenced blocks where useful.
5. A `## Validation` section with the repo's actual commands when one applies.

## Writing rules

| Rule | Detail |
| --- | --- |
| Imperative mood | "Use", "Avoid" — not "you should" |
| Specific | Concrete repo paths/commands over abstractions |
| Current | Reference real tools (`az bicep`, `shellcheck`, `validate.yml`); drop dead refs |
| Concise | Target < 150 lines; push depth into a companion doc if needed |

## Maintenance

Keep globs accurate as the repo evolves. When several instruction files match the same file,
the most specific guidance wins; resolve conflicts by tightening `applyTo`.
