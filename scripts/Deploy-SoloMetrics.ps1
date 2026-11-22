<#
.SYNOPSIS
  Copies addon\SoloMetrics (the installable payload) into WoW: Forever's
  Interface\AddOns\SoloMetrics. Source is never modified; nothing is synced back.

.PARAMETER WowAddonsDir
  Path ending in \_forever_\Interface\AddOns. If omitted, read from the
  SOLOMETRICS_WOW_ADDONS_DIR environment variable, then dev.local.json.

.PARAMETER DryRun
  Print every planned operation without writing anything.

.PARAMETER AdoptExisting
  Allow overwriting an existing AddOns\SoloMetrics folder that was NOT created
  by this script (no deploy manifest). Inspect that folder first.

.PARAMETER AllowNonForever
  Permit a client folder other than _forever_ (e.g. a beta). Requires explicit
  user approval; never use for _retail_ / _classic_.

.EXAMPLE
  ./scripts/Deploy-SoloMetrics.ps1 -WowAddonsDir 'C:\path\to\_forever_\Interface\AddOns' -DryRun
#>
[CmdletBinding()]
param(
    [string]$WowAddonsDir,
    [switch]$DryRun,
    [switch]$AdoptExisting,
    [switch]$AllowNonForever
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$AddonName = 'SoloMetrics'
$ManifestName = '.solometrics-deploy-manifest.txt'
$BlockedClients = @('_retail_', '_classic_', '_classic_era_', '_ptr_', '_xptr_', '_classic_ptr_')

function Fail([string]$Message) { throw "DEPLOY FAILED: $Message" }

function ConvertTo-NormalPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { Fail 'blank path' }
    $full = [System.IO.Path]::GetFullPath($Path.Trim().Replace('/', '\'))
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full.TrimEnd('\') -ieq $root.TrimEnd('\')) { Fail "refusing filesystem root: $full" }
    return $full.TrimEnd('\')
}

function Test-IsUnder([string]$Child, [string]$Parent) {
    $c = $Child.TrimEnd('\') + '\'
    $p = $Parent.TrimEnd('\') + '\'
    return $c.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

try {
    # ---- Resolve paths --------------------------------------------------
    $ProjectRoot = ConvertTo-NormalPath (Split-Path -Parent $PSScriptRoot)
    $SourceAddon = Join-Path $ProjectRoot "addon\$AddonName"
    $SourceToc = Join-Path $SourceAddon "$AddonName.toc"

    $configSource = 'parameter'
    if ([string]::IsNullOrWhiteSpace($WowAddonsDir)) {
        if (-not [string]::IsNullOrWhiteSpace($env:SOLOMETRICS_WOW_ADDONS_DIR)) {
            $WowAddonsDir = $env:SOLOMETRICS_WOW_ADDONS_DIR
            $configSource = 'env SOLOMETRICS_WOW_ADDONS_DIR'
        } else {
            $localCfg = Join-Path $ProjectRoot 'dev.local.json'
            if (Test-Path -LiteralPath $localCfg -PathType Leaf) {
                $cfg = Get-Content -LiteralPath $localCfg -Raw | ConvertFrom-Json
                $prop = $cfg.PSObject.Properties['wowAddonsDir']
                if ($prop) { $WowAddonsDir = [string]$prop.Value }
                $configSource = 'dev.local.json'
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($WowAddonsDir)) {
        Fail 'no WoW AddOns directory given. Pass -WowAddonsDir, set SOLOMETRICS_WOW_ADDONS_DIR, or create dev.local.json (see dev.local.example.json).'
    }

    $AddonsDir = ConvertTo-NormalPath $WowAddonsDir
    $Dest = Join-Path $AddonsDir $AddonName

    Write-Host '== SoloMetrics deploy =='
    Write-Host "  Project root : $ProjectRoot"
    Write-Host "  Source addon : $SourceAddon"
    Write-Host "  AddOns dir   : $AddonsDir  (from $configSource)"
    Write-Host "  Destination  : $Dest"
    if ($DryRun) { Write-Host '  Mode         : DRY RUN (no writes)' -ForegroundColor Cyan }

    # ---- Safety gates ---------------------------------------------------
    if (-not (Test-Path -LiteralPath $SourceToc -PathType Leaf)) { Fail "source TOC not found: $SourceToc" }
    if (-not (Test-Path -LiteralPath $AddonsDir -PathType Container)) { Fail "AddOns directory does not exist: $AddonsDir" }
    if ($AddonsDir -notmatch '\\Interface\\AddOns$') { Fail "destination parent must end in \Interface\AddOns: $AddonsDir" }

    $clientDir = Split-Path -Parent (Split-Path -Parent $AddonsDir)
    $clientName = Split-Path -Leaf $clientDir
    if ($BlockedClients -contains $clientName.ToLowerInvariant()) { Fail "refusing non-Forever client folder '$clientName'" }
    if ($clientName -ine '_forever_') {
        if ($AllowNonForever) {
            Write-Warning "Client folder is '$clientName', not _forever_ (allowed by -AllowNonForever)."
        } else {
            Fail "client folder is '$clientName', expected '_forever_'. Use -AllowNonForever only with explicit approval."
        }
    }

    if ((Split-Path -Leaf $Dest) -cne $AddonName) { Fail "destination folder must be named exactly '$AddonName'" }
    if (Test-IsUnder $Dest $ProjectRoot) { Fail 'destination is inside the project root' }
    if (Test-IsUnder $ProjectRoot $Dest) { Fail 'project root is inside the destination' }
    if (Test-IsUnder $SourceAddon $AddonsDir) { Fail 'source addon is inside the WoW AddOns directory' }

    # ---- Static validation ----------------------------------------------
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot 'Validate-SoloMetrics.ps1')
    if ($LASTEXITCODE -ne 0) { Fail 'validation failed; nothing deployed' }

    # ---- Build payload --------------------------------------------------
    $payload = New-Object System.Collections.Generic.List[object]
    $newSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($f in (Get-ChildItem -LiteralPath $SourceAddon -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($SourceAddon.Length).TrimStart('\')
        if ($rel -match '(^|\\)\.') { Write-Warning "Skipping dotfile: $rel"; continue }
        $dst = Join-Path $Dest $rel
        $srcHash = Get-Sha256 $f.FullName
        $action = 'NEW'
        if (Test-Path -LiteralPath $dst -PathType Leaf) {
            if ((Get-Sha256 $dst) -eq $srcHash) { $action = 'UNCHANGED' } else { $action = 'UPDATE' }
        }
        $payload.Add([pscustomobject]@{ Rel = $rel; Src = $f.FullName; Dst = $dst; Hash = $srcHash; Action = $action })
        [void]$newSet.Add($rel)
    }
    if (-not $newSet.Contains("$AddonName.toc")) { Fail 'payload has no root TOC (double nesting?)' }

    # ---- Existing destination -------------------------------------------
    $manifestPath = Join-Path $Dest $ManifestName
    $stale = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Dest) {
        $item = Get-Item -LiteralPath $Dest -Force
        if (-not $item.PSIsContainer) { Fail "destination exists but is not a folder: $Dest" }
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Fail "destination is a symlink/junction: $Dest" }
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            foreach ($old in (Get-Content -LiteralPath $manifestPath)) {
                $old = $old.Trim()
                if ($old -eq '' -or $old.StartsWith('#')) { continue }
                if ($newSet.Contains($old)) { continue }
                if ($old -match '(^|\\)\.\.(\\|$)' -or [System.IO.Path]::IsPathRooted($old)) {
                    Write-Warning "Ignoring suspicious manifest entry: $old"; continue
                }
                $stale.Add($old)
            }
        } elseif (-not $AdoptExisting) {
            Fail "destination exists but has no deploy manifest, so it was not created by this script. Inspect $Dest, then re-run with -AdoptExisting if it is safe to overwrite."
        } else {
            Write-Warning 'Adopting existing destination without manifest; untracked files there are left untouched.'
        }
    }

    # ---- Plan -----------------------------------------------------------
    Write-Host '  Planned operations:'
    foreach ($p in $payload) { Write-Host ("    {0,-9} {1}" -f $p.Action, $p.Rel) }
    foreach ($s in $stale) { Write-Host ("    {0,-9} {1}" -f 'DELETE', $s) -ForegroundColor Yellow }
    $countNew = @($payload | Where-Object { $_.Action -eq 'NEW' }).Count
    $countUpd = @($payload | Where-Object { $_.Action -eq 'UPDATE' }).Count
    $countSame = @($payload | Where-Object { $_.Action -eq 'UNCHANGED' }).Count
    $summary = "$($payload.Count) files ($countNew new, $countUpd updated, $countSame unchanged, $($stale.Count) removed)"

    if ($DryRun) {
        Write-Host "DRY RUN COMPLETE: $summary. No files written." -ForegroundColor Cyan
        exit 0
    }

    # ---- Execute --------------------------------------------------------
    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }
    foreach ($p in $payload) {
        if ($p.Action -eq 'UNCHANGED') { continue }
        $dir = Split-Path -Parent $p.Dst
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $p.Src -Destination $p.Dst -Force
        Write-Verbose "Copied $($p.Rel)"
    }
    foreach ($s in $stale) {
        $target = [System.IO.Path]::GetFullPath((Join-Path $Dest $s))
        if (-not (Test-IsUnder $target $Dest)) { Fail "stale entry resolves outside destination: $s" }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
            Write-Verbose "Removed stale $s"
        }
    }
    $manifest = @('# SoloMetrics deploy manifest - generated by Deploy-SoloMetrics.ps1, do not edit') + @($payload | ForEach-Object { $_.Rel })
    Set-Content -LiteralPath $manifestPath -Value $manifest -Encoding UTF8

    # ---- Verify ---------------------------------------------------------
    if (-not (Test-Path -LiteralPath (Join-Path $Dest "$AddonName.toc") -PathType Leaf)) { Fail 'deployed TOC missing after copy' }
    foreach ($p in $payload) {
        if (-not (Test-Path -LiteralPath $p.Dst -PathType Leaf)) { Fail "missing after copy: $($p.Rel)" }
        if ((Get-Sha256 $p.Dst) -ne $p.Hash) { Fail "hash mismatch after copy: $($p.Rel)" }
    }
    foreach ($s in $stale) {
        if (Test-Path -LiteralPath (Join-Path $Dest $s)) { Fail "stale file still present: $s" }
    }

    Write-Host "DEPLOY SUCCESS: $summary" -ForegroundColor Green
    $tocChanged = @($payload | Where-Object { $_.Rel -ieq "$AddonName.toc" -and $_.Action -ne 'UNCHANGED' }).Count -gt 0
    if ($tocChanged -or $countNew -gt 0 -or $stale.Count -gt 0) {
        Write-Host '  NOTE: TOC or file membership changed (or first install). Restart WoW (or log out to character select) - /reload may not pick this up.' -ForegroundColor Yellow
    } else {
        Write-Host '  Next: type /reload in game.'
    }
    exit 0
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
