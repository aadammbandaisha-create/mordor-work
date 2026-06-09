[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$Sentinel = "mordor:web-dash"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir    = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir   = Join-Path $ClaudeDir "scripts"
$WebdashDir   = Join-Path $ScriptsDir "webdash"
$TargetServer = Join-Path $WebdashDir "server.js"
$TargetStart  = Join-Path $ScriptsDir "start-web-dash.ps1"
$TargetStop   = Join-Path $ScriptsDir "stop-web-dash.ps1"
$PromptsFile  = Join-Path $ClaudeDir "webdash-prompts.json"

$DefaultPrompts = @(
    [pscustomobject]@{
        label  = "Status report"
        prompt = "Give me a status report: what you are doing, what is blocked, what is next."
    },
    [pscustomobject]@{
        label  = "Commit work"
        prompt = "Commit the completed work in logical commits with clear messages. Do not push."
    },
    [pscustomobject]@{
        label  = "Write handoff"
        prompt = "Write a handoff to .claude/handoff.md: completed, in-progress, decisions, blockers, exact next step."
    },
    [pscustomobject]@{
        label  = "Run tests"
        prompt = "Run the project test suite and report failures with the relevant output."
    }
)

Write-Host ""
Write-Host "Install web-dash"
Write-Host "Sentinel: $Sentinel"
Write-Host ""
Write-Host "Files to install:"
Write-Host "  $TargetServer"
Write-Host "  $TargetStart"
Write-Host "  $TargetStop"
Write-Host ""
$promptsNote = if (Test-Path -LiteralPath $PromptsFile) {
    "$PromptsFile  (already exists - will NOT overwrite)"
} else {
    "$PromptsFile  (will seed with 4 default prompts)"
}
Write-Host "Prompts: $promptsNote"
Write-Host ""
Write-Host "No changes to settings.json."
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $ClaudeDir, $ScriptsDir, $WebdashDir | Out-Null

Copy-Item -LiteralPath (Join-Path $Here "scripts\webdash\server.js") -Destination $TargetServer -Force
Copy-Item -LiteralPath (Join-Path $Here "scripts\start-web-dash.ps1") -Destination $TargetStart -Force
Copy-Item -LiteralPath (Join-Path $Here "scripts\stop-web-dash.ps1") -Destination $TargetStop -Force

if (-not (Test-Path -LiteralPath $PromptsFile)) {
    $DefaultPrompts | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PromptsFile -Encoding UTF8
    Write-Host "Created $PromptsFile with 4 default prompts."
} else {
    Write-Host "Skipped prompts file (already exists)."
}

Write-Host ""
Write-Host "Installed web-dash ($Sentinel)."
Write-Host ""
Write-Host "Start the dashboard:"
Write-Host "  powershell -File `"$TargetStart`""
Write-Host "  powershell -File `"$TargetStart`" -Background"
Write-Host "  powershell -File `"$TargetStart`" -Port 8080 -Lan"
Write-Host ""
Write-Host "Stop background instance:"
Write-Host "  powershell -File `"$TargetStop`""
