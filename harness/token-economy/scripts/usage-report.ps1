[CmdletBinding()]
param(
    [int]$Days = 7
)

# Aggregates token usage from local Claude Code transcripts:
#   ~\.claude\projects\**\*.jsonl
# Costs are API-equivalent estimates. On a subscription plan they represent
# value consumed against your rate limits, not a bill.
# For exact, maintained pricing use: npx ccusage

$ErrorActionPreference = "SilentlyContinue"

$projectsDir = Join-Path $env:USERPROFILE ".claude\projects"
if (-not (Test-Path -LiteralPath $projectsDir)) {
    Write-Host "No transcripts found at $projectsDir"
    exit 0
}

# USD per million tokens: input, output, cache write, cache read
$pricing = @{
    "opus"   = @{ in = 15.0; out = 75.0; cw = 18.75; cr = 1.50 }
    "sonnet" = @{ in = 3.0;  out = 15.0; cw = 3.75;  cr = 0.30 }
    "haiku"  = @{ in = 1.0;  out = 5.0;  cw = 1.25;  cr = 0.10 }
}

function Get-ModelFamily {
    param([string]$ModelId)
    foreach ($family in @("opus", "sonnet", "haiku")) {
        if ($ModelId -match $family) {
            return $family
        }
    }
    return "sonnet"
}

$cutoff = (Get-Date).Date.AddDays(-($Days - 1))
$files = Get-ChildItem -LiteralPath $projectsDir -Recurse -Filter "*.jsonl" |
    Where-Object { $_.LastWriteTime -ge $cutoff }

$byDay = @{}
$byModel = @{}

foreach ($file in $files) {
    foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
        if ($line -notmatch '"usage"') {
            continue
        }
        try {
            $evt = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        if ($evt.type -ne "assistant" -or $null -eq $evt.message -or $null -eq $evt.message.usage) {
            continue
        }
        $usage = $evt.message.usage
        if ($null -eq $usage.input_tokens) {
            continue
        }

        $day = ""
        if ($evt.timestamp) {
            try {
                $day = ([datetime]$evt.timestamp).ToLocalTime().ToString("yyyy-MM-dd")
            } catch {
                $day = $file.LastWriteTime.ToString("yyyy-MM-dd")
            }
        } else {
            $day = $file.LastWriteTime.ToString("yyyy-MM-dd")
        }
        if ($day -and ([datetime]$day) -lt $cutoff) {
            continue
        }

        $modelId = ""
        if ($evt.message.model) {
            $modelId = [string]$evt.message.model
        }
        $family = Get-ModelFamily -ModelId $modelId

        $inTok = [int64]$usage.input_tokens
        $outTok = if ($usage.output_tokens) { [int64]$usage.output_tokens } else { 0 }
        $cwTok = if ($usage.cache_creation_input_tokens) { [int64]$usage.cache_creation_input_tokens } else { 0 }
        $crTok = if ($usage.cache_read_input_tokens) { [int64]$usage.cache_read_input_tokens } else { 0 }

        $p = $pricing[$family]
        $cost = ($inTok * $p.in + $outTok * $p.out + $cwTok * $p.cw + $crTok * $p.cr) / 1000000.0

        foreach ($bucket in @(@{ map = $byDay; key = $day }, @{ map = $byModel; key = $family })) {
            if (-not $bucket.map.ContainsKey($bucket.key)) {
                $bucket.map[$bucket.key] = [pscustomobject]@{
                    InputTokens = [int64]0
                    OutputTokens = [int64]0
                    CacheWrite = [int64]0
                    CacheRead = [int64]0
                    EstCostUsd = [double]0
                }
            }
            $row = $bucket.map[$bucket.key]
            $row.InputTokens += $inTok
            $row.OutputTokens += $outTok
            $row.CacheWrite += $cwTok
            $row.CacheRead += $crTok
            $row.EstCostUsd += $cost
        }
    }
}

if ($byDay.Count -eq 0) {
    Write-Host "No usage events found in the last $Days day(s)."
    exit 0
}

function Format-Tokens {
    param([int64]$Value)
    if ($Value -ge 1000000) {
        return ("{0:N1}M" -f ($Value / 1000000.0))
    }
    if ($Value -ge 1000) {
        return ("{0:N0}k" -f ($Value / 1000.0))
    }
    return [string]$Value
}

Write-Host ""
Write-Host "Claude Code usage, last $Days day(s)"
Write-Host "===================================="
Write-Host ""
Write-Host "By day:"
$totalCost = 0.0
foreach ($day in ($byDay.Keys | Sort-Object)) {
    $row = $byDay[$day]
    $totalCost += $row.EstCostUsd
    $line = "  {0}  in {1,8}  out {2,8}  cacheW {3,8}  cacheR {4,8}  ~`${5:N2}" -f `
        $day,
        (Format-Tokens $row.InputTokens),
        (Format-Tokens $row.OutputTokens),
        (Format-Tokens $row.CacheWrite),
        (Format-Tokens $row.CacheRead),
        $row.EstCostUsd
    Write-Host $line
}

Write-Host ""
Write-Host "By model:"
foreach ($family in ($byModel.Keys | Sort-Object)) {
    $row = $byModel[$family]
    $line = "  {0,-8} out {1,8}  ~`${2:N2}" -f $family, (Format-Tokens $row.OutputTokens), $row.EstCostUsd
    Write-Host $line
}

Write-Host ""
Write-Host ("Total estimated API-equivalent cost: ~`${0:N2}" -f $totalCost)
Write-Host ""
Write-Host "Estimates use embedded prices and may drift. Exact figures: npx ccusage"
