[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ClaudeDir  = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$Target     = Join-Path $ScriptsDir "show-mission-control.ps1"
$PosFile    = Join-Path $ClaudeDir "mission-control.pos"

$StartupDir = [System.Environment]::GetFolderPath("Startup")
$LnkPath    = Join-Path $StartupDir "mission-control.lnk"

Write-Host ""
Write-Host "Uninstall mission-control"
Write-Host ""

if (Test-Path -LiteralPath $Target) {
    Remove-Item -LiteralPath $Target -Force
    Write-Host "Removed $Target"
} else {
    Write-Host "Script not found (already removed): $Target"
}

if (Test-Path -LiteralPath $LnkPath) {
    Remove-Item -LiteralPath $LnkPath -Force
    Write-Host "Removed startup shortcut: $LnkPath"
} else {
    Write-Host "No startup shortcut found (already removed or -AutoStart was never used)."
}

if (Test-Path -LiteralPath $PosFile) {
    Remove-Item -LiteralPath $PosFile -Force
    Write-Host "Removed position file: $PosFile"
} else {
    Write-Host "No position file found."
}

Write-Host ""
Write-Host "Uninstalled mission-control."
