#!/usr/bin/env bash
# install.sh — Symlink the skills under this repo's skills/ into each AI agent's
# (Claude Code / OpenAI Codex / Cursor / Gemini CLI / Windsurf / Cline / Kilo / OpenClaw / Agents (shared ~/.agents/skills) /
# WorkBuddy / CodeBuddy / Hermes, etc.) skills directory.
#
# Design principles:
#   1. Single source, zero conversion: this repo's skills/ is the single source of truth; only symlinks are created, no data copied.
#   2. Idempotent: safe to run repeatedly; already-correctly-linked skills are skipped automatically.
#   3. Safe: only manage links "pointing to this repo's skills/"; never rm -rf user directories.
#      On a name conflict with a non-repo directory, ask interactively (non-interactive/CI defaults to safe skip; only rm -r on explicit user choice).
#   4. Validatable: before linking, check each SKILL.md's frontmatter for name/description.
#   5. Multi-agent extensible: supported agents are declared in agents.cfg (one line per agent:
#      name|ENV_VAR|DEFAULT_DIR). Adding an agent changes only that file.
#   6. Shared hub: ~/.agents/skills (Open Agent Skills standard) is symlinked to this repo's
#      skills/; agents that read it receive public skills automatically and are skipped by the
#      per-agent bridge loop below. Agents that do not read the hub get public skills bridged
#      into their own skills directory (private real subdirs are preserved = mixed mode).
#
# Usage:
#   bash install.sh                 # Link to all configured agent directories
#   bash install.sh --tool claude   # Only a specific agent (can repeat --tool multiple times)
#   bash install.sh --claude        # Convenience alias for any configured agent (e.g. --cursor, --gemini)
#   bash install.sh --list-tools    # List currently supported agents and their default directories
#   bash install.sh --uninstall     # Remove all links created by this repo
#   bash install.sh --check         # Validate frontmatter only, no linking
#   bash install.sh --hook          # Add a startup hook (auto git pull && install.sh) to supported agents
#   bash install.sh --hook --tool codebuddy  # Only a specific agent (can repeat --tool)
#   bash install.sh --unhook        # Remove the startup hook
#   bash install.sh --hook-list     # List agents that support a startup hook

set -u
# Expand path globs that match nothing to nothing (instead of a literal "*"
# path). Without this, an empty skills/ makes `for d in "$SRC_DIR"/*/` iterate
# the literal string "skills/*/", which then fails validation and aborts the
# install/check with a spurious "Validation failed" error.
shopt -s nullglob

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/skills"
AGENTS_CFG="$REPO_ROOT/agents.cfg"

if [ ! -f "$AGENTS_CFG" ]; then
  echo "Agent config not found: $AGENTS_CFG" >&2
  exit 1
fi

# ─────────────────────────────────────────────────────────────
# Agent configuration is data-driven from agents.cfg.
#   list_agents      -> print configured agent names (one per line)
#   tool_info <agent> -> print "ENV_VAR|DEFAULT_DIR"; unknown agent returns 1
# Adding a new agent only requires a new line in agents.cfg.
# ─────────────────────────────────────────────────────────────

list_agents() {
  grep -v '^[[:space:]]*#' "$AGENTS_CFG" | grep -v '^[[:space:]]*$' | cut -d'|' -f1
}

tool_info() {
  local info
  info="$(grep -v '^[[:space:]]*#' "$AGENTS_CFG" | grep -v '^[[:space:]]*$' \
          | awk -F'|' -v a="$1" 'NF>=3 && $1==a {print $2"|"$3; exit}')"
  if [ -n "$info" ]; then printf '%s\n' "$info"; return 0; fi
  return 1
}

# Directories skipped during linking (template + example skills are not
# distributed into any agent's skills directory).
EXCLUDED_DIRS=("_template" "example-doc-review" "example-git-workflow")

