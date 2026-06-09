[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ModName     = "daily-digest"
$TaskName    = "mutwo-daily-digest"
$ClaudeDir   = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir  = Join-Path $ClaudeDir "scripts"
$TargetScript = Join-Path $ScriptsDir "daily-digest.ps1"

Write-Host ""
Write-Host "Uninstall $ModName"
Write-Host ""

# Remove scheduled task (ignore not-found)
$schtasksOut = & schtasks.exe /Delete /F /TN $TaskName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Removed scheduled task: $TaskName"
} else {
    $outStr = [string]$schtasksOut
    if ($outStr -match "not exist" -or $outStr -match "cannot find") {
        Write-Host "Scheduled task $TaskName not found (already removed or never created)."
    } else {
        Write-Host "WARNING: schtasks /Delete returned exit $LASTEXITCODE - $outStr"
    }
}

# Remove copied script
if (Test-Path -LiteralPath $TargetScript) {
    Remove-Item -LiteralPath $TargetScript -Force
    Write-Host "Removed $TargetScript"
} else {
    Write-Host "$TargetScript not found (already removed)."
}

# Leave digests - they are user data
$DigestsDir = Join-Path $ClaudeDir "digests"
Write-Host ""
Write-Host "Digests directory retained (user data): $DigestsDir"
Write-Host ""
Write-Host "Uninstalled $ModName."
