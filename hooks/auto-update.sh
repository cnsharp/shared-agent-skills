#!/usr/bin/env bash
# auto-update.sh — bootstrap hook invoked by an agent's SessionStart event.
#
# Pulls the latest shared-agent-skills repo (fast-forward only) and re-runs
# install.sh to re-link skills. Designed to be safe: it never blocks the
# agent session, and failures (offline, no remote, detached HEAD) are ignored.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 0

# Fast-forward pull; tolerate failures (offline / no upstream / detached).
git pull --ff-only >/dev/null 2>&1 || true

# Re-link skills into each agent's directory (idempotent, repo-safe).
bash "$REPO_ROOT/install.sh" >/dev/null 2>&1 || true

exit 0
