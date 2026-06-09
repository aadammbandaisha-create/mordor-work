[CmdletBinding()]
param(
    [switch]$RemoveState,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $Root "harness\windows-state-indicator\uninstall.ps1"

if ($Yes -and $RemoveState) {
    & $script -Yes -RemoveState
} elseif ($Yes) {
    & $script -Yes
} elseif ($RemoveState) {
    & $script -RemoveState
} else {
    & $script
}
