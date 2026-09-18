#!/usr/bin/env bash
# helpers.sh — Helper script for the example-git-workflow skill (POSIX/Bash, depends only on git).
# Subcommands:
#   check-branch            Validate that the current branch name follows the naming convention
#   precheck                Pre-commit state check (dirty working tree / divergence / large files)
#   commit-msg "<summary>"  Output a suggested commit message following Conventional Commits

set -u

BRANCH_RE='^(feat|fix|docs|chore|refactor|test|build)/[a-z0-9._-]+-[a-z0-9._-]+$'

check_branch() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ -z "$branch" ]; then echo "✗ Not inside a git repository"; return 1; fi
  if printf '%s' "$branch" | grep -Eq "$BRANCH_RE"; then
    echo "✓ Valid branch name: $branch"
  else
    echo "✗ Invalid branch name: $branch"
    echo "  Convention: <type>/<scope>-<desc>"
    echo "  type ∈ {feat,fix,docs,chore,refactor,test,build}"
    echo "  Example: feat/install-symlink-script"
    return 1
  fi
}

precheck() {
  local rc=0
  # Dirty working tree
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "⚠ Uncommitted changes present:"
    git status --porcelain | sed 's/^/    /'
    rc=1
  else
    echo "✓ Working tree clean"
  fi
  # Divergence from upstream
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    local ahead behind
    ahead="$(git rev-list --count @{u}..HEAD 2>/dev/null)"
    behind="$(git rev-list --count HEAD..@{u} 2>/dev/null)"
    [ "${ahead:-0}" -gt 0 ] && echo "⚠ Ahead of upstream by $ahead commit(s) (not pushed)" && rc=1
    [ "${behind:-0}" -gt 0 ] && echo "⚠ Behind upstream by $behind commit(s) (suggest pulling first)" && rc=1
    [ "${ahead:-0}" -eq 0 ] && [ "${behind:-0}" -eq 0 ] && echo "✓ In sync with upstream"
  fi
  # Large file detection (>1MB untracked/modified files)
  local big
  big="$(git status --porcelain 2>/dev/null | awk '{print $2}' | while read -r f; do
    [ -f "$f" ] || continue
    sz="$(wc -c <"$f" 2>/dev/null || echo 0)"
    if [ "$sz" -gt 1048576 ]; then echo "$f ($((sz/1024))KB)"; fi
  done)"
  if [ -n "$big" ]; then echo "⚠ Large file(s) detected (>1MB); confirm whether to add to .gitignore:"; printf '%s\n' "$big" | sed 's/^/    /'; rc=1; fi
  return "$rc"
}

commit_msg() {
  local summary="$1"
  if [ -z "$summary" ]; then echo "Usage: helpers.sh commit-msg \"<change summary>\"" >&2; return 1; fi
  local type="chore"
  case "$summary" in
    feat*:*|add*:*|new*:*) type="feat" ;;
    fix*:*|repair*:*) type="fix" ;;
    docs*:*|doc*:*) type="docs" ;;
    refactor*:*) type="refactor" ;;
    test*:*) type="test" ;;
    build*:*) type="build" ;;
    chore*:*) type="chore" ;;
  esac
  printf '%s: %s\n' "$type" "$summary"
}

case "${1:-}" in
  check-branch) check_branch ;;
  precheck) precheck ;;
  commit-msg) shift; commit_msg "$*" ;;
  *) echo "Unknown subcommand: ${1:-<empty>}"; echo "Available: check-branch | precheck | commit-msg \"<summary>\""; exit 1 ;;
esac
