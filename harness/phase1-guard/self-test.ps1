# self-test.ps1
# Tests guard-check.ps1 logic without installing anything.
# Usage: powershell -File self-test.ps1
# All tests operate in $env:TEMP; nothing is written to ~/.claude

$ErrorActionPreference = "Stop"

$guardScript = Join-Path $PSScriptRoot "scripts\guard-check.ps1"

$tempDir = Join-Path $env:TEMP "phase1-guard-test"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$tempLog = Join-Path $tempDir "guard-log-test.jsonl"
if (Test-Path -LiteralPath $tempLog) { Remove-Item -LiteralPath $tempLog -Force }

$env:MORDOR_GUARD_LOG = $tempLog

function Invoke-Guard {
    param([string]$StdinJson)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$guardScript`" mordor:phase1-guard"
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($StdinJson)
    $p.StandardInput.Close()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

$passed = 0
$failed = 0

function Assert {
    param([bool]$Condition, [string]$Label)
    if ($Condition) {
        Write-Host "  PASS: $Label"
        $script:passed++
    } else {
        Write-Host "  FAIL: $Label"
        $script:failed++
    }
}

# ---- TEST 1: git push --force -> exit 0, log entry written ---------------
Write-Host "TEST 1: git push --force (destructive)"
$r1 = Invoke-Guard -StdinJson '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
Assert ($r1.ExitCode -eq 0)         "exit 0 in log-only mode"
Assert ($r1.Stdout   -eq "")        "no stdout"
$logContent = Get-Content -LiteralPath $tempLog -Raw -Encoding UTF8
$logEntry = $logContent.Trim() | ConvertFrom-Json
Assert ($logEntry.wouldBlock -eq $true)     "wouldBlock=true"
Assert ($logEntry.mode -eq "log-only")      "mode=log-only"
Assert (-not [string]::IsNullOrEmpty($logEntry.matchedPattern)) "matchedPattern non-empty"
Assert ($logEntry.command -like "*git push*") "command captured"
Write-Host "  matched pattern: $($logEntry.matchedPattern)"

# ---- TEST 2: harmless 'ls -la' -> exit 0, no log growth ------------------
Write-Host "TEST 2: harmless ls -la"
$linesBefore = (Get-Content -LiteralPath $tempLog -Encoding UTF8).Count
$r2 = Invoke-Guard -StdinJson '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
Assert ($r2.ExitCode -eq 0)    "exit 0"
Assert ($r2.Stdout   -eq "")   "no stdout"
$linesAfter = (Get-Content -LiteralPath $tempLog -Encoding UTF8).Count
Assert ($linesAfter -eq $linesBefore) "log not grown"

# ---- TEST 3: rm -rf -> exit 0, log written --------------------------------
Write-Host "TEST 3: rm -rf /tmp/foo"
$r3 = Invoke-Guard -StdinJson '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/foo"}}'
Assert ($r3.ExitCode -eq 0) "exit 0"
$logLines = @(Get-Content -LiteralPath $tempLog -Encoding UTF8)
Assert ($logLines.Count -eq 2) "log now has 2 entries"

# ---- TEST 4: git reset --hard -------------------------------------------
Write-Host "TEST 4: git reset --hard"
$r4 = Invoke-Guard -StdinJson '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~2"}}'
Assert ($r4.ExitCode -eq 0) "exit 0"
$logLines = @(Get-Content -LiteralPath $tempLog -Encoding UTF8)
Assert ($logLines.Count -eq 3) "log now has 3 entries"

# ---- TEST 5: shutdown command --------------------------------------------
Write-Host "TEST 5: shutdown /r /t 0"
$r5 = Invoke-Guard -StdinJson '{"tool_name":"Bash","tool_input":{"command":"shutdown /r /t 0"}}'
Assert ($r5.ExitCode -eq 0) "exit 0"

# ---- TEST 6: malformed stdin -> exit 0 -----------------------------------
Write-Host "TEST 6: malformed stdin JSON"
$r6 = Invoke-Guard -StdinJson '{not valid json'
Assert ($r6.ExitCode -eq 0) "exit 0 on malformed JSON"

# ---- TEST 7: empty stdin -> exit 0 --------------------------------------
Write-Host "TEST 7: empty stdin"
$r7 = Invoke-Guard -StdinJson ""
Assert ($r7.ExitCode -eq 0) "exit 0 on empty stdin"

# ---- TEST 8: enforce mode -> exit 2, stderr set -------------------------
Write-Host "TEST 8: enforce mode (git push --force)"
$savedMode = $env:MORDOR_GUARD_MODE
$env:MORDOR_GUARD_MODE = "enforce"
$r8 = Invoke-Guard -StdinJson '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
$env:MORDOR_GUARD_MODE = $savedMode
Assert ($r8.ExitCode -eq 2)            "exit 2 in enforce mode"
Assert ($r8.Stderr   -like "*phase1-guard*") "stderr contains 'phase1-guard'"
Write-Host "  stderr: $($r8.Stderr.Trim())"

# ---- TEST 9: settings coexistence fixture --------------------------------
# Simulate a settings object that already has:
#   - PreToolUse: AskUserQuestion entry (windows-state-indicator owns it)
#   - PostToolUse: Edit|Write entry (format-on-edit owns it)
# Run the Set-HookEvent / Remove-OwnedEntries logic from install.ps1 as a
# pure in-memory exercise and assert the AskUserQuestion entry survives.
Write-Host "TEST 9: settings coexistence (AskUserQuestion entry survives)"

$sentinel = "mordor:phase1-guard"

$askEntry = [pscustomobject]@{
    matcher = "AskUserQuestion"
    hooks   = @([pscustomobject]@{
        type    = "command"
        command = "powershell.exe -File `"C:\scripts\claude-state.ps1`" idle mordor:windows-state-indicator"
    })
}

