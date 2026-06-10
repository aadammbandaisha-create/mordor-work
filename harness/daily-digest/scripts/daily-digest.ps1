[CmdletBinding()]
param(
    [int]$Days = 1,
    [string]$OutDir = "",
    [switch]$Narrate,
    [switch]$Speak,
    [switch]$Play
)

# Daily digest of Claude Code activity, generated from local transcripts.
# Run manually or via Windows Task Scheduler (registered by install.ps1).
# -Narrate: also write a spoken-word narration to YYYY-MM-DD.narration.txt
# -Speak  : implies -Narrate; also render a WAV via Windows SAPI (no install required)
# -Play   : implies -Speak; immediately play the WAV through the default audio device
# Always exits 0.

$ErrorActionPreference = "SilentlyContinue"

# -Play implies -Speak; -Speak implies -Narrate
if ($Play)   { $Speak   = $true }
if ($Speak)  { $Narrate = $true }

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

# ---- narration / TTS pipeline (only when -Narrate or -Speak or -Play) ----
if ($Narrate) {
    $narrationFile = Join-Path $OutDir "$todayStr.narration.txt"
    $wavFile       = Join-Path $OutDir "$todayStr.wav"
    $narration     = ""

    # Try to produce the narration via the claude CLI.
    # We write the digest to a temp file to avoid quoting nightmares.
    $claudeFound = $false
    $claudeExe   = ""

    try {
        $claudeCmd = Get-Command claude -ErrorAction Stop
        $claudeFound = $true
        $claudeExe = $claudeCmd.Source
    } catch {}

    # If Get-Command resolved a .ps1 wrapper, substitute the sibling .cmd wrapper.
    # cmd.exe cannot execute a raw .ps1 path (PATHEXT does not include .ps1),
    # so running it via cmd /c would silently produce 0 bytes of output.
    if ($claudeFound -and [System.IO.Path]::GetExtension($claudeExe) -ieq '.ps1') {
        $cmdPath = $claudeExe -replace '\.ps1$', '.cmd'
        if (Test-Path -LiteralPath $cmdPath) {
            $claudeExe = $cmdPath
        } else {
            # No sibling .cmd -- clear so we fall through to the npm probe
            $claudeFound = $false
            $claudeExe = ""
        }
    }

    # Also probe the npm global prefix path if not found above.
    # npm bin -g was removed in npm 9+; use npm prefix -g instead.
    if (-not $claudeFound) {
        $npmPrefix = ""
        try {
            $npmPrefix = & npm.cmd prefix -g 2>$null
        } catch {}
        # Sanity-check: must look like an absolute Windows path (e.g. C:\...)
        if (-not [string]::IsNullOrWhiteSpace($npmPrefix) -and $npmPrefix -match '^[A-Za-z]:\\') {
            $candidate = Join-Path $npmPrefix "claude.cmd"
            if (Test-Path -LiteralPath $candidate) {
                $claudeFound = $true
                $claudeExe = $candidate
            }
            if (-not $claudeFound) {
                $candidate2 = Join-Path $npmPrefix "claude"
                if (Test-Path -LiteralPath $candidate2) {
                    $claudeFound = $true
                    $claudeExe = $candidate2
                }
            }
        }
    }

    if ($claudeFound -and -not [string]::IsNullOrWhiteSpace($claudeExe)) {
        # Write digest to a temp file so we can feed it as stdin content
        $tmpDigest = [System.IO.Path]::GetTempFileName()
        try {
            $utf8NoBom2 = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($tmpDigest, $content, $utf8NoBom2)

            $prompt = "Rewrite this dev activity digest as a brief, natural spoken-word morning briefing, 150-250 words, second person, no markdown, no headers, just what I'd want read to me with coffee. Digest follows:"

            # Build the full prompt string with digest appended
            $fullPrompt = $prompt + "`n`n" + $content

            # Write prompt+digest to another temp file and pipe it in via Get-Content
            $tmpPrompt = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllText($tmpPrompt, $fullPrompt, $utf8NoBom2)

            # Use cmd /c to pipe the temp file into claude -p via stdin
            # We pass the prompt text directly as the -p argument and pipe nothing,
            # to keep things simple and PS5.1-safe.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            # Escape paths for cmd /c: wrap in double quotes inside the outer quotes
            $safeExe    = $claudeExe.Replace('"', '')
            $safePrompt = $fullPrompt.Replace('"', "'").Replace("`n", " ").Replace("`r", "")
            # Use temp file approach: write prompt to temp, pass as -p arg via file read
            # Actually use stdin pipe: cmd /c type tmpPrompt | claude -p <prompt>
            # Simplest safe approach: pass -p with the prompt, pipe the digest on stdin
            $psi.Arguments = "/c type `"$tmpPrompt`" | `"$safeExe`" -p `"$prompt`""
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $claudeOutput = $proc.StandardOutput.ReadToEnd()
            $proc.WaitForExit(60000) | Out-Null

            if ($proc.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($claudeOutput)) {
                $narration = $claudeOutput.Trim()
            } else {
                Write-Error "claude CLI returned exit $($proc.ExitCode); falling back to markdown-strip narration"
                $claudeFound = $false
            }
        } catch {
            Write-Error "claude CLI invocation failed: $($_.Exception.Message); falling back"
            $claudeFound = $false
        } finally {
            if (Test-Path -LiteralPath $tmpDigest) { Remove-Item -LiteralPath $tmpDigest -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $tmpPrompt) { Remove-Item -LiteralPath $tmpPrompt -Force -ErrorAction SilentlyContinue }
        }
    }

    # Fallback: strip markdown from the digest into plain prose
    if (-not $claudeFound -or [string]::IsNullOrWhiteSpace($narration)) {
        $plain = $content
        # Remove markdown headings
        $plain = $plain -replace '(?m)^#{1,6}\s+', ''
        # Remove bold/italic markers
        $plain = $plain -replace '\*{1,2}([^*]+)\*{1,2}', '$1'
        $plain = $plain -replace '_{1,2}([^_]+)_{1,2}', '$1'
        # Remove inline code
        $plain = $plain -replace '`([^`]+)`', '$1'
        # Remove horizontal rules
        $plain = $plain -replace '(?m)^---+\s*$', ''
        # Remove list bullets
        $plain = $plain -replace '(?m)^\s*[-*]\s+', ''
        # Collapse multiple blank lines
        $plain = $plain -replace '(\r?\n){3,}', "`n`n"
        $narration = $plain.Trim()
    }

    # Write narration file
    try {
        $utf8NoBomN = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($narrationFile, $narration, $utf8NoBomN)
        Write-Host $narrationFile
    } catch {
        Write-Error "ERROR: could not write narration to $narrationFile - $($_.Exception.Message)"
    }

    # ---- TTS via Windows SAPI (only when -Speak or -Play) ----
    if ($Speak -and -not [string]::IsNullOrWhiteSpace($narration)) {
        try {
            Add-Type -AssemblyName System.Speech -ErrorAction Stop

            $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
            try {
                # Always write WAV first
                $synth.SetOutputToWaveFile($wavFile)
                $synth.Speak($narration)
                $synth.SetOutputToNull()
                Write-Host $wavFile
            } finally {
                try { $synth.Dispose() } catch {}
            }

            # Immediate playback only if -Play was given
            if ($Play -and (Test-Path -LiteralPath $wavFile)) {
                $synthPlay = New-Object System.Speech.Synthesis.SpeechSynthesizer
                try {
                    $synthPlay.SetOutputToDefaultAudioDevice()
                    $synthPlay.Speak($narration)
                } finally {
                    try { $synthPlay.Dispose() } catch {}
                }
            }
        } catch {
            Write-Error "SAPI TTS failed: $($_.Exception.Message)"
        }
    }
}

exit 0