# Directories skipped during validation (--check / pre-install). Only the bare
# template is skipped here (its name intentionally differs from its dir name);
# the example skills are real, valid skills and are validated like any other,
# keeping this consistent with tools/validate.sh.
VALIDATE_EXCLUDE=("_template")

SELECTED=()
DO_UNINSTALL=0
DO_CHECK_ONLY=0
DO_LIST_TOOLS=0
DO_HOOK=0
DO_UNHOOK=0
DO_HOOK_LIST=0

# Parse arguments in a single pass so that `--tool <name>` consumes its value immediately.
while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --tool)
      shift
      if [ "$#" -eq 0 ]; then echo "Missing value for --tool" >&2; exit 1; fi
      SELECTED+=("$1"); shift ;;
    --tool=*)
      t="${arg#--tool=}"; SELECTED+=("$t") ;;
    --list-tools) DO_LIST_TOOLS=1; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    --check)    DO_CHECK_ONLY=1; shift ;;
    --hook)      DO_HOOK=1; shift ;;
    --unhook)    DO_UNHOOK=1; shift ;;
    --hook-list) DO_HOOK_LIST=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --*)
      # Any other --<name> is treated as a convenience alias for a configured agent
      cand="${arg#--}"
      if tool_info "$cand" >/dev/null 2>&1; then
        SELECTED+=("$cand")
      else
        echo "Unknown argument: $arg" >&2
        echo "Supported tools: " "$(list_agents)" >&2
        exit 1
      fi
      shift ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Supported tools: " "$(list_agents)" >&2
      exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────
# Startup-hook subcommands: --hook / --unhook / --hook-list
#   Data-driven from hooks.cfg (name|SETTINGS_FILE|NEEDS_MATCHER|FORMAT).
#   Adds/removes a SessionStart hook that runs hooks/auto-update.sh
#   (git pull --ff-only && bash install.sh) at agent startup.
# ─────────────────────────────────────────────────────────────
HOOKS_CFG="$REPO_ROOT/hooks.cfg"
AUTO_UPDATE="$REPO_ROOT/hooks/auto-update.sh"

