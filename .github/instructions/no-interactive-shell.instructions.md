---
description: "Prevents interactive shell prompts and long-output terminal replays from being injected into chat. Forbids -i flags on mv/rm/cp, read -p, and confirm prompts; pipe long output to files."
applyTo: ".github/skills/**/SKILL.md, .github/instructions/**/*.instructions.md, scripts/**/*.sh, README.md, docs/**/*.md"
---

# MANDATORY: No Interactive Shell, No Long-Output Replay

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/no-interactive-shell.instructions.md`, retargeted for apex-localops
> (apex's `safe-shell.mjs`, `apex-recall`, and `agent-output/` references removed).

> [!CAUTION]
> Interactive shell prompts (`mv -i`, `rm -i`, `cp -i`, `read -p`, confirm dialogs) and
> long-output terminal replays bloat the chat transcript and re-inject 50+ lines into every
> subsequent turn.

## Rule 1 — No interactive flags

Never use `mv -i`, `rm -i`, `cp -i`, `read -p`, or any prompt-driven builtin (including inside
`bash -c '...'`).

| Forbidden | Use instead |
| --- | --- |
| `mv -i src dst` | `mv -f src dst` |
| `rm -i path` | `rm -f path` (or let the user delete) |
| `cp -i src dst` | `cp -f src dst` |
| `read -p "Continue? " ans` | Use the `vscode_askQuestions` tool |

If the user genuinely needs to confirm, use `vscode_askQuestions` — never an interactive shell prompt.

## Rule 2 — Pipe long output to a file

For commands likely to exceed ~50 lines, redirect to a file and report only the line count:

```bash
my-cmd > /tmp/my-cmd.out 2>&1 && echo "wrote /tmp/my-cmd.out ($(wc -l </tmp/my-cmd.out) lines)"
```

### Azure CLI output budget

`az` returns large JSON by default. Prefer:

| Goal | Recipe |
| --- | --- |
| Fire-and-check | `az <cmd> --output none && echo OK` |
| Single field | `az <cmd> --query "<jmespath>" --output tsv` |
| Full capture | `az <cmd> > /tmp/<name>.json && wc -l /tmp/<name>.json` |

## Rule 3 — Command portability

Do not hard-depend on non-default CLIs (`rg`, `fd`, `bat`) in committed snippets. Guard them:
`command -v rg >/dev/null && rg ... || grep -R ...`. Stdlib (`grep -R`, `find`) is always fine.

## Why

A runtime `mv -i` that hangs waiting for input dumps its prompt into the transcript and replays
every turn. This file is the control; there is no linter here, so discipline matters.
