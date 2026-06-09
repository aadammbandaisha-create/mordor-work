[CmdletBinding()]
param(
    [int]$Port = 7777,
    [switch]$Lan,
    [switch]$Background
)

$ErrorActionPreference = "Stop"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$ServerJs = Join-Path $ClaudeDir "scripts\webdash\server.js"
$PidFile  = Join-Path $ClaudeDir "webdash.pid"

if (-not (Test-Path -LiteralPath $ServerJs)) {
    Write-Host "server.js not found at $ServerJs"
    Write-Host "Run install.ps1 first."
    exit 1
}

$bindAddr = if ($Lan) { "0.0.0.0" } else { "127.0.0.1" }

$env:WEBDASH_PORT = [string]$Port
$env:WEBDASH_BIND = $bindAddr
$env:CLAUDE_DIR   = $ClaudeDir

$localUrl = "http://127.0.0.1:$Port"
Write-Host "web-dash URL: $localUrl"

if ($Lan) {
    $lanIp = $null
    try {
        $lanIp = (
            [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object { $_.AddressFamily -eq "InterNetwork" } |
            Select-Object -First 1
        ).IPAddressToString
    } catch {}
    if ($lanIp) {
        Write-Host "LAN URL:      http://$lanIp`:$Port"
        Write-Host "NOTE: LAN mode exposes dashboard to your local network unauthenticated."
    }
}

if ($Background) {
    $stdoutLog = Join-Path $env:TEMP "webdash-stdout.log"
    $stderrLog = Join-Path $env:TEMP "webdash-stderr.log"
    $proc = Start-Process -FilePath "node" -ArgumentList "`"$ServerJs`"" `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError  $stderrLog
    $proc.Id | Set-Content -LiteralPath $PidFile -Encoding UTF8
    # Brief wait to detect immediate startup failure
    Start-Sleep -Milliseconds 800
    if ($proc.HasExited) {
        $errText = ""
        if (Test-Path $stderrLog) { $errText = (Get-Content -LiteralPath $stderrLog -Raw -Encoding UTF8).Trim() }
        Write-Host "ERROR: web-dash node process exited immediately (exit code $($proc.ExitCode))."
        if ($errText) { Write-Host "stderr: $errText" }
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
    Write-Host "Started web-dash in background (PID $($proc.Id)). PID saved to $PidFile"
    Write-Host "Stop with: .\stop-web-dash.ps1"
    Write-Host "Startup log (if any): $stdoutLog"
    Write-Host "Error log (if any):   $stderrLog"
} else {
    Write-Host "Running web-dash in foreground. Press Ctrl+C to stop."
    & node $ServerJs
}
