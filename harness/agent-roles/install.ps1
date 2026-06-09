[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$SentinelStart = "<!-- mordor:agent-roles start -->"
$SentinelEnd = "<!-- mordor:agent-roles end -->"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$AgentsDir = Join-Path $ClaudeDir "agents"
$ClaudeMd = Join-Path $ClaudeDir "CLAUDE.md"
$RoleFiles = @("scout.md", "researcher.md", "scholar.md", "builder.md", "reviewer.md", "architect.md")

Write-Host ""
Write-Host "Install agent-roles"
Write-Host "Agents:   $AgentsDir  ($($RoleFiles -join ', '))"
Write-Host "Doctrine: $ClaudeMd  (sentinel-owned block)"
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $ClaudeDir, $AgentsDir | Out-Null

foreach ($file in $RoleFiles) {
    Copy-Item -LiteralPath (Join-Path $Here "agents\$file") -Destination (Join-Path $AgentsDir $file) -Force
}

$doctrine = (Get-Content -LiteralPath (Join-Path $Here "doctrine.md") -Raw -Encoding UTF8).TrimEnd()

$existing = ""
if (Test-Path -LiteralPath $ClaudeMd) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item -LiteralPath $ClaudeMd -Destination "$ClaudeMd.bak.$timestamp" -Force
    $existing = Get-Content -LiteralPath $ClaudeMd -Raw -Encoding UTF8
}

$startIdx = $existing.IndexOf($SentinelStart)
$endIdx = $existing.IndexOf($SentinelEnd)
if ($startIdx -ge 0 -and $endIdx -gt $startIdx) {
    $before = $existing.Substring(0, $startIdx).TrimEnd()
    $after = $existing.Substring($endIdx + $SentinelEnd.Length).TrimStart()
    $parts = @($before, $doctrine, $after) | Where-Object { $_ }
    $updated = ($parts -join "`r`n`r`n").TrimEnd() + "`r`n"
} elseif ([string]::IsNullOrWhiteSpace($existing)) {
    $updated = $doctrine + "`r`n"
} else {
    $updated = $existing.TrimEnd() + "`r`n`r`n" + $doctrine + "`r`n"
}

$updated | Set-Content -LiteralPath $ClaudeMd -Encoding UTF8 -NoNewline

Write-Host ""
Write-Host "Installed agent-roles."
Write-Host "Restart Claude Code (or start a new session) to load the roles and doctrine."
