[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$Sentinel = "mordor:phase1-guard"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$TargetGuard = Join-Path $ScriptsDir "guard-check.ps1"
$TargetReview = Join-Path $ScriptsDir "review-guard-log.ps1"

# ---- hook helper functions (copied verbatim from windows-state-indicator) ----

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
        hooks   = @(
            [pscustomobject]@{
                type    = "command"
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

# ---- main install --------------------------------------------------------

New-Item -ItemType Directory -Force -Path $ClaudeDir, $ScriptsDir | Out-Null
$settingsObject = Read-Settings -Path $Settings

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Settings.bak.$timestamp"
Copy-Item -LiteralPath $Settings -Destination $backup -Force

$escapedGuard = $TargetGuard.Replace('"', '\"')
$hookCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$escapedGuard`" $Sentinel"

Set-HookEvent -SettingsObject $settingsObject -EventName "PreToolUse" -Matcher "Bash" -Command $hookCommand

$proposed = $settingsObject | ConvertTo-Json -Depth 50

Write-Host ""
Write-Host "Install phase1-guard"
Write-Host "Settings: $Settings"
Write-Host "Backup:   $backup"
Write-Host "Scripts:  $TargetGuard"
Write-Host "          $TargetReview"
Write-Host "Sentinel: $Sentinel"
Write-Host ""
Write-Host "Changes:"
Write-Host "  PreToolUse (matcher: Bash) -> run destructive-command guard (LOG-ONLY)"
Write-Host ""
Write-Host "NOTE: This guard installs in LOG-ONLY mode. It NEVER blocks."
Write-Host "  Review the log: powershell -File `"$TargetReview`""
Write-Host "  To enforce:     set env:MORDOR_GUARD_MODE = 'enforce' before starting Claude Code"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted. Backup retained at $backup"
        exit 1
    }
}

Copy-Item -LiteralPath (Join-Path $Here "scripts\guard-check.ps1") -Destination $TargetGuard -Force
Copy-Item -LiteralPath (Join-Path $Here "scripts\review-guard-log.ps1") -Destination $TargetReview -Force

try {
    $proposed | ConvertFrom-Json -ErrorAction Stop | Out-Null
    $proposed | Set-Content -LiteralPath $Settings -Encoding UTF8
    Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop | Out-Null
} catch {
    Copy-Item -LiteralPath $backup -Destination $Settings -Force
    throw "Install failed and settings backup was restored. $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Installed phase1-guard. Restart Claude Code to activate the hook."
Write-Host ""
Write-Host "*** GUARD IS IN LOG-ONLY MODE ***"
Write-Host "Review flagged commands: powershell -File `"$TargetReview`""
Write-Host "Log location:            $(Join-Path $ClaudeDir 'guard-log.jsonl')"
Write-Host "To promote to enforce:   set MORDOR_GUARD_MODE=enforce in your environment"
