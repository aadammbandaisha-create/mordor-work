[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Sentinel     = "mordor:web-dash"
$ClaudeDir    = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir   = Join-Path $ClaudeDir "scripts"
$WebdashDir   = Join-Path $ScriptsDir "webdash"
$TargetServer = Join-Path $WebdashDir "server.js"
$TargetStart  = Join-Path $ScriptsDir "start-web-dash.ps1"
$TargetStop   = Join-Path $ScriptsDir "stop-web-dash.ps1"
$PidFile      = Join-Path $ClaudeDir "webdash.pid"
$PromptsFile  = Join-Path $ClaudeDir "webdash-prompts.json"
$ProjectsFile = Join-Path $ClaudeDir "webdash-projects.json"
$TokenFile    = Join-Path $ClaudeDir "webdash-token"
$JobsLog      = Join-Path $ClaudeDir "webdash-jobs.log"

# Stop running instance first if pidfile exists
if (Test-Path -LiteralPath $PidFile) {
    $pidStr = ""
    try {
        $pidStr = (Get-Content -LiteralPath $PidFile -Raw -Encoding UTF8).Trim()
    } catch {}
    $webdashPid = 0
    if ($pidStr -and [int]::TryParse($pidStr, [ref]$webdashPid)) {
        $proc = Get-Process -Id $webdashPid -ErrorAction SilentlyContinue
        if ($null -ne $proc) {
            Stop-Process -Id $webdashPid -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped running web-dash process (PID $webdashPid)."
        }
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Write-Host "Removed pidfile $PidFile"
}

# Remove owned script files
foreach ($file in @($TargetServer, $TargetStart, $TargetStop)) {
    if (Test-Path -LiteralPath $file) {
        Remove-Item -LiteralPath $file -Force
        Write-Host "Removed $file"
    }
}

# Remove webdash dir if empty
if (Test-Path -LiteralPath $WebdashDir) {
    $remaining = @(Get-ChildItem -LiteralPath $WebdashDir -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        Remove-Item -LiteralPath $WebdashDir -Force -ErrorAction SilentlyContinue
        Write-Host "Removed empty dir $WebdashDir"
    }
}

Write-Host ""
Write-Host "Uninstalled $Sentinel."
Write-Host ""
Write-Host "The following user-data files were NOT removed. Delete them manually if no longer needed:"
if (Test-Path -LiteralPath $PromptsFile) {
    Write-Host "  $PromptsFile  (prompt deck configuration)"
}
if (Test-Path -LiteralPath $ProjectsFile) {
    Write-Host "  $ProjectsFile  (project allowlist for dispatch)"
}
if (Test-Path -LiteralPath $TokenFile) {
    Write-Host "  $TokenFile  (authentication token for POST endpoints)"
}
if (Test-Path -LiteralPath $JobsLog) {
    Write-Host "  $JobsLog  (append-only job audit log)"
}
