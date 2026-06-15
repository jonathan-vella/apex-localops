# Contributing to apex-localops

Thanks for your interest in contributing. This project is a **draft release** under active
development, so contributions — bug reports, doc fixes, and pull requests — are welcome. This
guide covers the conventions that keep the repository consistent and the CI green.

By participating, you agree that your contributions are licensed under the repository's
[CC BY 4.0 license](LICENSE).

## Ways to contribute

- **Report a bug or a docs issue** using the
  [issue templates](https://github.com/jonathan-vella/apex-localops/issues/new/choose).
- **Report a security vulnerability** privately — see [SECURITY.md](SECURITY.md). Do not open a
  public issue for security problems.
- **Open a pull request** for a fix or improvement.

## Prerequisites

- **Azure CLI** 2.65 or later with the Bicep extension (`az bicep upgrade`).
- A **bash** shell. The repository ships a dev container with Git, the Azure CLI, and the
  GitHub CLI preinstalled.
- For the docs lint step, **Node.js** (used via `npx`); it is not required for most changes.

## Repository layout

| Path | What it is |
| --- | --- |
| [infra/bicep/](infra/bicep/) | Owned Bicep templates, one folder per profile. |
| [scripts/](scripts/) | Owned bash deployment, monitoring, and helper scripts. |
| [artifacts/](artifacts/) | In-VM automation. Mix of owned and vendored — see below. |
| [docs/](docs/) | Owned documentation (per-profile subfolders, hub, glossary). |
| [.github/](.github/) | Workflows, skills, instructions, and issue templates. |

### Vendored, read-only content — do not edit directly

Some trees are mirrors of upstream projects, kept in sync automatically or pinned to a commit.
Editing them directly will be overwritten or will break provenance. **Do not modify:**

- `docs/upstream/**` and `docs/azure-local-sff/upstream/**` — synced from Microsoft docs.
- `artifacts/sff/vendor/**` — vendored from `Azure-Samples/AzureLocal`.
- The Arc Jumpstart LocalBox artifacts vendored under `artifacts/` — derived from
  `microsoft/azure_arc`.

If a change is needed there, fix it upstream and re-sync, or change the owned file that
references it. See [ATTRIBUTION.md](ATTRIBUTION.md) for exact sources and pinned commits.

## Validate your changes locally

CI runs the [`validate`](.github/workflows/validate.yml) workflow on every push and pull
request. Run the relevant checks before you open a PR:

```bash
# Bicep: build + lint (per profile)
az bicep build --file infra/bicep/azlocal-js/main.bicep --stdout > /dev/null
az bicep lint  --file infra/bicep/azlocal-js/main.bicep

# Shell: syntax + lint
bash -n scripts/<your-script>.sh
shellcheck scripts/<your-script>.sh

# Skills: frontmatter + reference integrity
./scripts/validate-skills.sh

# Docs: markdown lint + relative-link check (requires Node via npx)
npx --yes markdownlint-cli2 "docs/**/*.md" "README.md" "CHANGELOG.md" "ATTRIBUTION.md"
```

> [!NOTE]
> CI does not run live Azure deployments. Where possible, validate a template change with
> `./scripts/deploy*.sh --what-if-only` against a scratch resource group.

## Documentation conventions

Owned docs follow the standards in
[.github/instructions/markdown.instructions.md](.github/instructions/markdown.instructions.md):

- A single H1 title, ATX headings, and fenced code blocks with a language.
- Task-based structure: **Prerequisites → numbered steps → Next steps**.
- GitHub alerts (`[!NOTE]`, `[!IMPORTANT]`, `[!WARNING]`, `[!TIP]`) for callouts.
- Relative links between docs; keep them current when files move.
- First use of an acronym links to the [glossary](docs/glossary.md).

Vendored doc mirrors are excluded from these rules — do not edit them.

## Pull request checklist

- [ ] The change is scoped and does not touch vendored, read-only trees.
- [ ] Relevant CI checks pass locally (Bicep, shell, skills, docs).
- [ ] Docs are updated for any user-facing change.
- [ ] A bullet is added under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
- [ ] No secrets (passwords, tokens, subscription IDs) are committed.

## Commit and branch hygiene

- Keep commits focused; write clear, imperative commit messages.
- Keep `main` green — do not merge changes that fail `validate`.
- Avoid force-pushing shared branches and never bypass CI safety checks.
