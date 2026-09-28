# install.ps1 — On Windows, symlink the skills under this repo's skills/ into each AI
# agent's (Claude Code / OpenAI Codex / Cursor / Gemini CLI / Windsurf / Cline / Kilo / Hub (shared ~/.agents/skills) /
# OpenClaw / Trae / Qoder / Kimi / OpenCode / GitHub Copilot / Goose / Continue / Zed /
# WorkBuddy / CodeBuddy / Hermes, etc.) skills directory.
#
# Design principles (same as install.sh):
#   1. Single source, zero conversion: the repo's skills/ is the single source of truth; only create links, no data copying.
#   2. Idempotent: safe to run repeatedly; already-correctly-linked skills are skipped automatically.
#   3. Safe: only manage links "pointing to this repo's skills/"; never delete user-built skills.
#   4. Validatable: before linking, check each SKILL.md's frontmatter for name/description.
#   5. Multi-agent extensible: supported agents are declared in agents.cfg (one line per agent:
#      name|ENV_VAR|DEFAULT_DIR). Adding an agent changes only that file.
#   6. Shared hub: ~/.agents/skills (Open Agent Skills standard) is junctioned to this repo's
#      skills/; agents that read it receive public skills automatically and are skipped by the
#      per-agent bridge loop below. Agents that do not read the hub get public skills bridged
#      into their own skills directory (private real subdirs are preserved = mixed mode).
#
# On Windows, links are created as Directory Junctions instead of symbolic links, so they work
# without administrator rights in most setups (no "Developer Mode" required). A junction points at
# the repo source, so edits there are reflected immediately and removal only deletes the junction
# (never your private skills). If junction creation fails due to policy, run PowerShell as
# Administrator or enable "Developer Mode" (Settings > Privacy & security > For developers).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 --tool claude
#   powershell -ExecutionPolicy Bypass -File install.ps1 --claude
#   powershell -ExecutionPolicy Bypass -File install.ps1 --list-tools
#   powershell -ExecutionPolicy Bypass -File install.ps1 --uninstall
#   powershell -ExecutionPolicy Bypass -File install.ps1 --check
#   powershell -ExecutionPolicy Bypass -File install.ps1 --hook
#   powershell -ExecutionPolicy Bypass -File install.ps1 --hook --tool codebuddy
#   powershell -ExecutionPolicy Bypass -File install.ps1 --unhook
#   powershell -ExecutionPolicy Bypass -File install.ps1 --hook-list

param()

$RepoRoot  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SrcDir    = Join-Path $RepoRoot 'skills'
$agentsCfg = Join-Path $RepoRoot 'agents.cfg'
$hooksCfg  = Join-Path $RepoRoot 'hooks.cfg'
# The exact command path stored in each agent's settings JSON. Always use
# forward slashes (matching bash install.sh) so that --unhook can match a hook
# that was originally installed by install.sh on the same machine.
$AutoUpdate = ($RepoRoot -replace '\\', '/') + '/hooks/auto-update.sh'

if (-not (Test-Path $agentsCfg)) {
    Write-Error "Agent config not found: $agentsCfg"
    exit 1
}

