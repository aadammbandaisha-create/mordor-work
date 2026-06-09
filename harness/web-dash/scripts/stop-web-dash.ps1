[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$PidFile   = Join-Path $ClaudeDir "webdash.pid"

if (-not (Test-Path -LiteralPath $PidFile)) {
    Write-Host "web-dash is not running (no pidfile found)."
    exit 0
}

$pidStr = (Get-Content -LiteralPath $PidFile -Raw -Encoding UTF8).Trim()
$webdashPid = $null
if (-not [int]::TryParse($pidStr, [ref]$webdashPid)) {
    Write-Host "Invalid PID in pidfile ($pidStr). Removing pidfile."
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    exit 0
}

$proc = Get-Process -Id $webdashPid -ErrorAction SilentlyContinue
if ($null -eq $proc) {
    Write-Host "web-dash process (PID $webdashPid) is not running. Removing stale pidfile."
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    exit 0
}

Stop-Process -Id $webdashPid -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
Write-Host "Stopped web-dash (PID $webdashPid)."
