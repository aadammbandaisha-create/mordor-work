[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Sentinel = "mordor:web-dash"
$ClaudeDir    = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir   = Join-Path $ClaudeDir "scripts"
$WebdashDir   = Join-Path $ScriptsDir "webdash"
$TargetServer = Join-Path $WebdashDir "server.js"
$TargetStart  = Join-Path $ScriptsDir "start-web-dash.ps1"
$TargetStop   = Join-Path $ScriptsDir "stop-web-dash.ps1"
$PidFile      = Join-Path $ClaudeDir "webdash.pid"
$PromptsFile  = Join-Path $ClaudeDir "webdash-prompts.json"

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
if (Test-Path -LiteralPath $PromptsFile) {
    Write-Host "NOTE: $PromptsFile was NOT removed (user data). Delete it manually if you no longer need it."
}
