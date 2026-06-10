[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SkillsDir = Join-Path $ClaudeDir "skills"
$TargetSkill = Join-Path $SkillsDir "scribe"

if (Test-Path -LiteralPath $TargetSkill) {
    Remove-Item -LiteralPath $TargetSkill -Recurse -Force
    Write-Host "Removed $TargetSkill"
} else {
    Write-Host "Skill directory not found. Nothing to remove."
}

Write-Host "Uninstalled scribe."
