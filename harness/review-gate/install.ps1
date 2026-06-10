[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$Sentinel = "mordor:review-gate"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SkillsDir = Join-Path $ClaudeDir "skills"
$TargetShip = Join-Path $SkillsDir "ship"

Write-Host ""
Write-Host "Install review-gate"
Write-Host "Skills dir: $SkillsDir"
Write-Host "Target:     $TargetShip"
Write-Host "Sentinel:   $Sentinel"
Write-Host ""
Write-Host "Changes:"
Write-Host "  Skill: ship  -- adversarial Opus review gate before declaring done"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $SkillsDir, $TargetShip | Out-Null
Copy-Item -LiteralPath (Join-Path $Here "skills\ship\SKILL.md") -Destination (Join-Path $TargetShip "SKILL.md") -Force

Write-Host ""
Write-Host "Installed review-gate."
Write-Host "The /ship skill is now available in Claude Code."
