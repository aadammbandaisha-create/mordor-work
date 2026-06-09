[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$ModName = "visual-verify"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$TargetSkillDir = Join-Path $ClaudeDir "skills\$ModName"
$SourceSkillDir = Join-Path $Here "skills\$ModName"

Write-Host ""
Write-Host "Install $ModName"
Write-Host "Source:      $SourceSkillDir"
Write-Host "Destination: $TargetSkillDir"
Write-Host ""
Write-Host "Changes:"
Write-Host "  Copy skills\$ModName\ -> $TargetSkillDir"
Write-Host "  (no settings.json changes)"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $SourceSkillDir)) {
    throw "Source skill directory not found: $SourceSkillDir"
}

New-Item -ItemType Directory -Force -Path $TargetSkillDir | Out-Null

Copy-Item -LiteralPath (Join-Path $SourceSkillDir "SKILL.md") `
          -Destination (Join-Path $TargetSkillDir "SKILL.md") `
          -Force

$written = Join-Path $TargetSkillDir "SKILL.md"
if (-not (Test-Path -LiteralPath $written)) {
    throw "SKILL.md was not written to $written"
}

$content = Get-Content -LiteralPath $written -Raw -Encoding UTF8
if (-not $content.Contains("name: $ModName")) {
    throw "SKILL.md at $written does not contain expected frontmatter name: $ModName"
}

Write-Host ""
Write-Host "Installed $ModName."
Write-Host "Restart Claude Code (or start a new session) to load the skill."
