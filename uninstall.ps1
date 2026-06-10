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

$OtherMods = @("token-economy", "agent-roles", "mission-control", "web-dash", "continuity",
    "format-on-edit", "check-on-edit", "daily-digest", "visual-verify", "self-improve",
    "mcp-pack", "scribe", "review-gate", "phase1-guard")
foreach ($mod in $OtherMods) {
    $script = Join-Path $Root "harness\$mod\uninstall.ps1"
    if (Test-Path -LiteralPath $script) {
        & $script
    }
}
