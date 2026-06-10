[CmdletBinding()]
param(
    [int]$Port = 7777,
    [switch]$Lan,
    [switch]$Background
)

$ErrorActionPreference = "Stop"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$ServerJs  = Join-Path $ClaudeDir "scripts\webdash\server.js"
$PidFile   = Join-Path $ClaudeDir "webdash.pid"
$TokenFile = Join-Path $ClaudeDir "webdash-token"

if (-not (Test-Path -LiteralPath $ServerJs)) {
    Write-Host "server.js not found at $ServerJs"
    Write-Host "Run install.ps1 first."
    exit 1
}

# Ensure webdash-token exists; create with random GUID if missing.
# Use WriteAllText with UTF8Encoding(false) to avoid BOM.
if (-not (Test-Path -LiteralPath $TokenFile)) {
    $token = [System.Guid]::NewGuid().ToString()
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($TokenFile, $token, $utf8NoBom)
    Write-Host "Created webdash-token at $TokenFile"
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
    }

    # Read token for display (created above if it was missing)
    $tokenDisplay = ""
    try {
        $tokenDisplay = ([System.IO.File]::ReadAllText($TokenFile)).Trim()
    } catch {}
    Write-Host ""
    Write-Host "WARNING: LAN mode enabled."
    Write-Host "  The command deck can EXECUTE prompts on this machine from the network."
    Write-Host "  The token below is the only lock protecting dispatch endpoints."
    Write-Host "  Token: $tokenDisplay"
    Write-Host "  Keep this token private. Revoke by deleting $TokenFile and restarting."
    Write-Host ""
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
