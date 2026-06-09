[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Sentinel = "mutwo:format-on-edit"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$TargetScript = Join-Path $ScriptsDir "format-on-edit.ps1"

if (-not (Test-Path -LiteralPath $Settings)) {
    Write-Host "No settings file found. Nothing to uninstall."
    if (Test-Path -LiteralPath $TargetScript) {
        Remove-Item -LiteralPath $TargetScript -Force
        Write-Host "Removed $TargetScript"
    }
    exit 0
}

$settingsObject = Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Settings.bak.$timestamp"
Copy-Item -LiteralPath $Settings -Destination $backup -Force

# Remove owned PostToolUse entries -- filter by Sentinel only (preserves all other mods' entries)
$removed = $false
if (($settingsObject.PSObject.Properties.Name -contains "hooks") -and
    ($settingsObject.hooks.PSObject.Properties.Name -contains "PostToolUse")) {

    $entries = @($settingsObject.hooks.PostToolUse)
    $kept = @()
    foreach ($entry in $entries) {
        if ($null -eq $entry) { continue }
        $ownedEntry = $false
        foreach ($hook in @($entry.hooks)) {
            $command = [string]$hook.command
            if ($command.Contains($Sentinel)) {
                $ownedEntry = $true
                break
            }
        }
        if ($ownedEntry) {
            $removed = $true
        } else {
            $kept += $entry
        }
    }

    if ($removed) {
        $settingsObject.hooks | Add-Member -NotePropertyName "PostToolUse" -NotePropertyValue $kept -Force
    }
}

if ($removed) {
    $proposed = $settingsObject | ConvertTo-Json -Depth 50
    try {
        $proposed | ConvertFrom-Json -ErrorAction Stop | Out-Null
        $proposed | Set-Content -LiteralPath $Settings -Encoding UTF8
        Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop | Out-Null
    } catch {
        Copy-Item -LiteralPath $backup -Destination $Settings -Force
        throw "Uninstall failed and settings backup was restored. $($_.Exception.Message)"
    }
    Write-Host "Removed PostToolUse entry owned by $Sentinel."
} else {
    Write-Host "No PostToolUse entry owned by $Sentinel found. Settings unchanged."
}

if (Test-Path -LiteralPath $TargetScript) {
    Remove-Item -LiteralPath $TargetScript -Force
    Write-Host "Removed $TargetScript"
}

Write-Host "Uninstalled format-on-edit. Backup at $backup"
