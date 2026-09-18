# shared-agent-skills

A single-source repository of Agent Skills shared across **multiple AI tools** (WorkBuddy(CodeBuddy) / OpenAI Codex / Claude Code, etc.).

All tools adopt the [OpenAI / Anthropic common Agent Skills standard](https://agentskills.io) (one directory per skill + `SKILL.md` + YAML frontmatter). Therefore this repository **stores one copy of standard skills with no format conversion**, and distributes skills to each tool's skills directory via symlinks, achieving "change in one place, take effect everywhere."

> Built-in support for agents that adopt the OpenAI Agent Skills standard, including Claude Code, Cline, CodeBuddy, OpenAI Codex, Continue, GitHub Copilot, Cursor, Gemini CLI, Goose, Hermes, Kilo Code, Kimi, OpenClaw, OpenCode, Qoder, Trae, Windsurf, WorkBuddy, and Zed. Several agents (e.g. Pi) also share the common `~/.agents/skills` directory, linked via the generic `agents` target — install with `bash install.sh --tool agents`. To add another agent, append one line to `agents.cfg` (see "Extending Supported Tools" below).

## Repository Structure

```
shared-agent-skills/
├── README.md          # This file
├── SKILL_SPEC.md      # SKILL authoring spec (field conventions, compatibility, validation)
├── CONTRIBUTING.md    # Contribution workflow (creating skills, commit conventions)
├── agents.cfg         # Agent targets supported by the install scripts (name|ENV_VAR|DEFAULT_DIR)
├── hooks.cfg          # Agents with a verified startup-hook config (name|SETTINGS_FILE|NEEDS_MATCHER)
├── install.sh         # Symlink sync script for macOS/Linux (install / uninstall / validate / list tools / --hook)
├── install.ps1        # Equivalent sync script for Windows (install / uninstall / validate / list tools / --hook)
├── hooks/
│   └── auto-update.sh # Wrapper invoked by the startup hook (git pull --ff-only && install.sh)
├── tools/
│   ├── validate.sh    # Standalone validation script for macOS/Linux (local + CI)
│   └── validate.ps1   # Equivalent validation script for Windows (local + CI)
└── skills/            # Single source of all shared skills
    ├── _template/                 # Template for new skills
    ├── example-doc-review/        # Example 1: pure documentation type
    └── example-git-workflow/      # Example 2: script-backed type
        └── scripts/helpers.sh
```

## Skill Catalog

The shared skills currently included in this repository:

- `example-doc-review` — structured review of Markdown / technical documentation.
- `example-git-workflow` — Git workflow helpers (branch naming validation, pre-commit checks, commit message generation).

## Quick Start

### 1. Get the Repository

```bash
git clone <repo URL> shared-agent-skills
cd shared-agent-skills
```

### 2. Install (Symlink to Each Tool)

**macOS / Linux:**

```bash
bash install.sh              # Link to all recognized tool directories
bash install.sh --tool claude   # Only a specific tool (can repeat --tool multiple times)
bash install.sh --claude        # Convenience alias for any configured agent (e.g. --cursor, --gemini, --windsurf)
bash install.sh --list-tools    # List currently supported agents and their default directories
```

**Windows (PowerShell):** the same flags apply to `install.ps1`. On Windows, skills are linked via **Directory Junctions** (no administrator rights required in most setups). If junction creation fails due to policy, run PowerShell as Administrator or enable "Developer Mode" (Settings → Privacy & security → For developers).

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
powershell -ExecutionPolicy Bypass -File install.ps1 --tool claude
powershell -ExecutionPolicy Bypass -File install.ps1 --claude
powershell -ExecutionPolicy Bypass -File install.ps1 --list-tools
```

Default target directories (overridable via environment variables; see `--list-tools` for details):

| Tool | Default skills directory | Override env var |
|------|------------------|--------------|
| Claude Code | `~/.claude/skills` | `CLAUDE_SKILLS_DIR` |
| Cline | `~/.cline/skills` | `CLINE_SKILLS_DIR` |
| CodeBuddy | `~/.codebuddy/skills` | `CODEBUDDY_SKILLS_DIR` |
| OpenAI Codex | `~/.codex/skills` | `CODEX_SKILLS_DIR` |
| Continue | `~/.continue/skills` | `CONTINUE_SKILLS_DIR` |
| GitHub Copilot | `~/.github/skills` | `COPILOT_SKILLS_DIR` |
| Cursor | `~/.cursor/skills` | `CURSOR_SKILLS_DIR` |
| Gemini CLI | `~/.gemini/skills` | `GEMINI_SKILLS_DIR` |
| Goose | `~/.config/agents/skills` | `GOOSE_SKILLS_DIR` |
| Hermes | `~/.hermes/skills` | `HERMES_SKILLS_DIR` |
| Kilo Code | `~/.kilo-code/skills` | `KILO_SKILLS_DIR` |
| Kimi | `~/.kimi/skills` | `KIMI_SKILLS_DIR` |
| OpenClaw | `~/.openclaw/skills` | `OPENCLAW_SKILLS_DIR` |
| OpenCode | `~/.config/opencode/skills` | `OPENCODE_SKILLS_DIR` |
| Agents (shared) | `~/.agents/skills` | `AGENTS_SKILLS_DIR` |
| Qoder | `~/.qoder/skills` | `QODER_SKILLS_DIR` |
| Trae | `~/.trae/skills` | `TRAE_SKILLS_DIR` |
| Windsurf | `~/.windsurf/skills` | `WINDSURF_SKILLS_DIR` |
| WorkBuddy | `~/.workbuddy/skills` | `WORKBUDDY_SKILLS_DIR` |
| Zed | `~/.agents/skills` | `ZED_SKILLS_DIR` |

> **Shared skills directory:** `~/.agents/skills` (user-level) and `.agents/skills` (project-level) are a common convention adopted by many tools — including OpenAI Codex, Zed, Goose, Cursor, Amp, OpenCode, GitHub Copilot, Gemini CLI, OpenClaw, Factory, and Pi. The **`Agents (shared)`** row above is the generic `agents` target: a single `bash install.sh --tool agents` links your skills into `~/.agents/skills` and is picked up by all of them at once. (Claude Code, Cline, and Qoder use their own private directories instead, so they keep separate rows.)

Installation is **idempotent**: repeated runs are safe; already-correctly-linked skills are skipped automatically; it only manages links pointing to this repository and will not delete your self-built skills.

### Coexisting with Existing Private Skills

The symlinks from this repository **will not replace, clean up, or overwrite** your existing private skills; the two can coexist peacefully:

- Private skills with no name conflict: kept as-is in directories like `~/.claude/skills/`, loaded normally by the tool, independent of repo skills.
- On name conflict (repo skill shares a name with your private skill): the script adopts a **"private-first"** strategy — keeps your private version, skips linking, and warns with `⚠` in the output. In this case the repo version will not load. To enable the repo version, first move/rename your private directory, then re-run the install script (`bash install.sh` or `install.ps1`).
- Uninstall (`--uninstall`) only removes links pointing to this repository; it never touches your private skills.

### 3. Update

After the repository is updated, simply re-run `bash install.sh` (symlinks always point to the latest source files; no need to re-pull links).

### 4. Uninstall

```bash
bash install.sh --uninstall            # Remove all
bash install.sh --uninstall --tool claude  # Remove only a tool's links
```

### 6. Auto-update Hook (optional)

You can have each agent automatically pull the latest repo and re-link skills on every session start, instead of re-running `install.sh` by hand after each `git pull`. A small startup hook does:

```bash
git pull --ff-only && bash install.sh   # via hooks/auto-update.sh
```

The hook is non-blocking: pull/install failures (offline, no remote) never stop the session.

The startup hook is managed by `install.sh` / `install.ps1` itself (as subcommands); `hooks.cfg` declares which agents are supported:

```bash
bash install.sh --hook                   # add the startup hook to every supported agent
bash install.sh --hook --tool claude     # only a specific agent (repeatable: --tool <agent>)
bash install.sh --unhook                 # remove the hook from every supported agent
bash install.sh --unhook --tool claude   # remove the hook from a specific agent
bash install.sh --hook-list              # list agents with a verified startup-hook config
```

```powershell
# Windows (PowerShell) — install.ps1 supports the same hook subcommands:
powershell -ExecutionPolicy Bypass -File install.ps1 --hook                  # add to every supported agent
powershell -ExecutionPolicy Bypass -File install.ps1 --hook --tool codebuddy # only a specific agent
powershell -ExecutionPolicy Bypass -File install.ps1 --unhook                # remove from every supported agent
powershell -ExecutionPolicy Bypass -File install.ps1 --hook-list             # list supported agents
```

> **Uninstall matching note (important):** `--hook` / `--unhook` write and match the `command` as this repo's **absolute path** (`$REPO_ROOT/hooks/auto-update.sh`); `remove` matches by that exact string. Therefore you must run `--unhook` from the **same repository checkout that originally installed the hook** for it to match and be removed; if the repo was renamed, moved to a different path, or you run it from another copy, it prints `startup hook not found (skipped)` and removes nothing (the settings file stays unchanged). In that case, just delete the `hooks.SessionStart` entry from the corresponding settings file manually (the script writes a `.bak` backup before editing). Note: both `install.sh` and `install.ps1` store the path with forward slashes, so a hook installed by one can be removed by the other as long as it's the same checkout.

Supported agents (and their hook/settings files) are declared in `hooks.cfg` at the repo root — one line per agent in the form `name|SETTINGS_FILE|NEEDS_MATCHER|FORMAT`. Adding an agent only requires a new line there; no change to the hook logic in `install.sh` / `install.ps1` is needed. Agents that lack a verified startup-hook schema are intentionally skipped (we never write a guessed config that could corrupt an agent we don't understand).

Currently supported (config format verified against each agent's official docs):

| Agent | Hook config file | Schema |
|-------|------------------|--------|
| Claude Code | `~/.claude/settings.json` | `SessionStart` |
| CodeBuddy / WorkBuddy | `~/.codebuddy/settings.json` | `SessionStart` matcher `startup` |
| OpenAI Codex | `~/.codex/hooks.json` | `SessionStart` |
| Gemini CLI | `~/.gemini/settings.json` | `SessionStart` |
| Cursor | `~/.cursor/hooks.json` | `sessionStart` (Cursor-style, top-level `version:1`) |
| Trae | `~/.trae-cn/hooks.json` | `SessionStart` (top-level `version:1`) |

The hook writes a backup (`<file>.bak`) before editing. After adding, verify the hook actually fires with the agent's hook inspector / reload (e.g. CodeBuddy `/hooks`, Codex `/hooks`, Cursor *Developer: Reload Window*, Trae restart).

**Not yet supported** (verified to lack a local session-start shell hook, or use a config we don't yet emit): **Qoder** (its hooks only cover `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `PostToolUseFailure` / `Stop` — there is no `SessionStart`, so a startup auto-update isn't possible; a `Stop` hook would fire after every response, which isn't a meaningful startup update), Cline, Continue, Copilot (cloud-agent hooks are repo-scoped on github.com, not a local startup hook), OpenCode, OpenClaw, Windsurf, Zed, Kilo Code (unverified), Hermes (YAML), Kimi (TOML), Goose (requires a plugin manifest). Add one by appending a verified line to `hooks.cfg` and, if its schema differs from the Claude/Cursor/Trae families, extending the writer in `install.sh` / `install.ps1`.