# Expand a path that may start with ~ to the user profile directory.
function Expand-Path {
    param([string]$p)
    if ($p -eq '~') { return $env:USERPROFILE }
    if ($p.StartsWith('~/') -or $p.StartsWith('~\')) {
        return Join-Path $env:USERPROFILE $p.Substring(2)
    }
    return $p
}

# Parse agents.cfg into objects with name / envVar / defaultDir (with ~ expanded).
function Get-Agents {
    $list = @()
    foreach ($line in (Get-Content $agentsCfg)) {
        $s = $line.Trim()
        if ($s -eq '' -or $s.StartsWith('#')) { continue }
        $parts = $s -split '\|'
        if ($parts.Count -lt 3) { continue }
        $list += [pscustomobject]@{
            name       = $parts[0].Trim()
            envVar     = $parts[1].Trim()
            defaultDir = (Expand-Path $parts[2].Trim())
        }
    }
    return $list
}

function Get-Agent {
    param([string]$name)
    return (Get-Agents) | Where-Object { $_.name -eq $name }
}

# Resolve an agent's skills directory: env override wins, else the default dir (with ~ expanded).
function Resolve-Target {
    param($agent)
    $envVal = [Environment]::GetEnvironmentVariable($agent.envVar)
    if ($envVal -and $envVal.Trim() -ne '') { return (Expand-Path $envVal) }
    return $agent.defaultDir
}

# Does the link at $path point under this repo's skills/ (i.e. was it created by us)?
function Test-Ours {
    param([string]$path)
    if (-not (Test-Path $path)) { return $false }
    $item = Get-Item $path -Force
    if ($item.LinkType -ne 'Junction' -and $item.LinkType -ne 'SymbolicLink') { return $false }
    $target = $item.Target
    if (-not $target) { return $false }
    $normTarget = $target.TrimEnd('\').ToLower()
    $normSrc    = $SrcDir.TrimEnd('\').ToLower()
    return $normTarget.StartsWith($normSrc)
}

# Validate one skill directory's frontmatter (name + description present, name well-formed).
function Test-Skill {
    param([string]$dir)
    $file = Join-Path $dir 'SKILL.md'
    if (-not (Test-Path $file)) {
        Write-Host "  X Missing SKILL.md: $dir" -ForegroundColor Red
        return $false
    }
    $content = Get-Content $file -Raw
    if ($content -notmatch '(?s)^---\r?\n(.*?)\r?\n---\r?\n?') {
        Write-Host "  X Missing frontmatter in: $file" -ForegroundColor Red
        return $false
    }
    $fm = $Matches[1]
    $name = ''; $desc = ''
    if ($fm -match '(?im)^\s*name:\s*(.+?)\s*$')        { $name = $Matches[1].Trim() }
    if ($fm -match '(?im)^\s*description:\s*(.+?)\s*$')  { $desc = $Matches[1].Trim() }
    if ($name -eq '') { Write-Host "  X Missing name: $file" -ForegroundColor Red; return $false }
    if ($desc -eq '') { Write-Host "  X Missing description: $file" -ForegroundColor Red; return $false }
    if ($name -notmatch '^[a-z0-9-]+$') {
        Write-Host "  X Invalid name (only lowercase letters/digits/hyphens): $name" -ForegroundColor Red
        return $false
    }
    $base = Split-Path $dir -Leaf
    if ($name -ne $base) {
        Write-Host "  X name($name) does not match directory name($base): $file" -ForegroundColor Red
        return $false
    }
    return $true
}

# ─────────────────────────────────────────────────────────────
# Startup-hook helpers (mirror install.sh --hook / --unhook / --hook-list).
#   hooks.cfg schema: name|SETTINGS_FILE|NEEDS_MATCHER|FORMAT
#   Adds/removes a SessionStart hook running hooks/auto-update.sh
#   (git pull --ff-only && bash install.sh) at agent startup.
# ─────────────────────────────────────────────────────────────

# List agent names declared in hooks.cfg (one per non-comment/non-blank line).
function Get-HookAgents {
    if (-not (Test-Path $hooksCfg)) { return @() }
    $list = @()
    foreach ($line in (Get-Content $hooksCfg)) {
        $s = $line.Trim()
        if ($s -eq '' -or $s.StartsWith('#')) { continue }
        $parts = $s -split '\|'
        if ($parts.Count -lt 3) { continue }
        $list += $parts[0].Trim()
    }
    return $list
}

# Return settings-file / needs-matcher / format for a hook agent, or $null.
function Get-HookInfo {
    param([string]$name)
    if (-not (Test-Path $hooksCfg)) { return $null }
    foreach ($line in (Get-Content $hooksCfg)) {
        $s = $line.Trim()
        if ($s -eq '' -or $s.StartsWith('#')) { continue }
        $parts = $s -split '\|'
        if ($parts.Count -lt 3) { continue }
        if ($parts[0].Trim() -eq $name) {
            $fmt = if ($parts.Count -ge 4 -and $parts[3].Trim() -ne '') { $parts[3].Trim() } else { 'claude' }
            return [pscustomobject]@{
                settingsFile = $parts[1].Trim()
                needsMatcher = $parts[2].Trim()
                format       = $fmt
            }
        }
    }
    return $null
}

# Write $data as pretty JSON to $path atomically (temp file + replace), making
# parent dirs as needed.
function Set-HookJson {
    param([string]$path, $data)
    $dir = Split-Path $path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $tmp  = $path + '.tmp'
    $json = $data | ConvertTo-Json -Depth 10
    Set-Content -Path $tmp -Value $json -Encoding UTF8
    Move-Item -Path $tmp -Destination $path -Force
}

# Snapshot the current settings file (best-effort) before modifying it.
function Backup-HookFile {
    param([string]$path)
    if (Test-Path $path) {
        try { Copy-Item -Path $path -Destination ($path + '.bak') -Force } catch {}
    }
}

# Extract the stored command from a hook group, or $null if it isn't ours.
function Get-GroupCmd {
    param($g, [string]$fmt, [string]$cmd)
    if ($g -isnot [PSCustomObject]) { return $null }
    if ($fmt -eq 'cursor') {
        if ($g.PSObject.Properties['command']) { return $g.command }
        return $null
    }
    if ($g.PSObject.Properties['hooks']) {
        $hs = $g.hooks
        if ($hs -isnot [Array]) { $hs = @($hs) }
        foreach ($h in $hs) {
            if ($h -is [PSCustomObject] -and $h.PSObject.Properties['command'] -and $h.command -eq $cmd) {
                return $cmd
            }
        }
    }
    return $null
}

# Merge (add|remove) the auto-update hook into a settings JSON file.
# Returns $true on success, $false on (recoverable) failure.
function Merge-HookJson {
    param(
        [string]$Mode,   # add | remove
        [string]$Path,
        [string]$Cmd,
        [string]$Needs,  # yes | no
        [string]$Fmt     # claude | cursor | trae | hermes | kimi | autohand
    )

    # Non-JSON formats get their own handlers.
    if ($Fmt -eq 'hermes')   { return Merge-HookYaml    $Mode $Path $Cmd }
    if ($Fmt -eq 'kimi')     { return Merge-HookToml    $Mode $Path $Cmd }
    if ($Fmt -eq 'autohand') { return Merge-HookAutohand $Mode $Path $Cmd }

    if ($Fmt -eq 'cursor') { $event = 'sessionStart' } else { $event = 'SessionStart' }

    $data = $null
    if (Test-Path $Path) {
        try { $data = Get-Content $Path -Raw | ConvertFrom-Json -ErrorAction Stop }
        catch {
            Write-Error ("ERROR: cannot parse JSON at {0}: {1}" -f $Path, $_.Exception.Message)
            return $false
        }
    } else {
        $data = New-Object PSObject
    }

    if ($Mode -eq 'add') {
        if (($Fmt -eq 'cursor' -or $Fmt -eq 'trae') -and -not $data.PSObject.Properties['version']) {
            Add-Member -InputObject $data -MemberType NoteProperty -Name 'version' -Value 1
        }
        if (-not $data.PSObject.Properties['hooks']) {
            Add-Member -InputObject $data -MemberType NoteProperty -Name 'hooks' -Value (New-Object PSObject)
        }
        $hooks = $data.hooks
        if (-not $hooks.PSObject.Properties[$event]) {
            Add-Member -InputObject $hooks -MemberType NoteProperty -Name $event -Value @()
        }
        $groups = $hooks.$event
        if ($groups -isnot [Array]) { $groups = @($groups) }

        foreach ($g in $groups) {
            if ((Get-GroupCmd $g -fmt $Fmt -cmd $Cmd) -eq $Cmd) {
                Write-Host "  · already present (skipped): $Path"
                return $true
            }
        }

        if ($Fmt -eq 'cursor') {
            $newGroup = New-Object PSObject
            Add-Member -InputObject $newGroup -MemberType NoteProperty -Name 'command' -Value $Cmd
        } else {
            $handler = New-Object PSObject
            Add-Member -InputObject $handler -MemberType NoteProperty -Name 'type' -Value 'command'
            Add-Member -InputObject $handler -MemberType NoteProperty -Name 'command' -Value $Cmd
            $newGroup = New-Object PSObject
            Add-Member -InputObject $newGroup -MemberType NoteProperty -Name 'hooks' -Value @($handler)
            if ($Needs -eq 'yes') {
                Add-Member -InputObject $newGroup -MemberType NoteProperty -Name 'matcher' -Value 'startup'
            }
        }

        $groups = $groups + $newGroup
        $hooks.$event = $groups
        Backup-HookFile $Path
        Set-HookJson $Path $data
        Write-Host "  OK added startup hook to $Path"
        return $true
    }

    # remove
    if (-not (Test-Path $Path)) {
        Write-Host "  · no settings file, nothing to remove: $Path"
        return $true
    }
    $hooks = $data.hooks
    if (-not $hooks -or -not $hooks.PSObject.Properties[$event]) {
        Write-Host "  · startup hook not found (skipped): $Path"
        return $true
    }
    $groups = $hooks.$event
    if ($groups -isnot [Array]) { $groups = @($groups) }
    $before = $groups.Count
    $kept = @()
    foreach ($g in $groups) { if ((Get-GroupCmd $g -fmt $Fmt -cmd $Cmd) -ne $Cmd) { $kept += $g } }
    $removed = $before - $kept.Count
    if ($removed -eq 0) {
        Write-Host "  · startup hook not found (skipped): $Path"
        return $true
    }
    if ($kept.Count -gt 0) { $hooks.$event = $kept } else { $hooks.PSObject.Properties.Remove($event) }
    if ($hooks.PSObject.Properties.Count -gt 0) { $data.hooks = $hooks } else { $data.PSObject.Properties.Remove('hooks') }
    Backup-HookFile $Path
    Set-HookJson $Path $data
    Write-Host ("  OK removed {0} startup hook(s) from {1}" -f $removed, $Path)
    return $true
}

# ── Kimi: ~/.kimi-code/config.toml — [[hooks]] array-of-tables ──
# Verified against kimi.com/code/docs: event="SessionStart", matcher="startup".
function Merge-HookToml {
    param([string]$Mode, [string]$Path, [string]$Cmd)
    $event = 'SessionStart'; $matcher = 'startup'
    $block = "[[hooks]]`nevent = `"$event`"`nmatcher = `"$matcher`"`ncommand = `"$Cmd`"`n"

    if ($Mode -eq 'add') {
        $txt = ''
        if (Test-Path $Path) { $txt = Get-Content $Path -Raw }
        if ($txt.Contains($Cmd)) { Write-Host "  · already present (skipped): $Path"; return $true }
        if ($txt -and -not $txt.EndsWith("`n")) { $txt += "`n" }
        $dir = Split-Path $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        Backup-HookFile $Path
        Set-Content -Path $Path -Value ($txt + $block) -Encoding UTF8
        Write-Host "  OK added startup hook to $Path"
        return $true
    }

    if (-not (Test-Path $Path)) { Write-Host "  · no config, nothing to remove: $Path"; return $true }
    $txt = Get-Content $Path -Raw
    if (-not $txt.Contains($Cmd)) { Write-Host "  · startup hook not found (skipped): $Path"; return $true }
    $lines = $txt -split "`n"
    $out = @(); $i = 0; $n = $lines.Count
    while ($i -lt $n) {
        if ($lines[$i].Trim() -eq '[[hooks]]') {
            $j = $i; $blk = @()
            while ($j -lt $n -and -not ($j -gt $i -and $lines[$j].Trim() -eq '[[hooks]]')) { $blk += $lines[$j]; $j++ }
            if (($blk -join "`n").Contains($Cmd)) { $i = $j; continue }
            $out += $blk; $i = $j
        } else { $out += $lines[$i]; $i++ }
    }
    Backup-HookFile $Path
    Set-Content -Path $Path -Value ($out -join "`n") -Encoding UTF8
    Write-Host "  OK removed startup hook from $Path"
    return $true
}

# ── Autohand: ~/.autohand/config.json — { "hooks": { "enabled": true, "hooks": [ {event, command} ] } } ──
# Verified against docs.autohand.ai: event "session-start", no matcher needed.
function Merge-HookAutohand {
    param([string]$Mode, [string]$Path, [string]$Cmd)
    $event = 'session-start'
    $data = $null
    if (Test-Path $Path) {
        try { $data = Get-Content $Path -Raw | ConvertFrom-Json -ErrorAction Stop }
        catch { Write-Error ("ERROR: cannot parse JSON at {0}" -f $Path); return $false }
    } else { $data = New-Object PSObject }

    if ($Mode -eq 'add') {
        if (-not $data.PSObject.Properties['hooks']) {
            Add-Member -InputObject $data -MemberType NoteProperty -Name 'hooks' -Value (New-Object PSObject)
        }
        $hooks = $data.hooks
        if (-not $hooks.PSObject.Properties['hooks']) {
            Add-Member -InputObject $hooks -MemberType NoteProperty -Name 'hooks' -Value @()
        }
        $hl = $hooks.hooks
        if ($hl -isnot [Array]) { $hl = @($hl) }
        foreach ($h in $hl) {
            if ($h -is [PSCustomObject] -and $h.PSObject.Properties['event'] -and $h.event -eq $event -and
                $h.PSObject.Properties['command'] -and $h.command -eq $Cmd) {
                Write-Host "  · already present (skipped): $Path"; return $true
            }
        }
        $entry = New-Object PSObject
        Add-Member -InputObject $entry -MemberType NoteProperty -Name 'event' -Value $event
        Add-Member -InputObject $entry -MemberType NoteProperty -Name 'command' -Value $Cmd
        $hl = $hl + $entry
        $hooks.hooks = $hl
        $hooks.enabled = $true
        Backup-HookFile $Path
        Set-HookJson $Path $data
        Write-Host "  OK added startup hook to $Path"
        return $true
    }

    if (-not (Test-Path $Path)) { Write-Host "  · no config, nothing to remove: $Path"; return $true }
    $hooks = $data.hooks
    $hl = if ($hooks -and $hooks.PSObject.Properties['hooks']) { $hooks.hooks } else { @() }
    if ($hl -isnot [Array]) { $hl = @($hl) }
    $before = $hl.Count
    $kept = @()
    foreach ($h in $hl) {
        if (-not ($h -is [PSCustomObject] -and $h.PSObject.Properties['event'] -and $h.event -eq $event -and
                  $h.PSObject.Properties['command'] -and $h.command -eq $Cmd)) { $kept += $h }
    }
    $removed = $before - $kept.Count
    if ($removed -eq 0) { Write-Host "  · startup hook not found (skipped): $Path"; return $true }
    if ($kept.Count -gt 0) {
        $hooks.hooks = $kept
        if ($hooks.PSObject.Properties['enabled']) { $hooks.PSObject.Properties.Remove('enabled') }
    } else {
        $data.PSObject.Properties.Remove('hooks')
    }
    Backup-HookFile $Path
    Set-HookJson $Path $data
    Write-Host ("  OK removed {0} startup hook(s) from {1}" -f $removed, $Path)
    return $true
}

# ── Hermes: ~/.hermes/config.yaml — hooks: { on_session_start: [ {command, timeout} ] } ──
# Verified against ~/.hermes/hermes-agent: event "on_session_start". YAML needs PyYAML,
# so delegate to python3 if available; otherwise print a manual snippet and skip.
function Merge-HookYaml {
    param([string]$Mode, [string]$Path, [string]$Cmd)
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        Write-Warning "python3 not found; cannot auto-edit Hermes YAML. Add this to $Path under 'hooks':"
        Write-Host ("  on_session_start:`n    - command: {0}`n      timeout: 30" -f $Cmd)
        return $true
    }
    $py = @'
import sys, os
mode, path, cmd = sys.argv[1:4]
try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: PyYAML is required to edit Hermes config.yaml (Hermes itself uses it). Install it or add the hook manually.\n")
    sys.exit(2)
event = "on_session_start"
def backup(p):
    if os.path.exists(p):
        try: open(p+".bak","w").write(open(p).read())
        except Exception: pass
def load(p):
    if not os.path.exists(p): return {}
    with open(p) as f: return yaml.safe_load(f) or {}
def write(p,d):
    os.makedirs(os.path.dirname(os.path.abspath(p)), exist_ok=True)
    t=p+".tmp"
    with open(t,"w") as f:
        yaml.safe_dump(d,f,default_flow_style=False,sort_keys=False,allow_unicode=True); f.write("\n")
    os.replace(t,p)
if mode=="add":
    data=load(path)
    if not isinstance(data,dict): data={}
    h=data.get("hooks")
    if not isinstance(h,dict): h={}; data["hooks"]=h
    lst=h.get(event)
    if not isinstance(lst,list): lst=[]; h[event]=lst
    if any(isinstance(x,dict) and x.get("command")==cmd for x in lst):
        print("  · already present (skipped): "+path); sys.exit(0)
    lst.append({"command":cmd,"timeout":30})
    backup(path); write(path,data)
    print("  OK added startup hook to "+path)
    print("  NOTE: Hermes requires the command to be allowlisted before it fires: run `hermes hooks --accept-hooks` (or set hooks_auto_accept: true).")
elif mode=="remove":
    if not os.path.exists(path):
        print("  · no config, nothing to remove: "+path); sys.exit(0)
    data=load(path)
    h=data.get("hooks",{}) if isinstance(data,dict) else {}
    lst=h.get(event,[]) if isinstance(h,dict) else []
    before=len(lst)
    lst=[x for x in lst if not (isinstance(x,dict) and x.get("command")==cmd)]
    removed=before-len(lst)
    if removed==0:
        print("  · startup hook not found (skipped): "+path); sys.exit(0)
    if lst: h[event]=lst
    else: h.pop(event,None)
    if h: data["hooks"]=h
    else: data.pop("hooks",None)
    backup(path); write(path,data)
    print("  OK removed startup hook from "+path)
'@
    $result = ($py | python3 - $Mode $Path $Cmd 2>&1)
    if ($LASTEXITCODE -eq 2) { Write-Error $result; return $false }
    Write-Host $result
    return $true
}

# Directories skipped during linking (template + example skills are not
# distributed into any agent's skills directory).
$EXCLUDED_DIRS = @('_template', 'example-doc-review', 'example-git-workflow')

# Directories skipped during validation. Only the bare template is skipped
# here (its name intentionally differs from its dir name); the example skills
# are real, valid skills and are validated like any other, keeping this
# consistent with install.sh and tools/validate.sh.
$VALIDATE_EXCLUDE = @('_template')

$Selected     = @()
$DoUninstall  = $false
$DoCheck      = $false
$DoList       = $false
$DoHook       = $false
$DoUnhook     = $false
$DoHookList   = $false

# Parse arguments in a single pass so that --tool <name> consumes its value immediately.
$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -eq '--tool') {
        $i++
        if ($i -ge $args.Count) { Write-Error "Missing value for --tool"; exit 1 }
        $Selected += $args[$i]
    }
    elseif ($arg -match '^--tool=(.+)$') {
        $Selected += $Matches[1]
    }
    elseif ($arg -eq '--list-tools') { $DoList = $true }
    elseif ($arg -eq '--uninstall')  { $DoUninstall = $true }
    elseif ($arg -eq '--check')      { $DoCheck = $true }
    elseif ($arg -eq '--hook')       { $DoHook = $true }
    elseif ($arg -eq '--unhook')     { $DoUnhook = $true }
    elseif ($arg -eq '--hook-list')  { $DoHookList = $true }
    elseif ($arg -eq '-h' -or $arg -eq '--help') {
        foreach ($l in (Get-Content $MyInvocation.MyCommand.Path)) {
            if ($l.StartsWith('#')) { Write-Host $l.Substring(1).Trim() } else { break }
        }
        exit 0
    }
    elseif ($arg -match '^--(.+)$') {
        $cand = $Matches[1]
        if (Get-Agent $cand) { $Selected += $cand }
        else {
            Write-Error "Unknown argument: $arg"
            Write-Host "Supported tools: $((Get-Agents).name -join ', ')"
            exit 1
        }
    }
    else {
        Write-Error "Unknown argument: $arg"
        Write-Host "Supported tools: $((Get-Agents).name -join ', ')"
        exit 1
    }
    $i++
}

