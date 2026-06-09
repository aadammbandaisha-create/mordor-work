[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$AutoStart
)

$ErrorActionPreference = "Stop"

$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$Src       = Join-Path $Here "scripts\show-mission-control.ps1"
$Target    = Join-Path $ScriptsDir "show-mission-control.ps1"

$StartupDir = [System.Environment]::GetFolderPath("Startup")
$LnkPath    = Join-Path $StartupDir "mission-control.lnk"

Write-Host ""
Write-Host "Install mission-control"
Write-Host "Script:  $Target"
if ($AutoStart) {
    Write-Host "Startup: $LnkPath"
} else {
    Write-Host "Startup: (skipped -- pass -AutoStart to create)"
}
Write-Host ""
Write-Host "No settings.json changes."
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $ClaudeDir, $ScriptsDir | Out-Null
Copy-Item -LiteralPath $Src -Destination $Target -Force

if ($AutoStart) {
    $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
    $wsh   = New-Object -ComObject WScript.Shell
    $lnk   = $wsh.CreateShortcut($LnkPath)
    $lnk.TargetPath       = $psExe
    $lnk.Arguments        = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Target`""
    $lnk.WorkingDirectory = $ClaudeDir
    $lnk.Description      = "mission-control dashboard (mutwo:mission-control)"
    $lnk.Save()
    Write-Host "Created startup shortcut: $LnkPath"
}

Write-Host ""
Write-Host "Installed mission-control."
Write-Host "Run: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Target`""
