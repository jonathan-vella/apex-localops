#!/usr/bin/env bash
# Validates this repo's hand-authored skills (the azlocal-*, aksarc-*, sov-*
# namespaces). Two checks:
#   1. Frontmatter schema — each SKILL.md has a valid YAML frontmatter block with
#      name (matching its folder), a description containing a WHEN clause, and a
#      license.
#   2. Reference integrity — every docs/upstream/... path referenced by a custom
#      skill resolves to a file that actually exists, so an upstream rename can't
#      silently rot a skill's grounding links.
#
# Scope is deliberately limited to the custom namespaces: the upstream-synced
# skills (mirrored from microsoft/azure-skills) follow their own conventions and
# must not fail this repo's CI when their format drifts.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

skills_dir=".github/skills"
fail=0
checked=0

err() { printf '::error::%s\n' "$*" >&2; fail=1; }

# Collect custom skill folders by reserved prefix.
shopt -s nullglob
custom_dirs=()
for prefix in azlocal- aksarc- sov-; do
  for d in "$skills_dir/$prefix"*/; do
    custom_dirs+=("${d%/}")
  done
done
shopt -u nullglob

if [[ ${#custom_dirs[@]} -eq 0 ]]; then
  echo "No custom skills (azlocal-*/aksarc-*/sov-*) found under $skills_dir — nothing to validate."
  exit 0
fi

for dir in "${custom_dirs[@]}"; do
  name="$(basename "$dir")"
  skill="$dir/SKILL.md"
  checked=$((checked + 1))

  if [[ ! -f "$skill" ]]; then
    err "$name: missing SKILL.md"
    continue
  fi

  # Extract the frontmatter block (between the first two '---' fences).
  if [[ "$(sed -n '1p' "$skill")" != "---" ]]; then
    err "$name: SKILL.md must start with a '---' YAML frontmatter fence"
    continue
  fi
  fm="$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$skill")"

  fm_name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n1 | tr -d '"'"'"' \r')"
  [[ -n "$fm_name" ]] || err "$name: frontmatter missing 'name:'"
  [[ "$fm_name" == "$name" ]] || err "$name: frontmatter name '$fm_name' does not match folder '$name'"

  if ! printf '%s\n' "$fm" | grep -q '^license:[[:space:]]*'; then
    err "$name: frontmatter missing 'license:'"
  fi

  # apex convention: a compatibility line and a metadata.category are required.
  if ! printf '%s\n' "$fm" | grep -q '^compatibility:[[:space:]]*'; then
    err "$name: frontmatter missing 'compatibility:'"
  fi
  if ! printf '%s\n' "$fm" | grep -qE '^[[:space:]]+category:[[:space:]]*'; then
    err "$name: frontmatter missing 'metadata.category:'"
  fi

  if ! printf '%s\n' "$fm" | grep -q '^description:[[:space:]]*'; then
    err "$name: frontmatter missing 'description:'"
  else
    # apex convention: description must declare a skill type and a WHEN clause.
    if ! printf '%s\n' "$fm" | grep -qE '\*\*(WORKFLOW|ANALYSIS|UTILITY) SKILL\*\*'; then
      err "$name: description must start with a skill-type tag (**WORKFLOW SKILL**, **ANALYSIS SKILL**, or **UTILITY SKILL**)"
    fi
    if ! printf '%s\n' "$fm" | grep -q 'WHEN'; then
      err "$name: description should include a WHEN clause of trigger phrases"
    fi
  fi

  # apex convention: each skill dir SHOULD ship a LICENSE.txt.
  if [[ ! -f "$dir/LICENSE.txt" ]]; then
    err "$name: missing LICENSE.txt"
  fi

  # Reference integrity: every docs/upstream/... path must exist.
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    target="${ref%%#*}"          # strip any #anchor
    # Only validate concrete file/dir references; skip prose globs/partials
    # (e.g. "docs/upstream/.../foo-*.md" is captured up to the '*').
    case "$target" in
      *.md|*.yml|*.yaml|*/) : ;;
      *) continue ;;
    esac
    if [[ ! -e "$target" ]]; then
      err "$name: broken reference to '$ref' (no such file: $target)"
    fi
  done < <(grep -rhoE 'docs/upstream/[A-Za-z0-9._/-]+' "$dir" | sort -u)
done

if [[ "$fail" -ne 0 ]]; then
  echo "Skill validation FAILED."
  exit 1
fi

echo "Skill validation passed: $checked custom skill(s) OK."