# ─────────────────────────────────────────────────────────────
# Startup-hook subcommands: --hook / --unhook / --hook-list
#   Adds/removes a SessionStart hook that runs hooks/auto-update.sh
#   (git pull --ff-only && bash install.sh) at agent startup.
#   Driven by hooks.cfg; exits before the tool-linking logic below.
# ─────────────────────────────────────────────────────────────
if ($DoHook -or $DoUnhook -or $DoHookList) {
    if (-not (Test-Path $hooksCfg))  { Write-Error "Hook config not found: $hooksCfg"; exit 1 }
    if (-not (Test-Path $AutoUpdate)) { Write-Error "Auto-update wrapper not found: $AutoUpdate"; exit 1 }

    if ($DoHookList) {
        Write-Host "Agents with a verified startup-hook config (hooks.cfg):"
        foreach ($t in (Get-HookAgents)) {
            $info = Get-HookInfo $t
            Write-Host ("  {0,-12} {1}  (schema: {2}, matcher: {3})" -f $t, $info.settingsFile, $info.format, $info.needsMatcher)
        }
        exit 0
    }

    if ($DoHook -and $DoUnhook) {
        Write-Error "Use either --hook or --unhook, not both."; exit 1
    }

    $hookSelected = @()
    if ($Selected.Count -gt 0) {
        foreach ($t in $Selected) {
            if (Get-HookInfo $t) { $hookSelected += $t }
            else {
                Write-Error "Unsupported hook agent: $t"
                Write-Host "Supported hook agents: $((Get-HookAgents) -join ', ')"
                Write-Host "(Agents not in hooks.cfg are skipped to avoid corrupting unknown configs.)"
                exit 1
            }
        }
    } else {
        $hookSelected = Get-HookAgents
    }

    $action = if ($DoUnhook) { 'remove' } else { 'add' }
    $verb   = if ($DoUnhook) { 'Removing' } else { 'Adding' }
    Write-Host "$verb startup hook (runs: git pull --ff-only && bash install.sh)"
    Write-Host "Wrapper: $AutoUpdate"
    Write-Host
    $rc = 0
    foreach ($tool in $hookSelected) {
        $info = Get-HookInfo $tool
        $spath = Expand-Path $info.settingsFile
        Write-Host "-> $tool ($spath)  [schema: $($info.format)]"
        if (-not (Merge-HookJson $action $spath $AutoUpdate $info.needsMatcher $info.format)) { $rc = 1 }
    }
    Write-Host
    if ($rc -eq 0) {
        Write-Host "Done."
        if ($DoHook) {
            Write-Host "The hook runs once per agent session start."
            Write-Host "Verify with the agent's hook inspector after restarting the agent."
        }
    } else {
        Write-Error "Some operations failed; see messages above."
    }
    exit $rc
}

