---
description: "Prevents terminal heredoc/redirect file corruption in VS Code Copilot by enforcing file-editing tools instead of shell redirections."
applyTo: "scripts/**/*.sh, infra/bicep/**/*.bicep, .github/workflows/*.yml, .github/skills/**/SKILL.md, .github/instructions/**/*.instructions.md, docs/**/*.md, README.md, CHANGELOG.md, ATTRIBUTION.md"
---

# MANDATORY: File Operations Use Editing Tools, Not Heredocs

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/no-heredoc.instructions.md`, retargeted for apex-localops
> (apex's `safe-shell.mjs` linter and `agent-output/` rules removed — they do not exist here).

> [!CAUTION]
> Terminal heredoc/redirect operations (`cat <<EOF`, `echo "..." >`, `printf >`, `tee <<EOF`)
> corrupt files in VS Code Copilot due to tab-completion interference, escape failures, and
> interrupted exit codes. This is a hard technical requirement.

## Rule

When **creating or editing a tracked file**, use the file tools (`create_file`,
`replace_string_in_file`, `multi_replace_string_in_file`) — **never** `cat`, `echo`, `printf`,
`tee`, or `>>`/`>` to write multi-line content.

## Allowed terminal commands

Package management, builds, tests, `git`, `gh`, running scripts, filesystem navigation
(`ls`, `cd`, `mkdir`, `rm`), and downloads (`curl`, `wget` — not piped into files with
content manipulation). Read-only inspection (`cat`, `wc -l`, `head`, `tail`) of existing
files is fine.

## Sub-rule: no heredoc'd code into `node -e` / interpreters

Piping a heredoc into an interpreter is forbidden when the body contains shell-meaningful
constructs (`` `${x}` ``, `${var}`, `$(cmd)`, escape sequences) — the shell expands them first
and you get corruption or `SyntaxError`. Instead, write the script to a temp file with the
file-edit tool, then run it (`node tmp/run-once.mjs`).

## Exception

Generated workflow files (`.github/workflows/*.yml`) legitimately contain heredoc-free
`run:` blocks that themselves call `rsync`/`git`; that shell runs **on the CI runner**, not in
the chat terminal, and is fine. This rule governs how the agent writes files during a chat turn.
