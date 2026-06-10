[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SkillsDir = Join-Path $ClaudeDir "skills"
$TargetSkill = Join-Path $SkillsDir "scribe"
$SourceSkill = Join-Path $Here "skills\scribe"

Write-Host ""
Write-Host "Install scribe"
Write-Host "Source: $SourceSkill"
Write-Host "Target: $TargetSkill"
Write-Host ""
Write-Host "Changes:"
Write-Host "  Copy skill directory -> $TargetSkill"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $ClaudeDir, $SkillsDir, $TargetSkill | Out-Null
Copy-Item -LiteralPath (Join-Path $SourceSkill "SKILL.md") -Destination (Join-Path $TargetSkill "SKILL.md") -Force

Write-Host ""
Write-Host "Installed scribe."
Write-Host "Use /scribe (or 'record what we learned') in any session to capture path-scoped rules."
