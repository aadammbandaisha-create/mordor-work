[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$NoSchedule,
    [switch]$WithPodcast
)

$ErrorActionPreference = "Stop"

$ModName          = "daily-digest"
$TaskName         = "mordor-daily-digest"
$PodcastTaskName  = "mordor-morning-podcast"
$Here             = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir        = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir       = Join-Path $ClaudeDir "scripts"
$TargetScript     = Join-Path $ScriptsDir "daily-digest.ps1"
$DigestsDir       = Join-Path $ClaudeDir "digests"

# No settings.json involvement for this mod.

Write-Host ""
Write-Host "Install $ModName"
Write-Host "Script:  $TargetScript"
Write-Host "Digests: $DigestsDir  (created on first run)"
if ($NoSchedule) {
    Write-Host "Task:    skipped (-NoSchedule)"
} else {
    Write-Host "Task:    $TaskName  (DAILY 08:00, current user)"
    if ($WithPodcast) {
        Write-Host "Task:    $PodcastTaskName  (DAILY 07:30, current user) -- runs daily-digest.ps1 -Speak"
    }
}
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $ClaudeDir, $ScriptsDir | Out-Null

Copy-Item -LiteralPath (Join-Path $Here "scripts\daily-digest.ps1") -Destination $TargetScript -Force
Write-Host "Copied $TargetScript"

if (-not $NoSchedule) {
    # Register the plain text digest task at 08:00
    $taskCommand = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TargetScript`""
    $schtasksArgs = @(
        "/Create",
        "/F",
        "/TN", $TaskName,
        "/SC", "DAILY",
        "/ST", "08:00",
        "/TR", $taskCommand
    )
    Write-Host "Registering scheduled task $TaskName ..."
    $schtasksOut = & schtasks.exe $schtasksArgs 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Scheduled task created: $TaskName  (DAILY 08:00)"
    } else {
        Write-Host ""
        Write-Host "WARNING: schtasks /Create failed (exit $LASTEXITCODE). This may require elevated privileges."
        Write-Host "Output: $schtasksOut"
        Write-Host ""
        Write-Host "To register the task manually, run as Administrator:"
        Write-Host "  schtasks /Create /F /TN $TaskName /SC DAILY /ST 08:00 /TR `"$taskCommand`""
        Write-Host ""
        Write-Host "Or run the digest manually at any time:"
        Write-Host "  powershell -File `"$TargetScript`""
    }

    # Optionally register the morning podcast task at 07:30
    if ($WithPodcast) {
        $podcastCommand = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TargetScript`" -Speak"
        $podcastArgs = @(
            "/Create",
            "/F",
            "/TN", $PodcastTaskName,
            "/SC", "DAILY",
            "/ST", "07:30",
            "/TR", $podcastCommand
        )
        Write-Host "Registering scheduled task $PodcastTaskName ..."
        $podcastOut = & schtasks.exe $podcastArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Scheduled task created: $PodcastTaskName  (DAILY 07:30)"
        } else {
            Write-Host ""
            Write-Host "WARNING: schtasks /Create failed for $PodcastTaskName (exit $LASTEXITCODE)."
            Write-Host "Output: $podcastOut"
            Write-Host ""
            Write-Host "To register the podcast task manually, run as Administrator:"
            Write-Host "  schtasks /Create /F /TN $PodcastTaskName /SC DAILY /ST 07:30 /TR `"$podcastCommand`""
        }
    }
}

Write-Host ""
Write-Host "Installed $ModName."
Write-Host "Run manually: powershell -File `"$TargetScript`""
Write-Host "Run with options: powershell -File `"$TargetScript`" -Days 7"
if ($WithPodcast) {
    Write-Host "Run podcast:  powershell -File `"$TargetScript`" -Speak"
    Write-Host "Run with playback: powershell -File `"$TargetScript`" -Play"
}
Write-Host "Digests are written to: $DigestsDir"
