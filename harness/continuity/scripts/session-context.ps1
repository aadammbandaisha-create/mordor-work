# session-context.ps1 -- SessionStart hook; stdout is the injected context.
# Accepts and ignores a trailing sentinel argument (mordor:continuity).
# $ErrorActionPreference SilentlyContinue: any failure is silent; always exit 0.

$ErrorActionPreference = "SilentlyContinue"

function Main {
    # Read stdin JSON
    $raw = $null
    try {
        $raw = [Console]::In.ReadToEnd()
    } catch {
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        exit 0
    }

    $input = $null
    try {
        $input = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        exit 0
    }

    # Skip injection when source is "compact" -- conversation already has context
    $source = [string]$input.source
    if ($source -eq "compact") {
        exit 0
    }

    $cwd = [string]$input.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) {
        exit 0
    }

    $gitOutput = @()
    $projectMapOutput = @()
    $markersOutput = @()
    $testStatusOutput = @()
    $handoffOutput = @()

    # --- Git context ---
    # Walk up from cwd looking for .git
    $repoRoot = $null
    $dir = $cwd
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-Path -LiteralPath (Join-Path $dir ".git")) {
            $repoRoot = $dir
            break
        }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) {
            break
        }
        $dir = $parent
    }

    if (-not [string]::IsNullOrEmpty($repoRoot)) {
        # Current branch
        $branch = $null
        try {
            $branch = & git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null
        } catch { }

        # git status --short, capped at 25 lines
        $statusLines = $null
        try {
            $statusLines = & git -C $repoRoot status --short 2>$null
        } catch { }

        # Last 3 commits
        $logLines = $null
        try {
            $logLines = & git -C $repoRoot log --oneline -3 2>$null
        } catch { }

        if (-not [string]::IsNullOrEmpty($branch)) {
            $gitOutput += "## Session context"
            $gitOutput += ""
            $gitOutput += "Branch: $branch"

            if ($null -ne $statusLines -and @($statusLines).Count -gt 0) {
                $lines = @($statusLines)
                $total = $lines.Count
                $shown = $lines | Select-Object -First 25
                $gitOutput += ""
                $gitOutput += "Status:"
                foreach ($line in $shown) {
                    $gitOutput += "  $line"
                }
                if ($total -gt 25) {
                    $extra = $total - 25
                    $gitOutput += "  (+$extra more)"
                }
            } else {
                $gitOutput += "Status: clean"
            }

            if ($null -ne $logLines -and @($logLines).Count -gt 0) {
                $gitOutput += ""
                $gitOutput += "Recent commits:"
                foreach ($line in @($logLines)) {
                    $gitOutput += "  $line"
                }
            }
        }

        # --- TODO/FIXME open markers (fast count + top 3 files) ---
        # Run git grep via a background job to allow timeout (~3 s)
        $markerCount = 0
        $topFiles = @()
        try {
            $job = Start-Job -ScriptBlock {
                param($root)
                & git -C $root grep -I -n -E "TODO|FIXME" 2>$null
            } -ArgumentList $repoRoot

            $finished = Wait-Job -Job $job -Timeout 3
            if ($null -ne $finished) {
                $grepLines = Receive-Job -Job $job
                Remove-Job -Job $job -Force
                if ($null -ne $grepLines) {
                    $grepArr = @($grepLines)
                    $markerCount = $grepArr.Count
                    if ($markerCount -gt 0) {
                        # Extract unique file paths (field before first colon)
                        $files = $grepArr | ForEach-Object {
                            $parts = $_ -split ":", 2
                            if ($parts.Count -ge 1) { $parts[0] }
                        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
                        $topFiles = @($files) | Select-Object -First 3
                    }
                }
            } else {
                Stop-Job -Job $job
                Remove-Job -Job $job -Force
            }
        } catch { }

        if ($markerCount -gt 0) {
            $markersOutput += ""
            $markersOutput += "## Open markers: $markerCount TODO/FIXME on this branch"
            foreach ($f in $topFiles) {
                $markersOutput += "  $f"
            }
        }
    }

    # --- Project map ---
    $projectMapPath = Join-Path $cwd ".claude\project-map.md"
    if (Test-Path -LiteralPath $projectMapPath) {
        $mapContent = $null
        try {
            $mapContent = Get-Content -LiteralPath $projectMapPath -Encoding UTF8 -ErrorAction Stop
        } catch { }

        if ($null -ne $mapContent) {
            $lines = @($mapContent)
            $shown = $lines | Select-Object -First 120
            $projectMapOutput += ""
            $projectMapOutput += "## Project map"
            $projectMapOutput += ""
            foreach ($line in $shown) {
                $projectMapOutput += $line
            }
            if ($lines.Count -gt 120) {
                $extra = $lines.Count - 120
                $projectMapOutput += "(+$extra lines truncated)"
            }
        }
    }

    # --- Last test status ---
    $testStatusPath = Join-Path $cwd ".claude\last-test-status.txt"
    if (Test-Path -LiteralPath $testStatusPath) {
        $fileAge = $null
        try {
            $fileAge = (Get-Item -LiteralPath $testStatusPath).LastWriteTime
        } catch { }

        $tooOld = $true
        if ($null -ne $fileAge) {
            $diff = (Get-Date) - $fileAge
            if ($diff.TotalDays -lt 7) {
                $tooOld = $false
            }
        }

        if (-not $tooOld) {
            $firstLine = $null
            try {
                $firstLine = Get-Content -LiteralPath $testStatusPath -Encoding UTF8 -TotalCount 1 -ErrorAction Stop
            } catch { }

            if (-not [string]::IsNullOrWhiteSpace($firstLine)) {
                $testStatusOutput += ""
                $testStatusOutput += "## Last recorded test status"
                $testStatusOutput += $firstLine
            }
        }
    }

    # --- Handoff file ---
    $handoffPath = Join-Path $cwd ".claude\handoff.md"
    if (Test-Path -LiteralPath $handoffPath) {
        $age = $null
        try {
            $age = (Get-Item -LiteralPath $handoffPath).LastWriteTime
        } catch { }

        $tooOld = $true
        if ($null -ne $age) {
            $diff = (Get-Date) - $age
            if ($diff.TotalDays -lt 7) {
                $tooOld = $false
            }
        }

        if (-not $tooOld) {
            $isoDate = $age.ToString("yyyy-MM-ddTHH:mm:ss")
            $handoffContent = $null
            try {
                $handoffContent = Get-Content -LiteralPath $handoffPath -Encoding UTF8 -ErrorAction Stop
            } catch { }

            if ($null -ne $handoffContent) {
                $lines = @($handoffContent)
                $shown = $lines | Select-Object -First 150
                $handoffOutput += ""
                $handoffOutput += "## Pending handoff (from $isoDate)"
                $handoffOutput += ""
                foreach ($line in $shown) {
                    $handoffOutput += $line
                }
                $handoffOutput += ""
                $handoffOutput += "(Source: .claude/handoff.md -- delete or overwrite it once absorbed.)"
            }
        }
    }

    # Emit in order: git context, project map, open markers, test status, pending handoff
    $allOutput = @()
    foreach ($line in $gitOutput)        { $allOutput += $line }
    foreach ($line in $projectMapOutput) { $allOutput += $line }
    foreach ($line in $markersOutput)    { $allOutput += $line }
    foreach ($line in $testStatusOutput) { $allOutput += $line }
    foreach ($line in $handoffOutput)    { $allOutput += $line }

    if ($allOutput.Count -gt 0) {
        foreach ($line in $allOutput) {
            Write-Output $line
        }
    }
}

try {
    Main
} catch {
    # Silent on any unhandled error
}

exit 0
