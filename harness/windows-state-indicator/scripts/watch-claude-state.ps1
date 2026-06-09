[CmdletBinding()]
param(
    [int]$IntervalSeconds = 1
)

$ErrorActionPreference = "SilentlyContinue"
$stateDir = Join-Path $env:USERPROFILE ".claude\state"

Write-Host "Watching Claude state files in $stateDir"
Write-Host "Press Ctrl+C to stop."

while ($true) {
    $latest = Get-ChildItem -LiteralPath $stateDir -Filter "*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        try {
            $state = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            $summary = [string]$state.summary
            if ($summary.Length -gt 90) {
                $summary = $summary.Substring(0, 90)
            }
            [Console]::Title = "Claude $($state.label) $summary"
        } catch {}
    } else {
        [Console]::Title = "Claude state watcher"
    }

    Start-Sleep -Seconds $IntervalSeconds
}
