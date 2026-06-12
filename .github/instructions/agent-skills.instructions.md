---
description: "Guidelines for authoring Agent Skills (SKILL.md) in this repository, matching the jonathan-vella/apex conventions and the local validator."
applyTo: ".github/skills/**/SKILL.md"
---

# Agent Skills File Guidelines

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/agent-skills.instructions.md`, retargeted for apex-localops. These rules
> describe the **custom** skills authored here (`azlocal-*`, `aksarc-*`, `sov-*`); the upstream
> skills mirrored from `microsoft/azure-skills` follow their own format and are not held to this file.

## Required frontmatter

```yaml
---
name: azlocal-deploy
description: "**WORKFLOW SKILL** — <what>. WHEN: \"...\". USE FOR: ... DO NOT USE FOR: ..."
compatibility: Works with Claude Code, GitHub Copilot, VS Code, and any Agent Skills compatible tool.
license: MIT
metadata:
  author: apex-localops
  version: "0.1.0"
  category: azure-local
---
```

| Field | Rule |
| --- | --- |
| `name` | lowercase-hyphen, ≤64 chars, **must match the folder name** |
| `description` | Single-line string, ≤1024 chars. Lead with a skill-type tag, then `WHEN:` + `USE FOR:` / `DO NOT USE FOR:`. Never a YAML block scalar (`>`, `|`) |
| `compatibility` | One-line compatibility statement |
| `license` | `MIT` (a matching `LICENSE.txt` sits in the skill dir) |
| `metadata.category` | `azure-local`, `aks-arc`, or `sovereign-cloud` |

Skill-type tags: `**WORKFLOW SKILL**` (multi-step procedures), `**ANALYSIS SKILL**` (assess /
explain / diagnose), `**UTILITY SKILL**` (shared conventions).

## Custom-skill namespace (MANDATORY)

Custom skills **must** be named `azlocal-*`, `aksarc-*`, or `sov-*`. The weekly
[sync-azure-skills.yml](../workflows/sync-azure-skills.yml) mirror runs `rsync --delete` and
**only** preserves those prefixes via `--exclude` — any other custom name is deleted on the next sync.

## Body structure

```text
# Title
> **AUTHORITATIVE GUIDANCE — MANDATORY COMPLIANCE** (grounding + cite-the-file rule)
## Triggers            (or "When to Use This Skill")
## Prerequisites       (when relevant)
## Rules
## Steps
## References          (canonical Learn URL + related skills)
## Reference Index     ("Load on demand — do NOT read all at once" table → docs/upstream/... links)
```

- Keep `SKILL.md` ≤ 500 lines; put depth in a `references/` subfolder if needed.
- Ground references in the vendored corpus: repo-root-relative `docs/upstream/...` (or
  `docs/azure-local-sff/upstream/...` for SFF). Every referenced path must exist.

## Directory

```text
.github/skills/<name>/
├── SKILL.md       # required
└── LICENSE.txt    # required (MIT)
```

## Validation (CI gate)

```bash
./scripts/validate-skills.sh
```

Enforces: frontmatter (`name`==dir, `description`+`WHEN`, skill-type tag, `compatibility`,
`metadata.category`, `license`), `LICENSE.txt` presence, and that every `docs/upstream/...`
reference resolves. Wired into [.github/workflows/validate.yml](../workflows/validate.yml).