# Validate that selected agent names are supported.
foreach ($t in $Selected) {
    if (-not (Get-Agent $t)) {
        Write-Error "Unknown tool: $t"
        Write-Host "Currently supported tools: $((Get-Agents).name -join ', ')"
        Write-Host "Use --list-tools to see the full list."
        exit 1
    }
}

# --list-tools
if ($DoList) {
    Write-Host "Currently supported tools:"
    foreach ($a in (Get-Agents)) {
        $dir = Resolve-Target $a
        Write-Host ("  {0,-12} {1} (override var: {2})" -f $a.name, $dir, $a.envVar)
    }
    exit 0
}

# Collect the agent set to process.
$agents = Get-Agents
if ($Selected.Count -eq 0) { $ActiveTools = $agents }
else                       { $ActiveTools = $agents | Where-Object { $Selected -contains $_.name } }

# ── Public skills hub (Open Agent Skills standard: ~/.agents/skills) ──
# Agents whose DEFAULT_DIR equals this path receive public skills directly via the hub junction
# and are skipped by the per-agent bridge loop. This is a fixed constant (the industry-standard
# hub location), not an entry in agents.cfg — there is no agent literally named "agents".
$Hub = Expand-Path '~/.agents/skills'

# --check mode
if ($DoCheck) {
    Write-Host "Validating skill frontmatter under $SrcDir..."
    $ok = $true
    foreach ($d in (Get-ChildItem $SrcDir -Directory)) {
        if ($VALIDATE_EXCLUDE -contains $d.Name) { continue }
        if (Test-Skill $d.FullName) { Write-Host "  OK $($d.Name)" }
        else                         { $ok = $false }
    }
    if ($ok) { Write-Host "All passed." } else { Write-Host "Some validation checks failed." -ForegroundColor Red }
    exit $(if ($ok) { 0 } else { 1 })
}

