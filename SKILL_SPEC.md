# Agent Skills Authoring Specification (English)

This repository is the single source of Agent Skills shared across multiple AI tools (OpenAI Codex / Claude Code, etc.).

All skills uniformly adopt the [OpenAI / Anthropic common Agent Skills standard](https://agentskills.io): each skill is a directory containing `SKILL.md` (YAML frontmatter + Markdown body), optionally accompanied by `scripts/`, `references/`, `assets/`.

Because each tool discovers and loads skills according to this standard, this repository performs **no format conversion**; it only addresses the "different discovery directories" problem — distributing via symlinks through `install.sh` (on Windows, use the equivalent `install.ps1`; supported tools are declared in `agents.cfg`).

---

## 1. Directory Structure

```
skills/<skill-name>/
├── SKILL.md        # Required: skill body, with YAML frontmatter (name / description)
├── scripts/        # Optional: deterministic scripts (Bash/Python, etc.)
├── references/     # Optional: reference materials loaded into context on demand
└── assets/         # Optional: resources for output (templates, icons, boilerplate code, etc.)
```

- `scripts/`: Solidify logic that would be repeatedly rewritten or requires deterministic results into scripts, saving tokens and allowing independent execution.
- `references/`: Large (over 10k chars) explanations, schemas, API docs. The body keeps only core steps; details go here, with search/read guidance given in `SKILL.md`.
- `assets/`: Files that don't enter the context but participate in the final output (templates, images, boilerplate projects).

## 2. frontmatter Field Conventions

The top of `SKILL.md` must contain the following fields, and **only use fields common to all tools**, avoiding any tool-specific proprietary fields:

```yaml
---
name: <skill-name>           # Required. Lowercase letters/digits/hyphens, globally unique
description: <when to use>   # Required. Third person, describing capability and trigger scenarios
---
```

### `name`
- Contains only lowercase letters, digits, hyphens (`[a-z0-9-]`).
- Matches the directory name `skills/<skill-name>/` and is unique across the repository.
- Examples: `example-doc-review`, `example-git-workflow`.

### `description`
- Describe in third person **when** the skill is used, embedding trigger keywords to help each tool auto-match.
- Recommended phrasing: `Use this skill when the user needs <scenario/action>.`
- Bad example (too vague, hard to trigger): `A useful documentation skill.`
- Good example: `Use this skill when the user needs to perform a structural or quality review of Markdown / technical documentation (e.g., checking heading hierarchy, terminology consistency, readability).`

## 3. Body Writing Style (English)

- Use **imperative / objective infinitive tone** (e.g., "To complete X, run Y"), not second person (avoid "you should…").
- Suggested structure:
  1. Purpose: one or two sentences describing what the skill does.
  2. Applicable scenarios: clear trigger conditions and out-of-scope boundaries.
  3. Workflow: step-by-step, reusable operation flow.
  4. Resource references: if scripts/references are included, explain their paths and how to invoke them.
  5. Notes: cross-tool compatibility, permissions, rollback, etc.
- Keep the `SKILL.md` body under **5k words**; push detailed material down to `references/`.

## 4. Cross-Tool Compatibility Constraints

To ensure Codex / Claude and all integrated tools load correctly, **you must**:

- Use only the two fields `name` and `description` in frontmatter; do not add other tool-specific fields.
- Do not assume a specific tool's unique commands or paths in the body; if tool-specific differences are needed, document them in `references/`.
- Keep scripts POSIX-compatible (Bash), avoiding macOS/Linux differences; prefer `$HOME` for path concatenation.
- Reference resource paths with relative paths uniformly; do not hardcode absolute paths.

## 5. Validation

`tools/validate.sh` (or `tools/validate.ps1` on Windows) iterates over each skill directory under `skills/` and checks:

- Each skill directory contains `SKILL.md`;
- `SKILL.md` contains valid YAML frontmatter with `name` and `description`;
- `name` contains only `[a-z0-9-]` and matches the directory name.

Local usage:

```bash
bash tools/validate.sh
# Windows:
powershell -ExecutionPolicy Bypass -File tools/validate.ps1
```

In CI, run the same script before commits; missing fields cause a non-zero exit with a prompt.

## 6. New Skill Workflow

See [CONTRIBUTING.md](./CONTRIBUTING.md). Minimal steps: copy `skills/_template/` → rename → fill content → run validation → commit.
