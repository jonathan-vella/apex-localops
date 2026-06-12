---
description: "Shell scripting best practices and conventions for bash scripts in this repo (scripts/)."
applyTo: "scripts/**/*.sh"
---

# Shell Scripting Guidelines

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/shell.instructions.md`, retargeted for apex-localops.
> Scope is `scripts/**` (owned). Vendored shell under `artifacts/sff/vendor/` is left as-is.

## Quick reference

| Rule | Standard |
| --- | --- |
| Shebang | `#!/usr/bin/env bash` |
| Safety | `set -euo pipefail` immediately after the shebang |
| Variables | Double-quote: `"$var"`; use `${var}` for clarity; avoid `eval` |
| Cleanup | `trap 'rm -rf "$tmp"' EXIT` for temp files/resources |
| Temp files | `mktemp` / `mktemp -d` — never hardcode `/tmp/x` paths |
| JSON | Use `jq`; fail fast if missing (`command -v jq`) |
| Conditionals | `[[ ]]` (this repo is bash, not POSIX sh) |
| Lint | Must pass `shellcheck` at `--severity=warning` (CI gate) |

## Script structure

- Header comment explaining purpose.
- `set -euo pipefail` right after the shebang.
- `trap cleanup EXIT` for resource teardown.
- Default variables at top; functions next; `main` invoked at the bottom.
- Validate required parameters/inputs before doing work; clear `echo` status, not noisy logging.

## Argument parsing

Use `while [[ $# -gt 0 ]]; do case $1 in ... esac; shift; done` with a `-h|--help` branch
and a `usage()` function.

## Portability

Do not hard-depend on non-default CLIs (`rg`, `fd`, `bat`). Guard optional tools:
`command -v rg >/dev/null && rg ... || grep -R ...`. The Azure CLI (`az`), `jq`, `git`,
and `gh` are available in this devcontainer.

## Validation

```bash
bash -n scripts/<name>.sh          # syntax
shellcheck scripts/<name>.sh        # same gate as .github/workflows/validate.yml
```

## Patterns to avoid

| Anti-pattern | Solution |
| --- | --- |
| Missing `set -euo pipefail` | Add it immediately after the shebang |
| Unquoted `$var` | Quote: `"$var"` |
| Hardcoded `/tmp/foo` | `mktemp`/`mktemp -d` + `trap` cleanup |
| Parsing JSON with `grep`/`awk` | Use `jq` |
| Bare `rg`/`fd` in committed scripts | Guard with `command -v` + fallback |
