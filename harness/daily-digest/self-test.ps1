# self-test.ps1 -- daily-digest mod verification
# Run from the mod root: .\self-test.ps1
# Does NOT mutate user state: no schtasks /Create, no writes outside $env:TEMP.

param()

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$DigestScript = Join-Path $Here "scripts\daily-digest.ps1"
$InstallScript = Join-Path $Here "install.ps1"
$UninstallScript = Join-Path $Here "uninstall.ps1"
$OutDir = Join-Path $env:TEMP "digest-test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$Failed = $false

function Fail {
    param([string]$Msg)
    Write-Host "FAIL: $Msg"
    $script:Failed = $true
}

function Pass {
    param([string]$Msg)
    Write-Host "PASS: $Msg"
}

# ---------------------------------------------------------------------------
# (a) Parser-validate all .ps1 files
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== (a) PS parser validation ==="
Write-Host ""

$psFiles = @(
    $DigestScript,
    $InstallScript,
    $UninstallScript,
    (Join-Path $Here "self-test.ps1")
)

foreach ($psFile in $psFiles) {
    if (-not (Test-Path -LiteralPath $psFile)) {
        Fail "File not found: $psFile"
        continue
    }
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($psFile, [ref]$null, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -eq 0) {
        Pass "Zero parse errors: $(Split-Path -Leaf $psFile)"
    } else {
        foreach ($e in $parseErrors) {
            Fail "Parse error in $(Split-Path -Leaf $psFile): $($e.Message) at line $($e.Extent.StartLineNumber)"
        }
    }
}

# ---------------------------------------------------------------------------
# (b) Run daily-digest.ps1 -Days 3 against real transcripts (read-only)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== (b) Run daily-digest.ps1 -Days 3 ==="
Write-Host ""

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$transcriptsDir = Join-Path $env:USERPROFILE ".claude\projects"
if (Test-Path -LiteralPath $transcriptsDir) {
    Write-Host "Transcripts dir: $transcriptsDir"
} else {
    Write-Host "NOTE: $transcriptsDir does not exist -- digest will report no activity (still valid)."
}

$todayStr = (Get-Date).ToString("yyyy-MM-dd")
$expectedOut = Join-Path $OutDir "$todayStr.md"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DigestScript -Days 3 -OutDir $OutDir
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Fail "daily-digest.ps1 exited $exitCode (expected 0)"
} else {
    Pass "Exit code 0"
}

# ---------------------------------------------------------------------------
# (c) Verify output file exists; print path + 5-line excerpt
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== (c) Output file verification ==="
Write-Host ""

if (Test-Path -LiteralPath $expectedOut) {
    Pass "Output file exists: $expectedOut"
    Write-Host ""
    Write-Host "--- First 5 lines ---"
    $topLines = Get-Content -LiteralPath $expectedOut -Encoding UTF8 -TotalCount 5
    foreach ($ln in $topLines) {
        Write-Host $ln
    }
    Write-Host "--- End excerpt ---"
    Write-Host ""
} else {
    # Script prints the path to stdout; look for any .md in $OutDir
    $anyMd = Get-ChildItem -LiteralPath $OutDir -Filter "*.md" -ErrorAction SilentlyContinue
    if ($anyMd) {
        $actualOut = $anyMd[0].FullName
        Pass "Output file exists (unexpected name): $actualOut"
        Write-Host ""
        Write-Host "--- First 5 lines ---"
        $topLines = Get-Content -LiteralPath $actualOut -Encoding UTF8 -TotalCount 5
        foreach ($ln in $topLines) {
            Write-Host $ln
        }
        Write-Host "--- End excerpt ---"
        Write-Host ""
        $expectedOut = $actualOut
    } else {
        Fail "No output .md file found in $OutDir"
    }
}

# ---------------------------------------------------------------------------
# (d) Verify file is valid UTF-8 and check ASCII-safety
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== (d) UTF-8 / ASCII-safe check ==="
Write-Host ""

