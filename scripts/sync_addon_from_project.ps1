<#
.SYNOPSIS
  Mirror the Godot project addon `project/addons/nexus_coda` into repo-root `addons/nexus_coda` by copy or symlink.

.DESCRIPTION
  Source of truth for local development is `project/addons/nexus_coda`. Use this after editing there so the
  repository-root addon (what you commit under `addons/nexus_coda`) stays in sync. Open the project under
  `project/` in Godot. Native builds still deploy via `python scripts/deploy_addon.py` / `scons` (see deploy_addon.py).

.PARAMETER Symlink
  Link repo-root `addons/nexus_coda` to the project folder instead of copying.
  On Windows, a directory junction is used (no admin required in most setups).
  On macOS/Linux, a symbolic link is created.

.PARAMETER Force
  Replace an existing destination path (removes files or a previous link).

.EXAMPLE
  .\scripts\sync_addon_from_project.ps1

.EXAMPLE
  .\scripts\sync_addon_from_project.ps1 -Symlink -Force
#>

[CmdletBinding()]
param(
    [switch]$Symlink,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$src = Join-Path $repoRoot "project/addons/nexus_coda"
$dstParent = Join-Path $repoRoot "addons"
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
