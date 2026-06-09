[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$Sentinel = "mutwo:windows-state-indicator"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$TargetState = Join-Path $ScriptsDir "claude-state.ps1"
$TargetWatch = Join-Path $ScriptsDir "watch-claude-state.ps1"
$TargetLight = Join-Path $ScriptsDir "show-claude-state-light.ps1"

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

function Ensure-PropertyObject {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not ($Object.PSObject.Properties.Name -contains $Name) -or $null -eq $Object.$Name) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{}) -Force
    }
}

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

function New-HookEntry {
    param(
        [string]$Matcher,
        [string]$Command
    )
    return [pscustomobject]@{
        matcher = $Matcher
        hooks = @(
            [pscustomobject]@{
                type = "command"
                command = $Command
            }
        )
    }
}

function Set-HookEvent {
    param(
        [Parameter(Mandatory)]$SettingsObject,
        [Parameter(Mandatory)][string]$EventName,
        [string]$Matcher,
        [Parameter(Mandatory)][string]$Command
    )
    Ensure-PropertyObject -Object $SettingsObject -Name "hooks"
    $existing = @()
    if ($SettingsObject.hooks.PSObject.Properties.Name -contains $EventName) {
        $existing = Remove-OwnedEntries $SettingsObject.hooks.$EventName
    }
    $newEntries = @($existing) + (New-HookEntry -Matcher $Matcher -Command $Command)
    $SettingsObject.hooks | Add-Member -NotePropertyName $EventName -NotePropertyValue $newEntries -Force
}

New-Item -ItemType Directory -Force -Path $ClaudeDir, $ScriptsDir | Out-Null
$settingsObject = Read-Settings -Path $Settings

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Settings.bak.$timestamp"
Copy-Item -LiteralPath $Settings -Destination $backup -Force

$escapedState = $TargetState.Replace('"', '\"')
$workingCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$escapedState`" working $Sentinel"
$idleCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$escapedState`" idle $Sentinel"

Set-HookEvent -SettingsObject $settingsObject -EventName "UserPromptSubmit" -Matcher "" -Command $workingCommand
Set-HookEvent -SettingsObject $settingsObject -EventName "PostToolUse" -Matcher "" -Command $workingCommand
Set-HookEvent -SettingsObject $settingsObject -EventName "Stop" -Matcher "" -Command $idleCommand
Set-HookEvent -SettingsObject $settingsObject -EventName "Notification" -Matcher "" -Command $idleCommand
Set-HookEvent -SettingsObject $settingsObject -EventName "PreToolUse" -Matcher "AskUserQuestion" -Command $idleCommand

$proposed = $settingsObject | ConvertTo-Json -Depth 50

Write-Host ""
Write-Host "Install windows-state-indicator"
Write-Host "Settings: $Settings"
Write-Host "Backup:   $backup"
Write-Host "Scripts:  $TargetState"
Write-Host "Sentinel: $Sentinel"
Write-Host ""
Write-Host "Hook events to install:"
Write-Host "  UserPromptSubmit -> working"
Write-Host "  PostToolUse      -> working"
Write-Host "  Stop             -> idle"
Write-Host "  Notification     -> idle"
Write-Host "  PreToolUse AskUserQuestion -> idle"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted. Backup retained at $backup"
        exit 1
    }
}

Copy-Item -LiteralPath (Join-Path $Here "scripts\claude-state.ps1") -Destination $TargetState -Force
Copy-Item -LiteralPath (Join-Path $Here "scripts\watch-claude-state.ps1") -Destination $TargetWatch -Force
Copy-Item -LiteralPath (Join-Path $Here "scripts\show-claude-state-light.ps1") -Destination $TargetLight -Force

try {
    $proposed | ConvertFrom-Json -ErrorAction Stop | Out-Null
    $proposed | Set-Content -LiteralPath $Settings -Encoding UTF8
    Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
} catch {
    Copy-Item -LiteralPath $backup -Destination $Settings -Force
    throw "Install failed and settings backup was restored. $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Installed windows-state-indicator."
Write-Host "Restart Claude Code to activate hooks."
