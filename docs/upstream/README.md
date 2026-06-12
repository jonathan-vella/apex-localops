# Upstream documentation — vendored, read-only mirror

This folder is a **read-only, prose-only mirror** of selected Azure Local and
Microsoft Sovereign Cloud documentation, vendored so this repo's guidance and
skills work offline and stay grounded in the latest Microsoft docs.

> [!IMPORTANT]
> Do **not** edit files under this folder — they are overwritten on every sync.
> The mirror is refreshed by
> [.github/workflows/sync-upstream-docs.yml](../../.github/workflows/sync-upstream-docs.yml)
> (weekly + on demand) via a blobless sparse checkout of the relevant folders.

## What's here

| Folder | Source | Upstream path |
| --- | --- | --- |
| [`azure-local/`](azure-local/) | `MicrosoftDocs/azure-stack-docs` | `azure-local/` (**excluding** `small-form-factor/`) |
| [`azure-local-max/`](azure-local-max/) | `MicrosoftDocs/azure-stack-docs` | `azure-local-max/` |
| [`aksarc/`](aksarc/) | `MicrosoftDocs/azure-stack-docs` | `AKS-Arc/` |
| [`azure-sovereign-clouds/`](azure-sovereign-clouds/) | `MicrosoftDocs/azure-sovereign-clouds` | `articles/` (Azure Local + foundations subset) |

## What's intentionally excluded

- **All media/binaries** (`media/`, `*.png`, `*.jpg`, `*.svg`, `*.pdf`, …). The
  LLM only consumes the markdown/YAML prose; images would add ~221 MB of payload
  the grounding never uses. The mirror is ~9 MB of text instead.
- **Azure Local Small Form Factor** (`small-form-factor/`) — vendored separately
  and pinned at [docs/azure-local-sff/upstream](../azure-local-sff/) to avoid
  double-vendoring.
- **Unrelated `azure-stack-docs` products** — `azure-stack` (Hub),
  `operator-nexus`, `azure-managed-lustre`.
- **Unrelated sovereign products** — Microsoft 365 Local, GitHub Enterprise Local,
  Dataverse / Power Platform, Dynamics 365 Business Central, National Partner Clouds.

## Canonical sources (Microsoft Learn)

| Topic | Learn URL |
| --- | --- |
| Azure Local | <https://learn.microsoft.com/azure/azure-local/> |
| AKS on Azure Local | <https://learn.microsoft.com/azure/aks/aksarc/> |
| Microsoft Sovereign Cloud | <https://learn.microsoft.com/industry/sovereignty/> |

## How this repo uses it

These docs are the **grounding corpus** for the hand-authored Azure Local, AKS on
Azure Local, and Sovereign Cloud skills under
[.github/skills/](../../.github/skills/) (folders prefixed `azlocal-*`, `aksarc-*`,
`sov-*`). Skill `References` sections link into this folder.

## License & attribution

The vendored docs are © Microsoft and licensed **CC BY 4.0** (compatible with this
repo's [LICENSE](../../LICENSE)). Each subfolder carries the upstream `LICENSE`,
`LICENSE-CODE`, and `ThirdPartyNotices.md`. See [ATTRIBUTION.md](../../ATTRIBUTION.md)
for the credit and the pinned upstream commits.