if [ "$DO_HOOK" -eq 1 ] || [ "$DO_UNHOOK" -eq 1 ] || [ "$DO_HOOK_LIST" -eq 1 ]; then
  if [ ! -f "$HOOKS_CFG" ]; then
    echo "Hook config not found: $HOOKS_CFG" >&2; exit 1
  fi
  if [ ! -f "$AUTO_UPDATE" ]; then
    echo "Auto-update wrapper not found: $AUTO_UPDATE" >&2; exit 1
  fi
  chmod +x "$AUTO_UPDATE" 2>/dev/null || true
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to edit agent settings JSON safely, but it was not found in PATH." >&2; exit 1
  fi

  list_hook_agents() {
    grep -v '^[[:space:]]*#' "$HOOKS_CFG" | grep -v '^[[:space:]]*$' | cut -d'|' -f1
  }
  hook_info() {
    local info
    info="$(grep -v '^[[:space:]]*#' "$HOOKS_CFG" | grep -v '^[[:space:]]*$' \
            | awk -F'|' -v a="$1" 'NF>=3 && $1==a {
                fmt = (NF>=4 && $4!="") ? $4 : "claude";
                print $2"|"$3"|"fmt; exit
              }')"
    if [ -n "$info" ]; then printf '%s\n' "$info"; return 0; fi
    return 1
  }
  expand_path() {
    local p="$1"
    if [ "${p:0:1}" = "~" ]; then
      if [ "$p" = "~" ]; then printf '%s' "$HOME";
      else printf '%s' "$HOME/${p#\~/}"; fi
    else
      printf '%s' "$p"
    fi
  }
  merge_hook_json() {
    local mode="$1" path="$2" cmd="$3" needs="$4" fmt="$5"
    python3 - "$mode" "$path" "$cmd" "$needs" "$fmt" <<'PYEOF'
import json, os, sys

mode, path, cmd, needs, fmt = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

def backup(p):
    if os.path.exists(p):
        try:
            with open(p, "r") as f:
                open(p + ".bak", "w").write(f.read())
        except Exception:
            pass

def load(p):
    if not os.path.exists(p):
        return {}
    try:
        with open(p) as f:
            return json.load(f)
    except Exception as e:
        sys.stderr.write("ERROR: cannot parse JSON at %s: %s\n" % (p, e))
        sys.exit(2)

def write(p, data):
    os.makedirs(os.path.dirname(os.path.abspath(p)), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, p)

if fmt == "cursor":
    event = "sessionStart"
    def handlers_of(group):
        return group.get("hooks", []) if isinstance(group, dict) else []
    def make_group():
        return {"command": cmd}
    def cmd_of(group):
        if isinstance(group, dict):
            return group.get("command")
        return None
else:
    event = "SessionStart"
    def handlers_of(group):
        return group.get("hooks", []) if isinstance(group, dict) else []
    def make_group():
        g = {"hooks": [{"type": "command", "command": cmd}]}
        if needs == "yes":
            g["matcher"] = "startup"
        return g
    def cmd_of(group):
        for h in handlers_of(group):
            if isinstance(h, dict) and h.get("command") == cmd:
                return cmd
        return None

if mode == "add":
    data = load(path)
    if fmt in ("cursor", "trae") and "version" not in data:
        data["version"] = 1
    hooks = data.setdefault("hooks", {})
    groups = hooks.setdefault(event, [])
    for g in groups:
        if cmd_of(g) == cmd:
            print("  · already present (skipped): %s" % path)
            sys.exit(0)
    groups.append(make_group())
    backup(path)
    write(path, data)
    print("  ✓ added startup hook to %s" % path)

elif mode == "remove":
    if not os.path.exists(path):
        print("  · no settings file, nothing to remove: %s" % path)
        sys.exit(0)
    data = load(path)
    hooks = data.get("hooks", {})
    groups = hooks.get(event, [])
    before = len(groups)
    groups = [g for g in groups if cmd_of(g) != cmd]
    removed = before - len(groups)
    if removed == 0:
        print("  · startup hook not found (skipped): %s" % path)
        sys.exit(0)
    if groups:
        hooks[event] = groups
    else:
        hooks.pop(event, None)
    if hooks:
        data["hooks"] = hooks
    else:
        data.pop("hooks", None)
    backup(path)
    write(path, data)
    print("  ✓ removed %d startup hook(s) from %s" % (removed, path))
PYEOF
  }

  if [ "$DO_HOOK_LIST" -eq 1 ]; then
    echo "Agents with a verified startup-hook config (hooks.cfg):"
    for t in $(list_hook_agents); do
      info="$(hook_info "$t")"
      sfile="${info%%|*}"; rest="${info#*|}"; matcher="${rest%%|*}"; fmt="${rest#*|}"
      printf "  %-12s %s  (schema: %s, matcher: %s)\n" "$t" "$sfile" "$fmt" "$matcher"
    done
    exit 0
  fi

  if [ "$DO_HOOK" -eq 1 ] && [ "$DO_UNHOOK" -eq 1 ]; then
    echo "Use either --hook or --unhook, not both." >&2; exit 1
  fi

  declare -a HOOK_SELECTED=()
  if [ "${#SELECTED[@]}" -gt 0 ]; then
    for t in "${SELECTED[@]:-}"; do
      [ -z "$t" ] && continue
      if hook_info "$t" >/dev/null 2>&1; then
        HOOK_SELECTED+=("$t")
      else
        echo "Unsupported hook agent: $t" >&2
        echo "Supported hook agents: $(list_hook_agents | tr '\n' ' ')" >&2
        echo "(Agents not in hooks.cfg are skipped to avoid corrupting unknown configs.)" >&2
        exit 1
      fi
    done
  else
    for t in $(list_hook_agents); do HOOK_SELECTED+=("$t"); done
  fi

  ACTION="add"; [ "$DO_UNHOOK" -eq 1 ] && ACTION="remove"
  VERB="Adding"; [ "$DO_UNHOOK" -eq 1 ] && VERB="Removing"
  echo "$VERB startup hook (runs: git pull --ff-only && bash install.sh)"
  echo "Wrapper: $AUTO_UPDATE"
  echo
  rc=0
  for tool in "${HOOK_SELECTED[@]:-}"; do
    [ -z "$tool" ] && continue
    info="$(hook_info "$tool")"
    sfile="${info%%|*}"; rest="${info#*|}"; needs="${rest%%|*}"; fmt="${rest#*|}"
    spath="$(expand_path "$sfile")"
    echo "→ $tool ($spath)  [schema: $fmt]"
    if ! merge_hook_json "$ACTION" "$spath" "$AUTO_UPDATE" "$needs" "$fmt"; then rc=1; fi
  done
  echo
  if [ "$rc" -eq 0 ]; then
    echo "Done."
    if [ "$DO_HOOK" -eq 1 ]; then
      echo "The hook runs once per agent session start."
      echo "Verify with the agent's hook inspector after restarting the agent."
    fi
  else
    echo "Some operations failed; see messages above." >&2
  fi
  exit "$rc"
