# review-guard-log.ps1
# Prints a summary of ~/.claude/guard-log.jsonl:
#   - counts by matchedPattern
#   - last 20 entries (full detail)
# Run this to review what phase1-guard would have blocked.

$ErrorActionPreference = "SilentlyContinue"

$logPath = Join-Path $env:USERPROFILE ".claude\guard-log.jsonl"

if (-not (Test-Path -LiteralPath $logPath)) {
    Write-Host "No guard log found at $logPath"
    Write-Host "Nothing has been flagged yet (or the guard is not installed)."
    exit 0
}

$lines = Get-Content -LiteralPath $logPath -Encoding UTF8
if ($null -eq $lines -or $lines.Count -eq 0) {
    Write-Host "Guard log exists but is empty. Nothing flagged yet."
    exit 0
}

$entries = @()
foreach ($line in $lines) {
    $line = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $obj = $line | ConvertFrom-Json -ErrorAction Stop
        $entries += $obj
    } catch {
        # skip malformed lines
    }
}

if ($entries.Count -eq 0) {
    Write-Host "Guard log has no parseable entries."
    exit 0
}

Write-Host ""
Write-Host "=== phase1-guard log: $($entries.Count) total flagged event(s) ==="
Write-Host "Log file: $logPath"
Write-Host ""

# Counts by matchedPattern
Write-Host "--- Counts by matched pattern ---"
$grouped = @{}
foreach ($e in $entries) {
    $p = [string]$e.matchedPattern
    if ($grouped.ContainsKey($p)) {
        $grouped[$p]++
    } else {
        $grouped[$p] = 1
    }
}
$grouped.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    Write-Host ("  {0,4}x  {1}" -f $_.Value, $_.Key)
}

Write-Host ""
Write-Host "--- Last 20 entries (newest last) ---"

$last20 = $entries
if ($entries.Count -gt 20) {
    $last20 = $entries[($entries.Count - 20)..($entries.Count - 1)]
}

foreach ($e in $last20) {
    $ts      = [string]$e.ts
    $tool    = [string]$e.tool
    $pattern = [string]$e.matchedPattern
    $cmd     = [string]$e.command
    $mode    = [string]$e.mode
    Write-Host ""
    Write-Host "  ts:      $ts"
    Write-Host "  tool:    $tool"
    Write-Host "  mode:    $mode"
    Write-Host "  pattern: $pattern"
    Write-Host "  command: $cmd"
}

Write-Host ""
Write-Host "=== To promote to enforce mode: set env:MORDOR_GUARD_MODE = 'enforce' ==="
Write-Host "  (in your shell before starting Claude Code, or add to settings.json env block)"
Write-Host ""