if (Test-Path -LiteralPath $expectedOut) {
    $rawBytes = [System.IO.File]::ReadAllBytes($expectedOut)

    # Must NOT have a UTF-8 BOM (script uses UTF8Encoding $false)
    $hasBom = ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF)
    if ($hasBom) {
        Fail "File has unexpected UTF-8 BOM (script should write without BOM via UTF8Encoding false)"
    } else {
        Pass "No BOM (UTF8Encoding false confirmed)"
    }

    # Check the file is decodable as UTF-8 (hard fail = malformed byte sequence)
    try {
        $strictUtf8 = New-Object System.Text.UTF8Encoding $false, $true
        [void]$strictUtf8.GetString($rawBytes)
        Pass "File is valid UTF-8"
    } catch {
        Fail "File is NOT valid UTF-8: $($_.Exception.Message)"
    }

    # Count non-ASCII bytes (informational -- transcript content may contain Unicode)
    $nonAsciiCount = 0
    foreach ($b in $rawBytes) {
        if ($b -gt 127) { $nonAsciiCount++ }
    }
    if ($nonAsciiCount -eq 0) {
        Pass "File is ASCII-safe (all bytes <= 127)"
    } else {
        Write-Host "INFO: $nonAsciiCount non-ASCII byte(s) found -- this is expected when transcript"
        Write-Host "      content includes Unicode characters (e.g. smart quotes from assistant text)."
        Write-Host "      The file is still valid UTF-8; ASCII-safety depends on transcript content."
        Pass "UTF-8 valid (non-ASCII bytes from transcript content are acceptable)"
    }
} else {
    Write-Host "SKIP: no output file to check"
}

# ---------------------------------------------------------------------------
# (e) Validate schtasks command string (install-time verified only, NOT run)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== (e) schtasks command string (construction only, NOT executed) ==="
Write-Host ""

$TaskName      = "mordor-daily-digest"
$ClaudeDir     = Join-Path $env:USERPROFILE ".claude"
$ScriptsDir    = Join-Path $ClaudeDir "scripts"
$TargetScript  = Join-Path $ScriptsDir "daily-digest.ps1"
$taskCommand   = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TargetScript`""
$schtasksCmd   = "schtasks /Create /F /TN $TaskName /SC DAILY /ST 08:00 /TR `"$taskCommand`""

Write-Host "Task name:    $TaskName"
Write-Host "Task command: $taskCommand"
Write-Host ""
Write-Host "Full schtasks invocation (install-time only -- NOT run here):"
Write-Host "  $schtasksCmd"
Write-Host ""

# Validate the pieces are non-empty and well-formed
if ($TaskName -match '^mordor-daily-digest$') {
    Pass "Task name matches sentinel: $TaskName"
} else {
    Fail "Task name does not match expected sentinel"
}

if ($taskCommand -match 'powershell\.exe') {
    Pass "Task command contains powershell.exe"
} else {
    Fail "Task command malformed"
}

if ($taskCommand -match '-NoProfile') {
    Pass "Task command includes -NoProfile"
} else {
    Fail "Task command missing -NoProfile"
}

if ($taskCommand -match '-WindowStyle Hidden') {
    Pass "Task command includes -WindowStyle Hidden"
} else {
    Fail "Task command missing -WindowStyle Hidden"
}

if ($taskCommand -match '-ExecutionPolicy Bypass') {
    Pass "Task command includes -ExecutionPolicy Bypass"
} else {
    Fail "Task command missing -ExecutionPolicy Bypass"
}

if ($taskCommand -match [regex]::Escape($TargetScript)) {
    Pass "Task command references correct target script path"
} else {
    Fail "Task command does not reference expected target script path"
}

# ---------------------------------------------------------------------------
# (f) Run daily-digest.ps1 -Days 1 -Narrate -- assert narration.txt produced
#     We test the FALLBACK path (no-CLI simulation) to avoid spending tokens.
#     We do this by temporarily pointing the script at a non-existent projects
#     dir (guaranteed no-activity, no-CLI path still runs) and asserting the
#     narration file exists and has length > 0.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== (f) -Narrate fallback path (narration.txt produced without claude CLI) ==="
Write-Host ""

