[CmdletBinding()]
param(
    [switch]$RemoveState,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$stateScript = Join-Path $Root "harness\windows-state-indicator\uninstall.ps1"
if ($Yes -and $RemoveState) {
    & $stateScript -Yes -RemoveState
} elseif ($Yes) {
    & $stateScript -Yes
} elseif ($RemoveState) {
    & $stateScript -RemoveState
} else {
    & $stateScript
}

$tokenScript = Join-Path $Root "harness\token-economy\uninstall.ps1"
& $tokenScript

$rolesScript = Join-Path $Root "harness\agent-roles\uninstall.ps1"
& $rolesScript
