[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Sentinel = "mutwo:token-economy"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$TargetStatusline = Join-Path $ScriptsDir "claude-statusline.ps1"
$TargetReport = Join-Path $ScriptsDir "usage-report.ps1"

if (-not (Test-Path -LiteralPath $Settings)) {
    Write-Host "No settings file found. Nothing to uninstall."
    exit 0
}

$settingsObject = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json -ErrorAction Stop

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Settings.bak.$timestamp"
Copy-Item -LiteralPath $Settings -Destination $backup -Force

$removed = $false
if ($settingsObject.PSObject.Properties.Name -contains "statusLine" -and $settingsObject.statusLine) {
    $command = [string]$settingsObject.statusLine.command
    if ($command.Contains($Sentinel)) {
        $settingsObject.PSObject.Properties.Remove("statusLine")
        $removed = $true
    }
}

if ($removed) {
    $proposed = $settingsObject | ConvertTo-Json -Depth 50
    try {
        $proposed | ConvertFrom-Json -ErrorAction Stop | Out-Null
        $proposed | Set-Content -LiteralPath $Settings -Encoding UTF8
    } catch {
        Copy-Item -LiteralPath $backup -Destination $Settings -Force
        throw "Uninstall failed and settings backup was restored. $($_.Exception.Message)"
    }
    Write-Host "Removed statusLine entry owned by $Sentinel."
} else {
    Write-Host "No statusLine entry owned by $Sentinel found. Settings unchanged."
}

foreach ($file in @($TargetStatusline, $TargetReport)) {
    if (Test-Path -LiteralPath $file) {
        Remove-Item -LiteralPath $file -Force
        Write-Host "Removed $file"
    }
}

Write-Host "Uninstalled token-economy. Backup at $backup"
