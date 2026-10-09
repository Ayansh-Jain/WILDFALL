# Runs the headless WILDFALL test suite.
# Usage (from anywhere):  powershell -ExecutionPolicy Bypass -File Game/tests/run_tests.ps1 [-Godot <path to Godot console exe>] [-Extra "<runner args>"]
# Runner args, e.g.  -Extra "--only=scroll"   or   -Extra "--skip-walk"
param(
    [string]$Godot = $env:GODOT,
    [string]$Extra = ""
)
$ErrorActionPreference = "Continue"
$project = Split-Path -Parent $PSScriptRoot
if (-not $Godot) { $Godot = "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $Godot)) { Write-Error "Godot not found. Pass -Godot or set the GODOT environment variable."; exit 2 }

# Import first so new scripts/classes/audio are registered.
$import = & $Godot --headless --path $project --import 2>&1 | ForEach-Object { "$_" }
$importErrors = $import | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load script"
if ($importErrors) { $importErrors | ForEach-Object { Write-Host $_ }; Write-Host "IMPORT FAILED"; exit 1 }

$out = & $Godot --headless --fixed-fps 60 --path $project res://tests/test_runner.tscn -- @($Extra -split " " | Where-Object { $_ }) 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Host $_ }
$scriptErrors = $out | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load script"
if ($scriptErrors) {
    Write-Host "`nFAILED: script errors were reported during the run:"
    $scriptErrors | ForEach-Object { Write-Host "  $_" }
    exit 1
}
exit $code