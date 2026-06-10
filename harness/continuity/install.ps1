[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$Sentinel = "mordor:continuity"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$SkillsDir = Join-Path $ClaudeDir "skills"
$TargetScript = Join-Path $ScriptsDir "session-context.ps1"
$TargetHandoff = Join-Path $SkillsDir "handoff"
$TargetCloseOut = Join-Path $SkillsDir "close-out"
$TargetMap = Join-Path $SkillsDir "map"

function Read-Settings {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        "{}" | Set-Content -LiteralPath $Path -Encoding UTF8
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
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

New-Item -ItemType Directory -Force -Path $ClaudeDir, $ScriptsDir, $SkillsDir | Out-Null
$settingsObject = Read-Settings -Path $Settings

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Settings.bak.$timestamp"
Copy-Item -LiteralPath $Settings -Destination $backup -Force

$escapedScript = $TargetScript.Replace('"', '\"')
$hookCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$escapedScript`" $Sentinel"

Set-HookEvent -SettingsObject $settingsObject -EventName "SessionStart" -Matcher "" -Command $hookCommand

$proposed = $settingsObject | ConvertTo-Json -Depth 50

Write-Host ""
Write-Host "Install continuity"
Write-Host "Settings: $Settings"
Write-Host "Backup:   $backup"
Write-Host "Scripts:  $TargetScript"
Write-Host "Skills:   $TargetHandoff"
Write-Host "          $TargetCloseOut"
Write-Host "          $TargetMap"
Write-Host "Sentinel: $Sentinel"
Write-Host ""
Write-Host "Changes:"
Write-Host "  SessionStart hook -> injects git context, project map, open markers, test status, pending handoff"
Write-Host "  Skills: handoff, close-out, map"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted. Backup retained at $backup"
        exit 1
    }
}

Copy-Item -LiteralPath (Join-Path $Here "scripts\session-context.ps1") -Destination $TargetScript -Force

New-Item -ItemType Directory -Force -Path $TargetHandoff, $TargetCloseOut, $TargetMap | Out-Null
Copy-Item -LiteralPath (Join-Path $Here "skills\handoff\SKILL.md") -Destination (Join-Path $TargetHandoff "SKILL.md") -Force
Copy-Item -LiteralPath (Join-Path $Here "skills\close-out\SKILL.md") -Destination (Join-Path $TargetCloseOut "SKILL.md") -Force
Copy-Item -LiteralPath (Join-Path $Here "skills\map\SKILL.md") -Destination (Join-Path $TargetMap "SKILL.md") -Force

try {
    $proposed | ConvertFrom-Json -ErrorAction Stop | Out-Null
    $proposed | Set-Content -LiteralPath $Settings -Encoding UTF8
    Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop | Out-Null
} catch {
    Copy-Item -LiteralPath $backup -Destination $Settings -Force
    throw "Install failed and settings backup was restored. $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Installed continuity."
Write-Host "Restart Claude Code to activate the SessionStart hook."
