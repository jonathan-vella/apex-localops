---
description: "Standards for GitHub Actions workflows in this repository: pinning, least-privilege permissions, triggers, and the sync-mirror pattern."
applyTo: ".github/workflows/*.yml, .github/workflows/*.yaml"
---

# GitHub Actions Workflow Standards

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/github-actions.instructions.md`, retargeted for apex-localops
> (apex's Node validators, Astro `site/`, and Node-version rules removed — this repo's CI is
> `az bicep` + `shellcheck`, not npm).

## Conventions

### Runner & permissions

- **Runner**: `ubuntu-latest`.
- **Permissions**: declare least-privilege at the workflow level. Default `contents: read`; add
  `contents: write` only for the sync-mirror workflows that push to `main`.

### Action versions

- Pin to a **major version tag**, not `@main`/`@latest`.
- This repo standardizes on **`actions/checkout@v5`** (all four workflows). Keep new workflows on
  `@v5` for consistency unless deliberately bumping all of them together.

### Triggers

- PR validation: `pull_request` to `main`. Post-merge: `push` to `main`.
- Always include `workflow_dispatch` for on-demand runs.
- Scheduled mirrors use `schedule` cron (existing syncs are offset: 06:00 / 06:30 / 06:45 UTC Mon).

### Naming & structure

- Kebab-case file name; human-readable `name:`; descriptive job/step names.
- Start with a comment block describing purpose + trigger.
- Use a `concurrency` group for sync workflows so a slow run and the next schedule cannot race.

## Existing workflows

| Workflow | Purpose |
| --- | --- |
| `validate.yml` | PR/push gate: Bicep build + lint, shell `bash -n` + ShellCheck, custom skill validation |
| `sync-azure-skills.yml` | Mirror `microsoft/azure-skills` → `.github/skills` (excludes `azlocal-*`/`aksarc-*`/`sov-*`) |
| `sync-azure-local-sff-docs.yml` | Mirror SFF docs → `docs/azure-local-sff/upstream` |
| `sync-upstream-docs.yml` | Mirror Azure Local + Sovereign prose → `docs/upstream` |

## Sync-mirror pattern (when adding another upstream mirror)

- Blobless sparse clone (`--filter=blob:none --sparse`) + `rsync` with media excludes.
- Add a `.gitattributes` `… text=auto eol=lf` rule for the destination so an unchanged upstream is
  a true no-op (CRLF churn lesson — see [.gitattributes](../../.gitattributes)).
- Record the pinned upstream commit in [ATTRIBUTION.md](../../ATTRIBUTION.md).
- `permissions: contents: write` + a `concurrency` group; commit only on change.

## Patterns to avoid

| Anti-pattern | Solution |
| --- | --- |
| `@main` / `@latest` pins | Use a major version tag (`@v5`) |
| Missing `permissions` block | Declare least-privilege explicitly |
| Broad triggers | Scope with `paths:` where it helps |
| Non-ASCII in YAML comments | Keep workflow YAML ASCII (em-dash broke the YAML LSP once) |
