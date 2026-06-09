[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ModName = "visual-verify"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$TargetSkillDir = Join-Path $ClaudeDir "skills\$ModName"

if (Test-Path -LiteralPath $TargetSkillDir) {
    Remove-Item -LiteralPath $TargetSkillDir -Recurse -Force
    Write-Host "Removed $TargetSkillDir"
} else {
    Write-Host "$TargetSkillDir not found. Nothing to remove."
}

Write-Host "Uninstalled $ModName."
