<#
.SYNOPSIS
  Static validation of the installable payload in addon\SoloMetrics.
.DESCRIPTION
  - TOC exists, has Interface/Title, every listed file exists, no path escapes.
  - Every .lua in the payload is listed in the TOC (otherwise it never loads).
  - No dev-only files (scripts, docs, configs, archives, .git) in the payload.
  - Lua safety scan: no combat-log parsing, no executable-string loaders,
    no damage-meter reset call unless the line is marked SM-ALLOW-RESET.
  - Optional syntax check with luac -p if a luac binary is on PATH.
  Exits 0 on success, 1 on any error.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $ProjectRoot 'addon\SoloMetrics'
$Toc = Join-Path $Source 'SoloMetrics.toc'

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

Write-Host "Validating payload: $Source"

if (-not (Test-Path -LiteralPath $Toc -PathType Leaf)) {
    Write-Host "VALIDATION FAILED: missing $Toc" -ForegroundColor Red
    exit 1
}

$tocLines = Get-Content -LiteralPath $Toc
$iface = $tocLines | Where-Object { $_ -match '^##\s*Interface:\s*\S' } | Select-Object -First 1
if (-not $iface) { $errors.Add('TOC has no "## Interface:" line') } else { Write-Host "  $iface" }
if (-not ($tocLines | Where-Object { $_ -match '^##\s*Title:\s*\S' })) { $errors.Add('TOC has no "## Title:" line') }

$listed = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($raw in $tocLines) {
    $line = $raw.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    $rel = $line.Replace('/', '\')
    if ($rel -match '(^|\\)\.\.(\\|$)' -or [System.IO.Path]::IsPathRooted($rel)) {
        $errors.Add("TOC entry escapes addon folder: $line")
        continue
    }
    [void]$listed.Add($rel)
    if (-not (Test-Path -LiteralPath (Join-Path $Source $rel) -PathType Leaf)) {
        $errors.Add("TOC lists missing file: $line")
    }
}
Write-Host "  TOC file entries: $($listed.Count)"

$forbiddenExt = @('.ps1', '.psm1', '.md', '.json', '.zip', '.log', '.bat', '.cmd', '.sh', '.exe', '.dll')
$files = Get-ChildItem -LiteralPath $Source -Recurse -Force
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Source.Length).TrimStart('\')
    if ($f.PSIsContainer) {
        if ($f.Name -eq '.git') { $errors.Add("Payload contains .git directory: $rel") }
        continue
    }
    if ($forbiddenExt -contains $f.Extension.ToLowerInvariant()) {
        $errors.Add("Dev-only file inside payload: $rel")
    }
    if ($f.Extension -ieq '.lua' -and -not $listed.Contains($rel)) {
        $warnings.Add("Lua file not listed in TOC (will not load): $rel")
    }
}

$luaFiles = @($files | Where-Object { -not $_.PSIsContainer -and $_.Extension -ieq '.lua' })
foreach ($f in $luaFiles) {
    $rel = $f.FullName.Substring($Source.Length).TrimStart('\')
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
        $n++
        if ($line -match 'COMBAT_LOG_EVENT_UNFILTERED') {
            $errors.Add("${rel}:${n} uses combat log event (not allowed as damage source)")
        }
        if ($line -match '\b(loadstring|RunScript)\s*\(') {
            $errors.Add("${rel}:${n} executes code from a string")
        }
        if ($line -match 'ResetAllCombatSessions' -and $line -notmatch 'SM-ALLOW-RESET') {
            $errors.Add("${rel}:${n} references ResetAllCombatSessions without SM-ALLOW-RESET review marker")
        }
    }
}
Write-Host "  Lua files scanned: $($luaFiles.Count)"

$luac = $null
foreach ($name in @('luac5.1', 'luac51', 'luac')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { $luac = $cmd.Source; break }
}
if ($luac) {
    foreach ($f in $luaFiles) {
        $out = & $luac -p $f.FullName 2>&1
        if ($LASTEXITCODE -ne 0) { $errors.Add("Lua syntax error: $out") }
    }
    Write-Host "  Syntax checked with $luac"
} else {
    $warnings.Add('No luac on PATH; Lua syntax not checked (in-game load is the real test)')
}

foreach ($w in $warnings) { Write-Host "  WARN: $w" -ForegroundColor Yellow }
if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Host "  ERROR: $e" -ForegroundColor Red }
    Write-Host "VALIDATION FAILED ($($errors.Count) error(s))" -ForegroundColor Red
    exit 1
}
Write-Host 'VALIDATION PASSED' -ForegroundColor Green
exit 0
