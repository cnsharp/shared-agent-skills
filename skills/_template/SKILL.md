---
name: skill-template
description: This is the template for creating new skills in the shared-agent-skills repository. When you want to add a skill shareable across Codex/Claude/etc..., copy this directory and follow its structure. Replace name and description before use.
---

# Skill Template (skill-template)

> This directory is the starting point for new skills. **Copy the entire `_template` directory**, rename it to `skills/<your-skill-name>/`, then fill in the content.

## Directory Structure

```
skills/<skill-name>/
├── SKILL.md        # Required: skill description, with YAML frontmatter (name / description)
├── scripts/        # Optional: scripts used by the skill (e.g. install/helpers)
├── references/     # Optional: reference materials, template files, examples
└── assets/         # Optional: non-text resources such as images
```

## frontmatter Field Conventions

- `name`: lowercase letters, digits and hyphens, globally unique, used as the skill identifier. Example: `example-doc-review`.
- `description`: one sentence stating **when to use the skill**, including trigger keywords where possible, to help each tool discover it automatically.

## Body Writing Style

1. Clearly state the skill's goal, applicable scenarios, and trigger conditions in English.
2. Provide clear steps / workflow.
3. If there are scripts, place them in `scripts/` and reference how to invoke them in the body.
4. Do not rely on any single tool's proprietary fields; ensure cross-tool usability.

## Local Validation

```bash
# Run at the repository root
bash tools/validate.sh
# Windows:
powershell -ExecutionPolicy Bypass -File tools/validate.ps1
```