fi

# Validate that agent names in SELECTED are supported
for t in "${SELECTED[@]:-}"; do
  [ -z "$t" ] && continue
  if ! tool_info "$t" >/dev/null 2>&1; then
    echo "Unknown tool: $t" >&2
    echo "Currently supported tools: " "$(list_agents)" >&2
    echo "Use --list-tools to see the full list." >&2
    exit 1
  fi
done

# ── --list-tools ──
if [ "$DO_LIST_TOOLS" -eq 1 ]; then
  echo "Currently supported tools:"
  for t in $(list_agents); do
    info="$(tool_info "$t")"
    envvar="${info%%|*}"; def="${info#*|}"
    printf "  %-12s %s (override var: %s)\n" "$t" "$def" "$envvar"
  done
  exit 0
fi

# Expand a leading ~ to $HOME (agents.cfg stores paths with ~).
# Note: Bash does NOT expand ~ inside a variable expansion, so this must be done explicitly.
# We deliberately avoid `case "~/"*` patterns: in bash, case patterns undergo tilde expansion,
# so "~/"* would expand to "$HOME/*" and never match a literal "~/.x" word.
expand_path() {
  local p="$1"
  if [ "${p:0:1}" = "~" ]; then
    if [ "$p" = "~" ]; then
      printf '%s' "$HOME"
    else
      printf '%s' "$HOME/${p#\~/}"
    fi
  else
    printf '%s' "$p"
  fi
}

# Public skills hub (Open Agent Skills standard). Agents whose DEFAULT_DIR equals this
# path receive public skills directly via the hub symlink and are skipped by the per-agent
# bridge loop. Derived from the 'agents' entry's DEFAULT_DIR; defaults to ~/.agents/skills.
_hub_raw="$(tool_info agents 2>/dev/null | cut -d'|' -f3)"
[ -z "$_hub_raw" ] && _hub_raw="~/.agents/skills"
HUB="$(expand_path "$_hub_raw")"

# resolve_target <agent> -> print the agent's skills directory; empty if unrecognized
resolve_target() {
  local info
  info="$(tool_info "$1")" || return 1
  local envvar="${info%%|*}"; local def="${info#*|}"
  local raw="${!envvar:-$def}"
  expand_path "$raw"
}

# Determine whether a link was created by this repo (points under REPO_ROOT/skills)
is_ours() {
  local link="$1"
  [ -L "$link" ] || return 1
  local real
  real="$(readlink "$link" 2>/dev/null || true)"
  case "$real" in
    "$REPO_ROOT/skills/"*) return 0 ;;
    "$SRC_DIR/"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Validate a single skill directory's frontmatter
