[CmdletBinding()]
param(
    [switch]$RemoveState,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$Sentinel = "mutwo:windows-state-indicator"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$TargetState = Join-Path $ScriptsDir "claude-state.ps1"
$TargetWatch = Join-Path $ScriptsDir "watch-claude-state.ps1"
$TargetLight = Join-Path $ScriptsDir "show-claude-state-light.ps1"
$StateDir = Join-Path $ClaudeDir "state"

function Remove-OwnedEntries {
    param($Entries)
    $kept = @()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) {
            continue
        }
        $owned = $false
        foreach ($hook in @($entry.hooks)) {
            $command = [string]$hook.command
            if ($command.Contains($Sentinel)) {
                $owned = $true
                break
            }
        }
        if (-not $owned) {
            $kept += $entry
        }
    }
    return $kept
}

function Get-OwnPropertyCount {
    param($Object)
    if ($null -eq $Object) {
        return 0
    }
    return @($Object.PSObject.Properties | Where-Object { $_.MemberType -in @("NoteProperty", "AliasProperty", "ScriptProperty") }).Count
}

if (-not (Test-Path -LiteralPath $Settings)) {
    Write-Host "No Claude settings file found: $Settings"
    exit 0
}

try {
    $settingsObject = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "$Settings is not valid JSON. Fix it manually before uninstalling. $($_.Exception.Message)"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Settings.bak.$timestamp"
Copy-Item -LiteralPath $Settings -Destination $backup -Force

Write-Host ""
Write-Host "Uninstall windows-state-indicator"
Write-Host "Settings: $Settings"
Write-Host "Backup:   $backup"
Write-Host "Sentinel: $Sentinel"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Remove owned hook entries and scripts? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted. Backup retained at $backup"
        exit 1
    }
}

if ($settingsObject.PSObject.Properties.Name -contains "hooks" -and $null -ne $settingsObject.hooks) {
    foreach ($eventName in @("UserPromptSubmit", "PostToolUse", "Stop", "Notification", "PreToolUse")) {
        if ($settingsObject.hooks.PSObject.Properties.Name -contains $eventName) {
            $kept = @(Remove-OwnedEntries $settingsObject.hooks.$eventName)
            if ($kept.Count -eq 0) {
                $settingsObject.hooks.PSObject.Properties.Remove($eventName)
            } else {
                $settingsObject.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue $kept -Force
            }
        }
    }
    if ((Get-OwnPropertyCount $settingsObject.hooks) -eq 0) {
        $settingsObject.PSObject.Properties.Remove("hooks")
    }
}

try {
    $json = $settingsObject | ConvertTo-Json -Depth 50
    $json | ConvertFrom-Json -ErrorAction Stop | Out-Null
    $json | Set-Content -LiteralPath $Settings -Encoding UTF8
} catch {
    Copy-Item -LiteralPath $backup -Destination $Settings -Force
    throw "Uninstall failed and settings backup was restored. $($_.Exception.Message)"
}

Remove-Item -LiteralPath $TargetState -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $TargetWatch -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $TargetLight -Force -ErrorAction SilentlyContinue

if ($RemoveState -and (Test-Path -LiteralPath $StateDir)) {
    Get-ChildItem -LiteralPath $StateDir -Filter "*.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*.json" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Removed windows-state-indicator hook entries and scripts."
