# validate.ps1 — On Windows, validate that each skill's SKILL.md under skills/ complies with the spec.
# Checks:
#   1. Each skill directory contains SKILL.md
#   2. frontmatter contains valid name / description
#   3. name contains only [a-z0-9-] and matches the directory name
# Exit code: 0 if all pass, otherwise 1. Usable for local validation and CI.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/validate.ps1

param()

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$SrcDir   = Join-Path $RepoRoot 'skills'

if (-not (Test-Path $SrcDir)) {
    Write-Error "Skills directory not found: $SrcDir"
    exit 1
}

$ok = $true
foreach ($d in (Get-ChildItem $SrcDir -Directory)) {
    if ($d.Name -eq '_template') { continue }
    $file = Join-Path $d.FullName 'SKILL.md'
    if (-not (Test-Path $file)) {
        Write-Host "X Missing SKILL.md: $($d.FullName)" -ForegroundColor Red
        $ok = $false
        continue
    }
    $content = Get-Content $file -Raw
    $name = ''; $desc = ''
    if ($content -match '(?s)^---\r?\n(.*?)\r?\n---\r?\n?') {
        $fm = $Matches[1]
        if ($fm -match '(?im)^\s*name:\s*(.+?)\s*$')        { $name = $Matches[1].Trim() }
        if ($fm -match '(?im)^\s*description:\s*(.+?)\s*$')  { $desc = $Matches[1].Trim() }
    }
    if ($name -eq '') { Write-Host "X Missing name: $file" -ForegroundColor Red; $ok = $false }
    if ($desc -eq '') { Write-Host "X Missing description: $file" -ForegroundColor Red; $ok = $false }
    if ($name -ne '' -and $name -notmatch '^[a-z0-9-]+$') {
        Write-Host "X Invalid name (only lowercase letters/digits/hyphens): $name" -ForegroundColor Red
        $ok = $false
    }
    if ($name -ne '' -and $name -ne $d.Name) {
        Write-Host "X name($name) does not match directory name($($d.Name))" -ForegroundColor Red
        $ok = $false
    }
    if ($ok) { Write-Host "OK $($d.Name)" }
}

if ($ok) { Write-Host "All skills validated." }
else     { Write-Host "Some validation checks failed; please fix per SKILL_SPEC.md." -ForegroundColor Red }
exit $(if ($ok) { 0 } else { 1 })
