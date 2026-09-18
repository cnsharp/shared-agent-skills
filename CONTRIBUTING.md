# Contribution Guide (English)

Welcome to submit skills to `shared-agent-skills` that can be shared across multiple AI tools (Codex / Claude, etc.). This guide explains the complete workflow and conventions from creation to commit.

## Roles and Scope

- **User-level skills**: symlinked via `install.sh` (or `install.ps1` on Windows) into each tool's user-level skills directory (e.g.  `~/.claude/skills`, `~/.codex/skills`; use `bash install.sh --list-tools` — or `install.ps1 --list-tools` on Windows — to see the full list), available in all projects. This repository is the source of this form.
- **Project-level skills**: if you need to share alongside a specific project, you can place them in that project's `.codex/skills/` or `.claude/skills/`; this is outside this repository's scope.

## Steps to Create a Skill

1. **Copy the template**
   ```bash
   cp -r skills/_template skills/<your-skill-name>
   ```
   `<your-skill-name>` contains only lowercase letters, digits, hyphens, and is globally unique.

2. **Fill in `SKILL.md`**
   - Modify the frontmatter `name` (matching the directory name) and `description` (third person, with trigger keywords).
   - Write the English body and resource directories following [SKILL_SPEC.md](./SKILL_SPEC.md) conventions.
   - Delete unneeded example directories (`scripts/`, `references/`, `assets/` kept as needed).

3. **Local validation**
   ```bash
   bash tools/validate.sh
   # Windows: powershell -ExecutionPolicy Bypass -File tools/validate.ps1
   ```
   Validation must pass before committing; fix any failures first.

4. **Self-test (optional but recommended)**
   Run `bash install.sh` (or `install.ps1` on Windows) to link the skill into the local tool directory, trigger it once, and confirm each tool can discover and use it.

## Importing Existing Skills

If you have already built a mature skill in some tool (e.g. `~/.claude/skills/my-skill/`), you can include it directly in this repository for sharing, without rewriting from the template.

1. **Place in repository**
   ```bash
   cp -r ~/.claude/skills/my-skill skills/my-skill
   ```
   The directory name contains only lowercase letters, digits, hyphens, and is globally unique (matching `name`).

2. **Compatibility adaptation**
   - Open `skills/my-skill/SKILL.md` and confirm the frontmatter contains only the two common fields `name` and `description`; remove proprietary fields from the source tool (such as a tool-specific `version`, `license`, `allowed-tools`, etc.) to ensure cross-tool loadability (see Section 4 of [SKILL_SPEC.md](./SKILL_SPEC.md)).
   - Ensure `name` matches the directory name, and `description` is in third person with trigger keywords.
   - Check whether the body hardcodes commands/paths specific to the source tool; if so, change to a generic expression or move into `references/`.

3. **Local validation**
   ```bash
   bash tools/validate.sh
   # Windows: powershell -ExecutionPolicy Bypass -File tools/validate.ps1
   ```
   Validation must pass before committing; fix any failures first.

4. **Self-test (optional but recommended)**
   Run `bash install.sh` (or `install.ps1` on Windows) to link the skill into the local tool directory, trigger it once in the source tool and other integrated tools, and confirm they all load and work correctly.

## Naming and Organization Conventions

- Skill directory / `name`: lowercase hyphenated, semantically clear, e.g. `doc-review`, `git-workflow`.
- One skill solves one clear class of task; do not pile unrelated capabilities into a single skill.
- Put large reference content in `references/`, scripts in `scripts/`, output templates in `assets/`, keeping `SKILL.md` concise.

## Commit Conventions

- One skill per directory; when committing, prefer "one skill per commit" for easier review and rollback.
- Suggested commit message: `feat(skills): add <skill-name> skill` or `fix(skills): fix <skill-name>'s description`.
- Do not commit the symlink files themselves (links are generated locally by `install.sh` / `install.ps1` for each user); the repository keeps only the source.
- After committing, add the skill description to the skill catalog in [README.md](./README.md).

## Review Checklist

Maintainers will look at: whether frontmatter fields are compliant, whether description helps auto-triggering, whether the body meets cross-tool compatibility constraints, and whether any single-tool proprietary content has been mixed in.
