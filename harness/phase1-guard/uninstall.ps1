[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Sentinel = "mordor:phase1-guard"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings = Join-Path $ClaudeDir "settings.json"
$ScriptsDir = Join-Path $ClaudeDir "scripts"
$TargetGuard = Join-Path $ScriptsDir "guard-check.ps1"
$TargetReview = Join-Path $ScriptsDir "review-guard-log.ps1"

if (-not (Test-Path -LiteralPath $Settings)) {
    Write-Host "No settings file found. Removing scripts only."
    foreach ($f in @($TargetGuard, $TargetReview)) {
        if (Test-Path -LiteralPath $f) {
            Remove-Item -LiteralPath $f -Force
            Write-Host "Removed $f"
        }
    }
    exit 0
}

$settingsObject = Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Settings.bak.$timestamp"
Copy-Item -LiteralPath $Settings -Destination $backup -Force

$removed = $false
if (($settingsObject.PSObject.Properties.Name -contains "hooks") -and
    ($settingsObject.hooks.PSObject.Properties.Name -contains "PreToolUse")) {

    $entries = @($settingsObject.hooks.PreToolUse)
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
        $settingsObject.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue $kept -Force
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
    Write-Host "Removed PreToolUse entry owned by $Sentinel."
} else {
    Write-Host "No PreToolUse entry owned by $Sentinel found. Settings unchanged."
}

foreach ($f in @($TargetGuard, $TargetReview)) {
    if (Test-Path -LiteralPath $f) {
        Remove-Item -LiteralPath $f -Force
        Write-Host "Removed $f"
    }
}

Write-Host "Uninstalled phase1-guard. Backup at $backup"
Write-Host ""
Write-Host "NOTE: guard-log.jsonl was NOT removed (it is your audit data)."
Write-Host "      Location: $(Join-Path $ClaudeDir 'guard-log.jsonl')"
Write-Host "      Delete it manually if no longer needed."