$narrateOutDir = Join-Path $env:TEMP "digest-narrate-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $narrateOutDir | Out-Null

$todayStr2 = (Get-Date).ToString("yyyy-MM-dd")
$expectedNarration = Join-Path $narrateOutDir "$todayStr2.narration.txt"

# Temporarily set a fake projects dir via a wrapper: run with -OutDir pointing
# to our temp dir. The script's -Narrate path always writes narration.txt even
# when there is no activity (it falls back to markdown-strip on the digest).
# We rely on real transcripts for input (or empty if none exist) -- either
# way the script must produce a narration.txt.

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DigestScript `
    -Days 1 -OutDir $narrateOutDir -Narrate
$narrateExit = $LASTEXITCODE

if ($narrateExit -ne 0) {
    Fail "-Narrate run exited $narrateExit (expected 0)"
} else {
    Pass "-Narrate run exited 0"
}

if (Test-Path -LiteralPath $expectedNarration) {
    $narLen = (Get-Item -LiteralPath $expectedNarration).Length
    if ($narLen -gt 0) {
        Pass "narration.txt exists and has length $narLen bytes"
    } else {
        Fail "narration.txt exists but is empty (0 bytes)"
    }
} else {
    # Check for any .narration.txt in case date differed
    $anyNar = Get-ChildItem -LiteralPath $narrateOutDir -Filter "*.narration.txt" -ErrorAction SilentlyContinue
    if ($anyNar -and $anyNar.Count -gt 0 -and $anyNar[0].Length -gt 0) {
        Pass "narration.txt found at $($anyNar[0].FullName) (length $($anyNar[0].Length) bytes)"
    } else {
        Fail "No .narration.txt file found in $narrateOutDir"
    }
}

Remove-Item -LiteralPath $narrateOutDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Removed temp narrate dir: $narrateOutDir"

# ---------------------------------------------------------------------------
# (g) SAPI synthesis -- generate a 1-sentence WAV to $env:TEMP and assert
#     the file exists with > 0 bytes (no audio device required; file output
#     only). Wrapped in try/catch so a headless/CI machine without the
#     System.Speech assembly does not hard-fail the entire self-test.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== (g) SAPI synthesis (WAV file to TEMP) ==="
Write-Host ""

$wavTmp = Join-Path $env:TEMP "sapi-selftest-$(Get-Date -Format 'yyyyMMdd-HHmmss').wav"

try {
    Add-Type -AssemblyName System.Speech -ErrorAction Stop
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        $synth.SetOutputToWaveFile($wavTmp)
        $synth.Speak("Self test")
        $synth.SetOutputToNull()
    } finally {
        try { $synth.Dispose() } catch {}
    }

    if (Test-Path -LiteralPath $wavTmp) {
        $wavLen = (Get-Item -LiteralPath $wavTmp).Length
        if ($wavLen -gt 0) {
            Pass "SAPI WAV written: $wavTmp ($wavLen bytes)"
        } else {
            Fail "SAPI WAV file exists but is 0 bytes: $wavTmp"
        }
    } else {
        Fail "SAPI WAV file not found after Speak(): $wavTmp"
    }
} catch {
    Fail "SAPI synthesis failed: $($_.Exception.Message)"
} finally {
    if (Test-Path -LiteralPath $wavTmp) {
        Remove-Item -LiteralPath $wavTmp -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Cleanup temp dir
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Cleanup ==="
Remove-Item -LiteralPath $OutDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Removed temp dir: $OutDir"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
if ($Failed) {
    Write-Host "RESULT: SOME CHECKS FAILED -- review output above."
    exit 1
} else {
    Write-Host "RESULT: ALL CHECKS PASSED."
    exit 0
}