validate_skill() {
  local dir="$1"; local file="$dir/SKILL.md"
  local base; base="$(basename "$dir")"
  [ -f "$file" ] || { echo "  ✗ Missing SKILL.md: $dir" >&2; return 1; }
  local head
  head="$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$file")"
  local name; name="$(printf '%s\n' "$head" | grep -i '^name:' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
  local desc; desc="$(printf '%s\n' "$head" | grep -i '^description:' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
  if [ -z "$name" ]; then echo "  ✗ Missing name: $file" >&2; return 1; fi
  if [ -z "$desc" ]; then echo "  ✗ Missing description: $file" >&2; return 1; fi
  if ! printf '%s' "$name" | grep -Eq '^[a-z0-9-]+$'; then
    echo "  ✗ Invalid name (only lowercase letters/digits/hyphens): $name" >&2; return 1
  fi
  if [ "$name" != "$base" ]; then
    echo "  ✗ name($name) does not match directory name($base): $file" >&2; return 1
  fi
  return 0
}

# Handle a conflict where the target already exists and is not a repo symlink: ask to delete or skip.
# Returns: 0=delete and link the repo version, 1=skip (keep the original directory)
#   · Non-interactive environment (pipe/CI) defaults to safe skip (no deletion)
#   · After the user inputs 'a', all subsequent conflicts are auto-skipped (same choice applies)
CONFLICT_SKIP_ALL=0
prompt_conflict() {
  local target="$1"
  if [ "$CONFLICT_SKIP_ALL" -eq 1 ]; then
    echo "  · Skipped (reusing previous choice): ${target}" >&2
    return 1
  fi
  if [ ! -t 0 ]; then
    echo "  ⚠ Non-interactive environment, auto-skip (no deletion): ${target}" >&2
    return 1
  fi
  local ans
  while true; do
    printf "  ? Conflict: target already exists and is not a repo symlink directory\n    %s\n    Choose [d] delete and link repo version / [s] skip and keep / [a] skip all : " "${target}" >&2
    if ! read -r ans; then echo "" >&2; return 1; fi
    case "$ans" in
      d|D) return 0 ;;
      s|S|"") return 1 ;;
      a|A) CONFLICT_SKIP_ALL=1; return 1 ;;
      *) echo "    Enter d / s / a" >&2 ;;
    esac
  done
}

# ---- --check mode ----
if [ "$DO_CHECK_ONLY" -eq 1 ]; then
  echo "Validating skill frontmatter under ${SRC_DIR}…"
  rc=0
  for d in "$SRC_DIR"/*/; do
    d="${d%/}"
    base="$(basename "$d")"
    [[ " ${VALIDATE_EXCLUDE[*]} " == *" $base "* ]] && continue
    if validate_skill "$d"; then echo "  ✓ $base"; else rc=1; fi
  done
  [ "$rc" -eq 0 ] && echo "All passed." || echo "Some validation checks failed." >&2
  exit "$rc"
fi

# ---- Collect agent directories to process ----
declare -a ACTIVE_TOOLS
if [ "${#SELECTED[@]}" -eq 0 ]; then
  for t in $(list_agents); do ACTIVE_TOOLS+=("$t"); done
else
  ACTIVE_TOOLS=("${SELECTED[@]}")
fi

# ---- --uninstall mode ----
if [ "$DO_UNINSTALL" -eq 1 ]; then
  echo "Removing symlinks created by this repo…"
  for tool in "${ACTIVE_TOOLS[@]}"; do
    tdir="$(resolve_target "$tool")"
    [ -z "$tdir" ] && continue
    [ -d "$tdir" ] || continue
    for link in "$tdir"/*; do
      [ -e "$link" ] || [ -L "$link" ] || continue
      if is_ours "$link"; then
        rm -f "$link" && echo "  ✓ Removed $link"
      fi
    done
  done
  # Remove the hub symlink if it points to this repo (restore backup if we made one).
  if [ -L "$HUB" ] && [ "$(readlink "$HUB")" = "$SRC_DIR" ]; then
    rm -f "$HUB" && echo "  ✓ Removed hub symlink $HUB"
    if [ -e "$HUB.bak" ]; then
      mv "$HUB.bak" "$HUB" 2>/dev/null && echo "  ✓ Restored $HUB from backup"
    fi
  fi
  echo "Uninstall complete (only links created by this repo were removed; other skills untouched)."
  exit 0
fi

# ---- Install mode ----
echo "Source directory: $SRC_DIR"

# Validate all skills first
rc=0
for d in "$SRC_DIR"/*/; do
  d="${d%/}"; base="$(basename "$d")"
    [[ " ${VALIDATE_EXCLUDE[*]} " == *" $base "* ]] && continue
    validate_skill "$d" || rc=1
