<#
.SYNOPSIS
  Mirror repo addon `addons/nexus_coda` into `project/addons/nexus_coda` by copy or symlink.

.DESCRIPTION
  Source of truth is the repository root `addons/nexus_coda`. Use this before opening the
  Godot project under `project/` so the editor sees `plugin.cfg`, `plugin.gd`, and (after a native
  build) `nexus_coda.gdextension`. Use `nexus_coda.gdextension.template` as the manifest source;
  `python scripts/deploy_addon.py` materializes `nexus_coda.gdextension` when DLLs exist. Native libraries are deployed separately:
  `python scripts/deploy_addon.py` (or with --symlink on Unix).

.PARAMETER Symlink
  Link the destination to the source instead of copying.
  On Windows, a directory junction is used (no admin required in most setups).
  On macOS/Linux, a symbolic link is created.

.PARAMETER Force
  Replace an existing destination path (removes files or a previous link).

.EXAMPLE
  .\scripts\sync_addon_to_project.ps1

.EXAMPLE
  .\scripts\sync_addon_to_project.ps1 -Symlink -Force
#>

[CmdletBinding()]
param(
    [switch]$Symlink,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$src = Join-Path $repoRoot "addons/nexus_coda"
$dstParent = Join-Path $repoRoot "project/addons"
$dst = Join-Path $dstParent "nexus_coda"

if (-not (Test-Path -LiteralPath $src -PathType Container)) {
    Write-Error "Source addon folder not found: $src"
}

if (Test-Path -LiteralPath $dst) {
    $isLink = (Get-Item -LiteralPath $dst).Attributes -band [IO.FileAttributes]::ReparsePoint
    if (-not $Force) {
        if ($Symlink -and $isLink) {
            Write-Host "Destination already exists as a link: $dst (use -Force to recreate)"
            exit 0
        }
        Write-Error "Destination already exists: $dst (use -Force to replace)"
    }
    Remove-Item -LiteralPath $dst -Recurse -Force
}

New-Item -ItemType Directory -Path $dstParent -Force | Out-Null

if ($Symlink) {
    $srcFull = Convert-Path $src
    $dstFull = $dst
    # Junction (mklink /J): Windows only. Symbolic links: macOS/Linux (and optional on Windows).
    $onWindows = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("SystemRoot"))

    if ($onWindows) {
        cmd /c mklink /J "$dstFull" "$srcFull" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "mklink /J failed (exit $LASTEXITCODE). Try copy mode without -Symlink."
        }
    }
    else {
        New-Item -ItemType SymbolicLink -Path $dstFull -Target $srcFull | Out-Null
    }

    Write-Host "Linked junction/symlink: $dst -> $srcFull"
}
else {
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
    Write-Host "Copied addon -> $dst"
}
