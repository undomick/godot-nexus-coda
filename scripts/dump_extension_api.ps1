<#
.SYNOPSIS
  Dump GDExtension API JSON from a Godot 4.x executable for godot-cpp (optional 4.7 bindings).

.DESCRIPTION
  Writes to godot-cpp/gdextension/extension_api-4-7.json by default. When that file exists, godot-cpp/custom.py
  passes custom_api_file to SCons so bindings match your editor version.

.PARAMETER GodotExecutable
  Path to Godot (e.g. ...\Godot_v4.7-beta1_win64_console.exe). Override if your layout differs.

.PARAMETER OutputPath
  Destination JSON path relative to repository root.

.EXAMPLE
  .\scripts\dump_extension_api.ps1

.EXAMPLE
  .\scripts\dump_extension_api.ps1 -GodotExecutable "D:\Godot\Godot.exe"
#>

[CmdletBinding()]
param(
    [string]$GodotExecutable = "C:\Godot\Godot_v4.7-beta1_win64\Godot_v4.7-beta1_win64_console.exe",
    [string]$OutputPath = "godot-cpp/gdextension/extension_api-4-7.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    Write-Error "Godot executable not found: $GodotExecutable"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$outFull = Join-Path $repoRoot $OutputPath
$outDir = Split-Path -Parent $outFull
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$p = Start-Process -FilePath $GodotExecutable `
    -ArgumentList @("--headless", "--dump-extension-api", $outFull, "--quit") `
    -WorkingDirectory $repoRoot -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) {
    Write-Error "Godot exited with code $($p.ExitCode). Check the executable path and Godot version."
}

Write-Host "Wrote extension API dump -> $outFull"
Write-Host "Rebuild godot-cpp / extension with scons (root SConstruct passes custom_api_file when this file exists)."