### 5. Validate

```bash
bash tools/validate.sh       # macOS/Linux: locally validate each SKILL.md one by one
bash install.sh --check      # macOS/Linux: validate only, no linking
powershell -ExecutionPolicy Bypass -File tools/validate.ps1   # Windows: validate each SKILL.md
powershell -ExecutionPolicy Bypass -File install.ps1 --check  # Windows: validate only, no linking
```

## Extending Supported Tools

Supported agents are declared in `agents.cfg` at the repository root — one line per agent in the form `name|ENV_VAR|DEFAULT_DIR`. To support a new agent:

1. Append a line with the agent's identifier, the environment variable that overrides its directory, and its default skills directory:

   ```bash
   gemini|GEMINI_SKILLS_DIR|~/.gemini/skills
   ```

That is the only change required; no edit to `install.sh` is needed. After that, you can install with `bash install.sh --tool gemini` (or the convenience alias `bash install.sh --gemini`), and it will automatically appear in the `--list-tools` list. Any `--<name>` that matches a configured agent works as a shortcut. The skill files themselves need no changes (the standard format is universal).

## Adding a Skill

- **Create from scratch**: start from the template.
  1. Copy the template: `cp -r skills/_template skills/<your-skill-name>`
  2. Fill in `SKILL.md` (follow [SKILL_SPEC.md](./SKILL_SPEC.md)).
  3. Local validation: `bash tools/validate.sh`.
  4. Self-test: after `bash install.sh`, actually trigger it once.
  5. Commit: recommend "one skill per commit", with a message like `feat(skills): add <skill-name>`.
- **Import an existing mature skill**: if you have already built a usable skill in some tool, simply place its directory into `skills/` and adapt it for cross-tool compatibility; see "Importing Existing Skills" in [CONTRIBUTING.md](./CONTRIBUTING.md).

Detailed rules in [CONTRIBUTING.md](./CONTRIBUTING.md).

## Design Highlights

- **Single source, zero conversion**: all tools share the same format; the repository only addresses "different discovery directories."
- **Symlinks instead of copies**: no data duplication, easy rollback; links always point to the latest source.
- **Safety first**: only add/remove links pointing to this repository; no `rm -rf` on user directories; no touching other skills.
- **Multi-tool extensible**: supported tools are declared in one place in `agents.cfg`; adding a tool does not affect existing skills.
- **Cross-tool compatible**: frontmatter uses only the common fields `name`/`description`, without relying on any single tool's proprietary features.

## License

This project is licensed under the [MIT License](./LICENSE).
