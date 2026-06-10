[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SkillsDir = Join-Path $ClaudeDir "skills"
$TargetShip = Join-Path $SkillsDir "ship"

if (Test-Path -LiteralPath $TargetShip) {
    Remove-Item -LiteralPath $TargetShip -Recurse -Force
    Write-Host "Removed $TargetShip"
} else {
    Write-Host "Skill dir not found, nothing to remove: $TargetShip"
}

Write-Host "Uninstalled review-gate."
