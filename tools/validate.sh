#!/usr/bin/env bash
# validate.sh — Validate that each skill's SKILL.md under skills/ complies with the spec.
# Checks:
#   1. Each skill directory contains SKILL.md
#   2. frontmatter contains valid name / description
#   3. name contains only [a-z0-9-] and matches the directory name
# Exit code: 0 if all pass, otherwise 1. Usable for local validation and CI.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/skills"

if [ ! -d "$SRC_DIR" ]; then
  echo "Skills directory not found: $SRC_DIR" >&2
  exit 1
fi

rc=0
for d in "$SRC_DIR"/*/; do
  d="${d%/}"; base="$(basename "$d")"
  [ "$base" = "_template" ] && continue
  file="$d/SKILL.md"
  if [ ! -f "$file" ]; then
    echo "✗ Missing SKILL.md: $d" >&2; rc=1; continue
  fi
  head="$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$file")"
  name="$(printf '%s\n' "$head" | grep -i '^name:' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
  desc="$(printf '%s\n' "$head" | grep -i '^description:' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
  if [ -z "$name" ]; then echo "✗ Missing name: $file" >&2; rc=1; fi
  if [ -z "$desc" ]; then echo "✗ Missing description: $file" >&2; rc=1; fi
  if [ -n "$name" ] && ! printf '%s' "$name" | grep -Eq '^[a-z0-9-]+$'; then
    echo "✗ Invalid name (only lowercase letters/digits/hyphens): $name" >&2; rc=1
  fi
  if [ -n "$name" ] && [ "$name" != "$base" ]; then
    echo "✗ name($name) does not match directory name($base)" >&2; rc=1
  fi
  if [ "$rc" -eq 0 ]; then echo "✓ $base"; fi
done

if [ "$rc" -eq 0 ]; then
  echo "All skills validated."
else
  echo "Some validation checks failed; please fix per SKILL_SPEC.md." >&2
fi
exit "$rc"
