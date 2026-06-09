[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$Sentinel = "mutwo:token-economy"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$TargetStatusline = Join-Path $ScriptsDir "claude-statusline.ps1"
$TargetReport = Join-Path $ScriptsDir "usage-report.ps1"

function Read-Settings {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        "{}" | Set-Content -LiteralPath $Path -Encoding UTF8
    }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "$Path is not valid JSON. Fix it manually before installing. $($_.Exception.Message)"
    }
}

New-Item -ItemType Directory -Force -Path $ClaudeDir, $ScriptsDir | Out-Null
$settingsObject = Read-Settings -Path $Settings

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Settings.bak.$timestamp"
Copy-Item -LiteralPath $Settings -Destination $backup -Force

$escapedStatusline = $TargetStatusline.Replace('"', '\"')
$statuslineCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$escapedStatusline`" $Sentinel"

$existingStatusline = $null
if ($settingsObject.PSObject.Properties.Name -contains "statusLine" -and $settingsObject.statusLine) {
    $existingStatusline = [string]$settingsObject.statusLine.command
}
if ($existingStatusline -and -not $existingStatusline.Contains($Sentinel)) {
    Write-Host ""
    Write-Host "WARNING: an existing statusLine is configured that this mod does not own:"
    Write-Host "  $existingStatusline"
    Write-Host "It will be replaced. The previous settings are in the backup."
}

$settingsObject | Add-Member -NotePropertyName "statusLine" -NotePropertyValue ([pscustomobject]@{
    type = "command"
    command = $statuslineCommand
}) -Force

$proposed = $settingsObject | ConvertTo-Json -Depth 50

Write-Host ""
Write-Host "Install token-economy"
Write-Host "Settings: $Settings"
Write-Host "Backup:   $backup"
Write-Host "Scripts:  $TargetStatusline"
Write-Host "          $TargetReport"
Write-Host "Sentinel: $Sentinel"
Write-Host ""
Write-Host "Changes:"
Write-Host "  statusLine -> context % / session cost / model / git branch"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted. Backup retained at $backup"
        exit 1
    }
}

Copy-Item -LiteralPath (Join-Path $Here "scripts\claude-statusline.ps1") -Destination $TargetStatusline -Force
Copy-Item -LiteralPath (Join-Path $Here "scripts\usage-report.ps1") -Destination $TargetReport -Force

try {
    $proposed | ConvertFrom-Json -ErrorAction Stop | Out-Null
    $proposed | Set-Content -LiteralPath $Settings -Encoding UTF8
    Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
} catch {
    Copy-Item -LiteralPath $backup -Destination $Settings -Force
    throw "Install failed and settings backup was restored. $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Installed token-economy."
Write-Host "Restart Claude Code to activate the statusline."
Write-Host "Usage report: powershell -File `"$TargetReport`" -Days 7"
