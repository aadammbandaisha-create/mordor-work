[CmdletBinding()]
param(
    [ValidateSet("harness", "all", "work", "windows-state-indicator", "token-economy", "agent-roles",
        "mission-control", "web-dash", "continuity", "format-on-edit", "daily-digest",
        "visual-verify", "self-improve", "mcp-pack", "scribe", "check-on-edit",
        "review-gate", "phase1-guard")]
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

$AllMods = @("windows-state-indicator", "token-economy", "agent-roles",
    "mission-control", "web-dash", "continuity", "format-on-edit", "check-on-edit",
    "daily-digest", "visual-verify", "self-improve", "mcp-pack", "scribe",
    "review-gate", "phase1-guard")

# Muted profile for a workstation: no network-serving dashboard. Future
# life-director mods (inboxes, agenda, voice briefs) stay out of this list.
$WorkMods = @("windows-state-indicator", "token-economy", "agent-roles",
    "mission-control", "continuity", "format-on-edit", "check-on-edit",
    "daily-digest", "visual-verify", "self-improve", "mcp-pack", "scribe",
    "review-gate", "phase1-guard")

switch ($Mode) {
    "harness" { foreach ($mod in $AllMods) { Invoke-ModInstall $mod } }
    "all" { foreach ($mod in $AllMods) { Invoke-ModInstall $mod } }
    "work" { foreach ($mod in $WorkMods) { Invoke-ModInstall $mod } }
    default { Invoke-ModInstall $Mode }
}

Write-Host ""
Write-Host "Done. Restart Claude Code to pick up hook changes."