# --uninstall mode
if ($DoUninstall) {
    Write-Host "Removing links created by this repo..."
    foreach ($agent in $ActiveTools) {
        $tdir = Resolve-Target $agent
        if (-not $tdir -or -not (Test-Path $tdir)) { continue }
        foreach ($link in (Get-ChildItem $tdir -ErrorAction SilentlyContinue)) {
            if (Test-Ours $link.FullName) {
                Remove-Item $link.FullName -Force
                Write-Host "  OK Removed $($link.FullName)"
            }
        }
    }
    # Remove the hub junction if it points to this repo (restore backup if we made one).
    if (Test-Path $Hub) {
        $hItem = Get-Item $Hub -Force
        if (($hItem.LinkType -eq 'Junction' -or $hItem.LinkType -eq 'SymbolicLink') -and (Test-Ours $Hub)) {
            Remove-Item $Hub -Force
            Write-Host "  OK Removed hub junction $Hub"
            if (Test-Path ($Hub + '.bak')) {
                Move-Item ($Hub + '.bak') $Hub -Force
                Write-Host "  OK Restored $Hub from backup"
            }
        }
    }
    Write-Host "Uninstall complete (only links created by this repo were removed; other skills untouched)."
    exit 0
}

# -- install mode
Write-Host "Source directory: $SrcDir"

