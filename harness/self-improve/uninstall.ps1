[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SkillsDir = Join-Path $ClaudeDir "skills"
$TargetSkillDir = Join-Path $SkillsDir "self-improve"

if (-not (Test-Path -LiteralPath $TargetSkillDir)) {
    Write-Host "Skill directory not found. Nothing to uninstall."
    exit 0
}

Remove-Item -LiteralPath $TargetSkillDir -Recurse -Force
Write-Host "Removed $TargetSkillDir"
Write-Host "Uninstalled self-improve."
