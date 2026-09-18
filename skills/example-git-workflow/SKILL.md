---
name: example-git-workflow
description: Use this skill when the user needs routine Git workflow tasks such as Git branch naming validation, conventional commit message generation, or pre-commit state checks (dirty working tree, unpulled changes).
---

# Git Workflow (example-git-workflow)

## Purpose

Encapsulate common Git workflow operations and provide deterministic scripts to reduce repetitive work and human error: branch naming convention validation, Conventional Commits message generation, and pre-commit state checks.

## Applicable Scenarios

- The user creates a branch and wants it to follow the `type/scope-description` naming convention.
- The user commits code and wants to auto-check the working tree state and generate a Conventional Commits style message.
- The user wants a consistency check before push / PR.

## Workflow

1. **Branch naming validation**: run `scripts/helpers.sh check-branch` to validate whether the current branch name follows the `feat|fix|docs|chore|refactor|test|build/<scope>-<desc>` convention; if not, give a correction suggestion.
2. **Pre-commit check**: run `scripts/helpers.sh precheck` to check for unstaged/uncommitted changes, divergence from upstream, and presence of large files.
3. **Generate commit message**: run `scripts/helpers.sh commit-msg "<change summary>"` to output a suggested `type(scope): summary` message following Conventional Commits, then commit after user confirmation.
4. **Commit**: after confirming the message is correct, run `git add` and `git commit` per the user's intent.

## Resources

- `scripts/helpers.sh`: implementation of the subcommands above, POSIX-compatible (Bash), depending only on `git` and basic tools.

Usage examples:

```bash
bash scripts/helpers.sh check-branch
bash scripts/helpers.sh precheck
bash scripts/helpers.sh commit-msg "Add install symlink script"
```

## Notes

- The script only checks and suggests; it does not auto-run history-rewriting commands (e.g. `git push --force`, `git reset`).
- The generated commit message must be confirmed by the user before the actual commit.
- Do not assume proprietary commands of any specific Git hosting platform (GitHub/GitLab, etc.).