# Validate all skills first.
$ok = $true
foreach ($d in (Get-ChildItem $SrcDir -Directory)) {
    if ($VALIDATE_EXCLUDE -contains $d.Name) { continue }
    if (-not (Test-Skill $d.FullName)) { $ok = $false }
}
if (-not $ok) {
    Write-Host "Validation failed; linking aborted. Please fix SKILL.md and retry." -ForegroundColor Red
    exit 1
}

# ── Public skills hub (Open Agent Skills standard: ~/.agents/skills) ──
# Junction the hub to this repo's skills/ so every agent that reads it receives public
# skills automatically. Idempotent: skips if already correctly linked; backs up a real
# pre-existing dir before replacing it.
$parent = Split-Path $Hub
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
if (Test-Path $Hub) {
    $hItem = Get-Item $Hub -Force
    if (($hItem.LinkType -eq 'Junction' -or $hItem.LinkType -eq 'SymbolicLink') -and (Test-Ours $Hub)) {
        Write-Host "-> Hub already linked: $Hub -> $SrcDir"
    }
    elseif ($hItem.LinkType -eq 'Junction' -or $hItem.LinkType -eq 'SymbolicLink') {
        Write-Warning "Hub exists but points elsewhere ($Hub -> $($hItem.Target)). Leaving it untouched; hub readers depend on it."
    }
    else {
        Move-Item $Hub ($Hub + '.bak') -Force
        Write-Host "  - Backed up existing $Hub to $($Hub).bak"
        New-Item -ItemType Junction -Path $Hub -Target $SrcDir | Out-Null
        Write-Host "-> Created hub junction: $Hub -> $SrcDir"
    }
}
else {
    New-Item -ItemType Junction -Path $Hub -Target $SrcDir | Out-Null
    Write-Host "-> Created hub junction: $Hub -> $SrcDir"
}

