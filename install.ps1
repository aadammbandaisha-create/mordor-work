[CmdletBinding()]
param(
    [ValidateSet("harness", "all", "windows-state-indicator", "token-economy", "agent-roles")]
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

$AllMods = @("windows-state-indicator", "token-economy", "agent-roles")

switch ($Mode) {
    "harness" { foreach ($mod in $AllMods) { Invoke-ModInstall $mod } }
    "all" { foreach ($mod in $AllMods) { Invoke-ModInstall $mod } }
    default { Invoke-ModInstall $Mode }
}

Write-Host ""
Write-Host "Done. Restart Claude Code to pick up hook changes."