$postEntry = [pscustomobject]@{
    matcher = "Edit|Write"
    hooks   = @([pscustomobject]@{
        type    = "command"
        command = "powershell.exe -File `"C:\scripts\format-on-edit.ps1`" mordor:format-on-edit"
    })
}

$fakeSettings = [pscustomobject]@{
    hooks = [pscustomobject]@{
        PreToolUse  = @($askEntry)
        PostToolUse = @($postEntry)
    }
}

function _Remove-OwnedEntries {
    param($Entries)
    $kept = @()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $owned = $false
        foreach ($hook in @($entry.hooks)) {
            $cmd = [string]$hook.command
            if ($cmd.Contains($sentinel)) { $owned = $true; break }
        }
        if (-not $owned) { $kept += $entry }
    }
    return $kept
}

function _New-HookEntry {
    param([string]$Matcher, [string]$Command)
    return [pscustomobject]@{
        matcher = $Matcher
        hooks   = @([pscustomobject]@{ type = "command"; command = $Command })
    }
}

# Simulate Set-HookEvent for PreToolUse
$existingPre = _Remove-OwnedEntries $fakeSettings.hooks.PreToolUse
$newCmd = "powershell.exe -File guard-check.ps1 $sentinel"
$newPre = @($existingPre) + (_New-HookEntry -Matcher "Bash" -Command $newCmd)
$fakeSettings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue $newPre -Force

# Assert AskUserQuestion entry survives
$preFinal = @($fakeSettings.hooks.PreToolUse)
$askSurvived = $false
foreach ($e in $preFinal) {
    if ([string]$e.matcher -eq "AskUserQuestion") { $askSurvived = $true; break }
}
Assert $askSurvived "AskUserQuestion entry survives after Set-HookEvent"

# Assert our new Bash entry was added
$bashAdded = $false
foreach ($e in $preFinal) {
    if ([string]$e.matcher -eq "Bash") { $bashAdded = $true; break }
}
Assert $bashAdded "Bash entry added by Set-HookEvent"

# Assert PostToolUse untouched
$postFinal = @($fakeSettings.hooks.PostToolUse)
Assert ($postFinal.Count -eq 1) "PostToolUse entry count unchanged (1)"
Assert ($postFinal[0].matcher -eq "Edit|Write") "PostToolUse Edit|Write entry intact"
Assert ($preFinal.Count -eq 2) "PreToolUse now has 2 entries (AskUserQuestion + Bash)"

Write-Host ""
Write-Host "Results: $passed passed, $failed failed"
if ($failed -gt 0) {
    exit 1
}
exit 0
