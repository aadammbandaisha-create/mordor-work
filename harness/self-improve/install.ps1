[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SkillsDir = Join-Path $ClaudeDir "skills"
$TargetSkillDir = Join-Path $SkillsDir "self-improve"
$TargetSkillMd = Join-Path $TargetSkillDir "SKILL.md"
$TargetScriptsDir = Join-Path $TargetSkillDir "scripts"
$TargetScan = Join-Path $TargetScriptsDir "friction-scan.ps1"

$SourceSkillMd = Join-Path $Here "skills\self-improve\SKILL.md"
$SourceScan = Join-Path $Here "skills\self-improve\scripts\friction-scan.ps1"

Write-Host ""
Write-Host "Install self-improve"
Write-Host "Skill dir: $TargetSkillDir"
Write-Host "Files:     $TargetSkillMd"
Write-Host "           $TargetScan"
Write-Host ""
Write-Host "No settings.json changes. This mod only copies skill files."
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $TargetSkillDir, $TargetScriptsDir | Out-Null

Copy-Item -LiteralPath $SourceSkillMd -Destination $TargetSkillMd -Force
Copy-Item -LiteralPath $SourceScan -Destination $TargetScan -Force

Write-Host ""
Write-Host "Installed self-improve."
Write-Host "Run the skill with /self-improve or 'improve the harness'."
Write-Host "Scanner: powershell -File `"$TargetScan`" -Days 7"
