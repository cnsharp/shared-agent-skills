---
name: example-doc-review
description: Use this skill when the user needs to perform a structural, quality, and consistency review of Markdown or technical documentation (e.g., checking heading hierarchy, terminology consistency, readability, link validity).
---

# Document Review (example-doc-review)

## Purpose

Provide a structured review process for technical docs, READMEs, design docs, and specification docs, outputting actionable revision suggestions that improve accuracy, consistency, and readability.

## Applicable Scenarios

- The user submits a document and asks for "review", "check", or "polish".
- The user wants a quality gate before publishing/merging a document.
- The user wants to unify terminology, normalize heading hierarchy, or fix broken links.

## Workflow

1. **Define scope**: confirm whether the review target is a single file, a directory, or a specific section; ask which aspects to focus on (structure / terminology / readability / links).
2. **Structure check**:
   - Whether heading hierarchy is contiguous (no skips, e.g. `#` directly followed by `###`).
   - Whether there are duplicate headings or a missing top-level heading.
   - Whether Markdown syntax for lists, code blocks, and tables is well-formed.
3. **Terminology and consistency**:
   - Whether the same concept uses a consistent translation/spelling (e.g. mixing "skill" and "技能").
   - Whether Chinese/English punctuation, number formats, and units are consistent.
4. **Readability and accuracy**:
   - Whether long sentences can be split, and whether passive voice is overused.
   - Whether example code and commands are runnable, and paths are relative and correct.
5. **Link validation**: check whether relative/anchor links point to valid targets (see `references/checklist.md`).
6. **Produce suggestions**: present as a list of "issue → location → suggestion", sorted by severity (blocking / suggested / optional).

## Resources

- `references/checklist.md`: the review checklist, used for item-by-item verification.

## Notes

- Provide the review as suggestions; do not make large rewrites on your own; confirm major structural changes with the user first.
- Do not assume any tool-specific syntax; keep the document generic and portable.
