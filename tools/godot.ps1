# Wrapper: run Godot against this project with any extra args.
# Usage:
#   .\tools\godot.ps1                      # open editor
#   .\tools\godot.ps1 --headless --quit-after 120
#   .\tools\godot.ps1 -- --shot=D:\tmp\menu.png
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Rest
)

$ErrorActionPreference = 'Stop'
$exe = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '_tools\godot\Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path $exe)) {
    Write-Error "Godot not found at: $exe"
    exit 1
}
$project = Split-Path $PSScriptRoot -Parent
& $exe --path $project @Rest
exit $LASTEXITCODE
