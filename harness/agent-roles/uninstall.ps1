[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$SentinelStart = "<!-- mordor:agent-roles start -->"
$SentinelEnd = "<!-- mordor:agent-roles end -->"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$AgentsDir = Join-Path $ClaudeDir "agents"
$ClaudeMd = Join-Path $ClaudeDir "CLAUDE.md"
$RoleFiles = @("scout.md", "researcher.md", "scholar.md", "builder.md", "reviewer.md", "architect.md")

foreach ($file in $RoleFiles) {
    $path = Join-Path $AgentsDir $file
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        Write-Host "Removed $path"
    }
}

if (Test-Path -LiteralPath $ClaudeMd) {
    $content = Get-Content -LiteralPath $ClaudeMd -Raw -Encoding UTF8
    $startIdx = $content.IndexOf($SentinelStart)
    $endIdx = $content.IndexOf($SentinelEnd)
    if ($startIdx -ge 0 -and $endIdx -gt $startIdx) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        Copy-Item -LiteralPath $ClaudeMd -Destination "$ClaudeMd.bak.$timestamp" -Force
        $before = $content.Substring(0, $startIdx).TrimEnd()
        $after = $content.Substring($endIdx + $SentinelEnd.Length).TrimStart()
        $parts = @($before, $after) | Where-Object { $_ }
        $updated = ($parts -join "`r`n`r`n").TrimEnd()
        if ([string]::IsNullOrWhiteSpace($updated)) {
            Remove-Item -LiteralPath $ClaudeMd -Force
            Write-Host "Removed $ClaudeMd (contained only the doctrine block)"
        } else {
            ($updated + "`r`n") | Set-Content -LiteralPath $ClaudeMd -Encoding UTF8 -NoNewline
            Write-Host "Removed doctrine block from $ClaudeMd"
        }
    }
}

Write-Host "Uninstalled agent-roles."