done
if [ "$rc" -ne 0 ]; then
  echo "Validation failed; linking aborted. Please fix SKILL.md and retry." >&2
  exit 1
fi

# ── Public skills hub (Open Agent Skills standard: ~/.agents/skills) ──
# Symlink the hub to this repo's skills/ so every agent that reads it receives public
# skills automatically. Idempotent: skips if already correctly linked; backs up a real
# pre-existing dir before replacing it.
if [ -L "$HUB" ]; then
  if [ "$(readlink "$HUB")" = "$SRC_DIR" ]; then
    echo "→ Hub already linked: $HUB -> $SRC_DIR"
  else
    echo "  ⚠ Hub exists but points elsewhere ($HUB -> $(readlink "$HUB")). Leaving it untouched; hub readers depend on it." >&2
  fi
elif [ -e "$HUB" ]; then
  mv "$HUB" "$HUB.bak" 2>/dev/null && echo "  · Backed up existing $HUB to $HUB.bak"
  ln -s "$SRC_DIR" "$HUB" && echo "→ Created hub symlink: $HUB -> $SRC_DIR"
else
  ln -s "$SRC_DIR" "$HUB" && echo "→ Created hub symlink: $HUB -> $SRC_DIR"
fi

linked=0
for tool in "${ACTIVE_TOOLS[@]}"; do
  tdir="$(resolve_target "$tool")"
  [ -z "$tdir" ] && continue
  # Agents whose skills dir IS the hub read public skills via the hub symlink directly.
  if [ "$tdir" = "$HUB" ]; then
    echo "→ $tool reads the hub directly ($HUB); skipped (served by hub)"
    continue
  fi
  mkdir -p "$tdir"
  echo "→ Linking to $tool: $tdir"
  for d in "$SRC_DIR"/*/; do
    d="${d%/}";     base="$(basename "$d")"
    [[ " ${EXCLUDED_DIRS[*]} " == *" $base "* ]] && continue
    target="$tdir/$base"
    src="$d"
    if [ -L "$target" ]; then
      if is_ours "$target"; then
        # Already points to this repo: skip if path matches, otherwise recreate
        if [ "$(readlink "$target")" = "$src" ]; then
          echo "  · Already linked (skipped): $base"
          continue
        fi
        rm -f "$target"
        ln -s "$src" "$target" && { echo "  ✓ Updated: $base"; linked=$((linked+1)); }
      else
        echo "  ⚠ Skipped: link already exists pointing elsewhere $target (your private skill kept; to enable the repo version, remove or rename this link first)" >&2
      fi
    elif [ -e "$target" ]; then
      if prompt_conflict "$target"; then
        if rm -r "$target" && ln -s "$src" "$target"; then
          echo "  ✓ Linked (replaced original dir): $base"; linked=$((linked+1))
        else
          echo "  ✗ Delete failed, skipped: $target" >&2
        fi
      else
        echo "  · Skipped (kept original dir): $base" >&2
      fi
    else
      ln -s "$src" "$target" && { echo "  ✓ Linked: $base"; linked=$((linked+1)); }
    fi
  done
done

echo "Done. Added/updated $linked links in total."
echo "If a tool still does not discover the skills, confirm its skills directory path, and override with the corresponding env var if needed (see bash install.sh --list-tools)."