$linked = 0
foreach ($agent in $ActiveTools) {
    $tdir = Resolve-Target $agent
    if (-not $tdir) { continue }
    # Agents whose skills dir IS the hub read public skills via the hub junction directly.
    if ($tdir -eq $Hub) {
        Write-Host "-> $($agent.name) reads the hub directly ($Hub); skipped (served by hub)"
        continue
    }
    if (-not (Test-Path $tdir)) { New-Item -ItemType Directory -Path $tdir | Out-Null }
    Write-Host "-> Linking to $($agent.name): $tdir"
    foreach ($d in (Get-ChildItem $SrcDir -Directory)) {
        if ($EXCLUDED_DIRS -contains $d.Name) { continue }
        $target = Join-Path $tdir $d.Name
        $src    = $d.FullName
        if (Test-Path $target) {
            $item = Get-Item $target -Force
            if (($item.LinkType -eq 'Junction' -or $item.LinkType -eq 'SymbolicLink') -and (Test-Ours $target)) {
                if ($item.Target.TrimEnd('\').ToLower() -eq $src.TrimEnd('\').ToLower()) {
                    Write-Host "  - Already linked (skipped): $($d.Name)"
                    continue
                }
                Remove-Item $target -Force
                New-Item -ItemType Junction -Path $target -Target $src | Out-Null
                Write-Host "  OK Updated: $($d.Name)"
                $linked++
            }
            else {
                Write-Warning "Skipped: target exists and is not a link $target (your private skill kept; to enable the repo version, move this directory away first)"
            }
        }
        else {
            New-Item -ItemType Junction -Path $target -Target $src | Out-Null
            Write-Host "  OK Linked: $($d.Name)"
            $linked++
        }
    }
}

Write-Host "Done. Added/updated $linked links in total."
Write-Host "If a tool still does not discover the skills, confirm its skills directory path, and override with the corresponding env var if needed (see: powershell -ExecutionPolicy Bypass -File install.ps1 --list-tools)."
