[CmdletBinding()]
param(
    [ValidateSet("harness", "all", "windows-state-indicator")]
    [string]$Mode = "harness",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-ModInstall {
    param([string]$Name)
    $script = Join-Path $Root "harness\$Name\install.ps1"
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Unknown harness mod: $Name"
    }
    if ($Yes) {
        & $script -Yes
    } else {
        & $script
    }
}

switch ($Mode) {
    "harness" { Invoke-ModInstall "windows-state-indicator" }
    "all" { Invoke-ModInstall "windows-state-indicator" }
    "windows-state-indicator" { Invoke-ModInstall "windows-state-indicator" }
}

Write-Host ""
Write-Host "Done. Restart Claude Code to pick up hook changes."
