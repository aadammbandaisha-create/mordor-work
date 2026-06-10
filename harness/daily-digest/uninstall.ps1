[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ModName         = "daily-digest"
$TaskName        = "mordor-daily-digest"
$PodcastTaskName = "mordor-morning-podcast"
$ClaudeDir       = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir      = Join-Path $ClaudeDir "scripts"
$TargetScript    = Join-Path $ScriptsDir "daily-digest.ps1"

Write-Host ""
Write-Host "Uninstall $ModName"
Write-Host ""

# Remove the plain digest scheduled task (ignore not-found)
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

# Remove the morning podcast scheduled task if present (ignore not-found)
$podcastOut = & schtasks.exe /Delete /F /TN $PodcastTaskName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Removed scheduled task: $PodcastTaskName"
} else {
    $podcastStr = [string]$podcastOut
    if ($podcastStr -match "not exist" -or $podcastStr -match "cannot find") {
        Write-Host "Scheduled task $PodcastTaskName not found (already removed or never created)."
    } else {
        Write-Host "WARNING: schtasks /Delete returned exit $LASTEXITCODE - $podcastStr"
    }
}

# Remove copied script
if (Test-Path -LiteralPath $TargetScript) {
    Remove-Item -LiteralPath $TargetScript -Force
    Write-Host "Removed $TargetScript"
} else {
    Write-Host "$TargetScript not found (already removed)."
}

# Leave digests and narration files - they are user data
$DigestsDir = Join-Path $ClaudeDir "digests"
Write-Host ""
Write-Host "Digests directory retained (user data): $DigestsDir"
Write-Host ""
Write-Host "Uninstalled $ModName."
