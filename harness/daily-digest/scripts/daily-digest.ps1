[CmdletBinding()]
param(
    [int]$Days = 1,
    [string]$OutDir = ""
)

# Daily digest of Claude Code activity, generated from local transcripts.
# Run manually or via Windows Task Scheduler (registered by install.ps1).
# No AI calls. Always exits 0.

$ErrorActionPreference = "SilentlyContinue"

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $env:USERPROFILE ".claude\digests"
}

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

function Get-AssistantText {
    param($Message)
    if ($null -eq $Message) {
        return ""
    }
    $content = $Message.content
    if ($null -eq $content) {
        return ""
    }
    if ($content -is [string]) {
        return $content
    }
    $parts = @()
    foreach ($item in @($content)) {
        if ($item.type -eq "text" -and $item.text) {
            $parts += [string]$item.text
        }
    }
    return ($parts -join " ")
}

function Clean-Summary {
    param([string]$Text, [int]$MaxChars = 300)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }
    $clean = ($Text -replace "[\r\n]+", " " -replace "\s{2,}", " ").Trim()
    if ($clean.Length -gt $MaxChars) {
        return $clean.Substring(0, $MaxChars) + "..."
    }
    return $clean
}

function Decode-ProjectName {
    param([string]$FolderName)
    # Claude Code encodes the project folder path by replacing every \ and / with -
    # and the drive colon+backslash is encoded as -- (so C:\ becomes C--).
    # e.g. C:\Users\qq\Desktop\mutwo-windows-claude-harness
    #   -> C--Users-qq-Desktop-mutwo-windows-claude-harness
    # This encoding is lossy: a folder literally named "my-project" is
    # indistinguishable from a path separator. Best-effort decode: strip the
    # drive prefix then replace every remaining - with \ (backslash).
    $decoded = $FolderName
    if ($decoded -match '^([A-Za-z])--(.+)$') {
        $driveLetter = $Matches[1]
        $rest = $Matches[2] -replace '-', '\'
        $decoded = $driveLetter + ':\' + $rest
    }
    return $decoded
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

# Determine cutoff: start-of-day for (today - Days + 1)
$today = (Get-Date).Date
$cutoffDate = $today.AddDays(-($Days - 1))
$todayStr = $today.ToString("yyyy-MM-dd")
$yesterdayStr = $today.AddDays(-1).ToString("yyyy-MM-dd")

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outFile = Join-Path $OutDir "$todayStr.md"

# Scan all project folders
$projectFolders = Get-ChildItem -LiteralPath $projectsDir -Directory -ErrorAction SilentlyContinue

# Per-project aggregation keyed by folder name
$projects = @{}

# Global totals by model family
$globalByModel = @{}

foreach ($projFolder in @($projectFolders)) {
    $projName = $projFolder.Name
    $jsonlFiles = Get-ChildItem -LiteralPath $projFolder.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime.Date -ge $cutoffDate }

    if ($null -eq $jsonlFiles -or @($jsonlFiles).Count -eq 0) {
        continue
    }

    if (-not $projects.ContainsKey($projName)) {
        $projects[$projName] = [pscustomobject]@{
            Sessions       = [System.Collections.Generic.HashSet[string]]::new()
            InputTokens    = [int64]0
            OutputTokens   = [int64]0
            EstCostUsd     = [double]0
            LastAssistants = @{}   # key = sessionId, value = last assistant text seen
        }
    }
    $proj = $projects[$projName]

    foreach ($file in @($jsonlFiles)) {
        $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $proj.Sessions.Add($sessionId) | Out-Null

        foreach ($line in ([System.IO.File]::ReadLines($file.FullName))) {
            $evt = $null
            try {
                $evt = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                continue
            }
            if ($null -eq $evt) {
                continue
            }
            if ($evt.type -ne "assistant") {
                continue
            }

            # Filter by timestamp if available
            $evtDay = ""
            if ($evt.timestamp) {
                try {
                    $evtDay = ([datetime]$evt.timestamp).ToLocalTime().ToString("yyyy-MM-dd")
                } catch {
                    $evtDay = $file.LastWriteTime.ToString("yyyy-MM-dd")
                }
            } else {
                $evtDay = $file.LastWriteTime.ToString("yyyy-MM-dd")
            }
            if (-not [string]::IsNullOrWhiteSpace($evtDay)) {
                try {
                    if (([datetime]$evtDay) -lt $cutoffDate) {
                        continue
                    }
                } catch {}
            }

            # Usage aggregation
            if ($evt.message -and $evt.message.usage -and $null -ne $evt.message.usage.input_tokens) {
                $usage = $evt.message.usage
                $modelId = ""
                if ($evt.message.model) {
                    $modelId = [string]$evt.message.model
                }
                $family = Get-ModelFamily -ModelId $modelId

                $inTok  = [int64]$usage.input_tokens
                $outTok = if ($usage.output_tokens) { [int64]$usage.output_tokens } else { [int64]0 }
                $cwTok  = if ($usage.cache_creation_input_tokens) { [int64]$usage.cache_creation_input_tokens } else { [int64]0 }
                $crTok  = if ($usage.cache_read_input_tokens) { [int64]$usage.cache_read_input_tokens } else { [int64]0 }

                $p = $pricing[$family]
                $cost = ($inTok * $p.in + $outTok * $p.out + $cwTok * $p.cw + $crTok * $p.cr) / 1000000.0

                $proj.InputTokens  += $inTok
                $proj.OutputTokens += $outTok
                $proj.EstCostUsd   += $cost

                if (-not $globalByModel.ContainsKey($family)) {
                    $globalByModel[$family] = [pscustomobject]@{
                        InputTokens  = [int64]0
                        OutputTokens = [int64]0
                        EstCostUsd   = [double]0
                    }
                }
                $gRow = $globalByModel[$family]
                $gRow.InputTokens  += $inTok
                $gRow.OutputTokens += $outTok
                $gRow.EstCostUsd   += $cost
            }

            # Track last assistant text per session
            if ($evt.message) {
                $text = Get-AssistantText -Message $evt.message
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $proj.LastAssistants[$sessionId] = $text
                }
            }
        }
    }
}

