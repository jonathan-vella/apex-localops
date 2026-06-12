---
description: "Markdown documentation standards for owned docs (docs/ and root *.md). Vendored mirrors are excluded."
applyTo: "docs/*.md, docs/plans/**/*.md, docs/azure-local-sff/README.md, docs/upstream/README.md, README.md, CHANGELOG.md, ATTRIBUTION.md"
---

# Markdown Documentation Standards

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/markdown.instructions.md`, retargeted for apex-localops.
> Scope is **owned** docs only. Vendored mirrors (`docs/upstream/**` except its README,
> `docs/azure-local-sff/upstream/**`) are read-only and intentionally excluded.

## General

- ATX-style headings (`##`, `###`). Use a single H1 (`#`) as the document title.
- LF line endings (enforced by [.gitattributes](../../.gitattributes) for many trees).
- Meaningful link text and image alt text.
- Wrap prose at a sensible width (~100–120 chars). **Not** CI-enforced here — readability over a hard cap.

## Content structure

| Element | Rule |
| --- | --- |
| Headings | `##` H2 top-level within sections; avoid H4+ |
| Lists | `-` for unordered, `1.` for ordered |
| Code blocks | Fenced with a language (never bare ```` ``` ````) |
| Links | Descriptive text + valid relative/absolute URLs |
| Tables | Header row + aligned columns |

## File references

Link files with workspace-relative paths, e.g. `[validate.yml](.github/workflows/validate.yml)`.
Keep links current when files move.

## Diagrams

Use fenced ```mermaid blocks for inline diagrams (the repo already uses Mermaid in docs). No
draw.io / python-diagrams tooling is set up here.

## Patterns to avoid

| Anti-pattern | Solution |
| --- | --- |
| Deep nesting (H4+) | Restructure content |
| Bare code fences | Specify the language |
| "Click here" links | Use descriptive link text |
| Editing vendored mirrors | Change upstream + re-sync, or edit the owned doc that references it |

## Validation

No markdown linter runs in CI today ([validate.yml](../workflows/validate.yml) covers Bicep +
shell + skills). Review manually; if a linter is added later, wire it here.
