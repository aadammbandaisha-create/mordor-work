[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Sentinel = "mutwo:continuity"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$SkillsDir = Join-Path $ClaudeDir "skills"
$TargetScript = Join-Path $ScriptsDir "session-context.ps1"
$TargetHandoff = Join-Path $SkillsDir "handoff"
$TargetCloseOut = Join-Path $SkillsDir "close-out"

if (-not (Test-Path -LiteralPath $Settings)) {
    Write-Host "No settings file found. Nothing to uninstall."
} else {
    $settingsObject = Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "$Settings.bak.$timestamp"
    Copy-Item -LiteralPath $Settings -Destination $backup -Force

    $changed = $false

    if ($settingsObject.PSObject.Properties.Name -contains "hooks" -and $null -ne $settingsObject.hooks) {
        $eventNames = @($settingsObject.hooks.PSObject.Properties.Name)
        foreach ($eventName in $eventNames) {
            $entries = @($settingsObject.hooks.$eventName)
            $kept = @()
            foreach ($entry in $entries) {
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
                } else {
                    $changed = $true
                }
            }
            $settingsObject.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue $kept -Force
        }
    }

    if ($changed) {
        $proposed = $settingsObject | ConvertTo-Json -Depth 50
        try {
            $proposed | ConvertFrom-Json -ErrorAction Stop | Out-Null
            $proposed | Set-Content -LiteralPath $Settings -Encoding UTF8
        } catch {
            Copy-Item -LiteralPath $backup -Destination $Settings -Force
            throw "Uninstall failed and settings backup was restored. $($_.Exception.Message)"
        }
        Write-Host "Removed SessionStart hook entry owned by $Sentinel."
    } else {
        Write-Host "No hook entries owned by $Sentinel found. Settings unchanged."
    }

    Write-Host "Backup at $backup"
}

if (Test-Path -LiteralPath $TargetScript) {
    Remove-Item -LiteralPath $TargetScript -Force
    Write-Host "Removed $TargetScript"
}

foreach ($dir in @($TargetHandoff, $TargetCloseOut)) {
    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force
        Write-Host "Removed $dir"
    }
}

Write-Host "Uninstalled continuity."