# Build the markdown output
$lines = [System.Collections.Generic.List[string]]::new()

$lines.Add("# Claude Code Daily Digest - $todayStr")
$lines.Add("")
$lines.Add("Lookback: $Days day(s). Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$lines.Add("")
$lines.Add("---")

if ($projects.Count -eq 0) {
    $lines.Add("")
    $lines.Add("No activity found in the last $Days day(s).")
} else {
    $totalSessions = 0
    $totalIn = [int64]0
    $totalOut = [int64]0
    $totalCost = [double]0

    foreach ($projName in ($projects.Keys | Sort-Object)) {
        $proj = $projects[$projName]
        $decoded = Decode-ProjectName -FolderName $projName
        $sessionCount = $proj.Sessions.Count
        $totalSessions += $sessionCount
        $totalIn += $proj.InputTokens
        $totalOut += $proj.OutputTokens
        $totalCost += $proj.EstCostUsd

        $lines.Add("")
        $lines.Add("## $decoded")
        $lines.Add("")
        $lines.Add("- Sessions: $sessionCount")
        $lines.Add("- Tokens in: $(Format-Tokens $proj.InputTokens)")
        $lines.Add("- Tokens out: $(Format-Tokens $proj.OutputTokens)")
        $lines.Add("- Est cost: ~`${0:N4}" -f $proj.EstCostUsd)
        $lines.Add("")

        if ($proj.LastAssistants.Count -gt 0) {
            $lines.Add("**Last assistant message per session:**")
            $lines.Add("")
            foreach ($sid in ($proj.LastAssistants.Keys | Sort-Object)) {
                $summary = Clean-Summary -Text $proj.LastAssistants[$sid] -MaxChars 300
                $shortId = $sid.Substring(0, [Math]::Min(8, $sid.Length))
                $lines.Add("- ``$shortId...``: $summary")
            }
        }
    }

    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")
    $lines.Add("## Totals")
    $lines.Add("")
    $lines.Add("- Sessions: $totalSessions across $($projects.Count) project(s)")
    $lines.Add("- Tokens in (all models): $(Format-Tokens $totalIn)")
    $lines.Add("- Tokens out (all models): $(Format-Tokens $totalOut)")
    $lines.Add("")

    if ($globalByModel.Count -gt 0) {
        $lines.Add("**By model family:**")
        $lines.Add("")
        foreach ($family in ($globalByModel.Keys | Sort-Object)) {
            $gRow = $globalByModel[$family]
            $lines.Add("- ${family}: in $(Format-Tokens $gRow.InputTokens) / out $(Format-Tokens $gRow.OutputTokens) / ~`${0:N4}" -f $gRow.EstCostUsd)
        }
        $lines.Add("")
    }

    $lines.Add("**Total estimated API-equivalent cost: ~`${0:N4}**" -f $totalCost)
    $lines.Add("")
    $lines.Add("_Estimates use embedded prices and may drift. Exact figures: npx ccusage_")

    # Yesterday vs today comparison if both days exist
    $yesterdayFile = Join-Path $OutDir "$yesterdayStr.md"
    if ($Days -le 1 -and (Test-Path -LiteralPath $yesterdayFile)) {
        $ydContent = Get-Content -LiteralPath $yesterdayFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($ydContent -match 'Total estimated API-equivalent cost: ~\$([0-9.]+)') {
            $ydCost = [double]$Matches[1]
            $diff = $totalCost - $ydCost
            $sign = if ($diff -ge 0) { "+" } else { "" }
            $lines.Add("")
            $lines.Add("---")
            $lines.Add("")
            $lines.Add("**Yesterday vs today:** yesterday ~`${0:N4}, today ~`${1:N4} ({2}{3:N4})" -f $ydCost, $totalCost, $sign, $diff)
        }
    }
}

$lines.Add("")

$content = $lines -join "`n"

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($outFile, $content, $utf8NoBom)
    Write-Host $outFile
} catch {
    Write-Host "ERROR: could not write digest to $outFile - $($_.Exception.Message)"
}

exit 0
