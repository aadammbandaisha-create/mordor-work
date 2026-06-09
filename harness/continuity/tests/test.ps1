# tests\test.ps1 -- self-test for the continuity mod
# Validates all .ps1 files and exercises session-context.ps1 logic.
# Run from the harness\continuity directory, or from anywhere -- it uses absolute paths.
# PowerShell 5.1 compatible. No installation required.

$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModRoot = Split-Path -Parent $Here
$ScriptUnderTest = Join-Path $ModRoot "scripts\session-context.ps1"
$InstallScript   = Join-Path $ModRoot "install.ps1"
$UninstallScript = Join-Path $ModRoot "uninstall.ps1"

$pass = 0
$fail = 0

function Assert-True {
    param([string]$Label, [bool]$Condition, [string]$Detail = "")
    if ($Condition) {
        Write-Host "  PASS  $Label"
        $script:pass++
    } else {
        if ($Detail) {
            Write-Host "  FAIL  $Label -- $Detail"
        } else {
            Write-Host "  FAIL  $Label"
        }
        $script:fail++
    }
}

# Helper: invoke session-context.ps1 with given stdin JSON; return stdout as string
function Invoke-SessionContext {
    param([string]$StdinJson)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptUnderTest`" mutwo:continuity"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Write($StdinJson)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    return [pscustomobject]@{ Stdout = $stdout; ExitCode = $exitCode }
}

Write-Host ""
Write-Host "=== continuity mod self-test ==="
Write-Host ""

# ------------------------------------------------------------------
# 1. PS 5.1 parser validation
# ------------------------------------------------------------------
Write-Host "-- Parser validation --"

foreach ($ps1 in @($ScriptUnderTest, $InstallScript, $UninstallScript)) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($ps1, [ref]$null, [ref]$errors)
    $label = [System.IO.Path]::GetFileName($ps1)
    Assert-True "Parse $label (0 errors)" ($errors.Count -eq 0) "got $($errors.Count) error(s)"
}

# ------------------------------------------------------------------
# 2. Temp git repo with commit + handoff fixture
# ------------------------------------------------------------------
Write-Host ""
Write-Host "-- Scenario: git repo with handoff --"

$tmp = Join-Path $env:TEMP ("continuity_test_" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    # Init git repo
    Push-Location $tmp
    $null = & git init 2>&1
    $null = & git config user.email "test@example.com" 2>&1
    $null = & git config user.name "Test" 2>&1
    # Create a file and commit
    "hello" | Set-Content -Path (Join-Path $tmp "hello.txt") -Encoding UTF8
    $null = & git add . 2>&1
    $null = & git commit -m "initial commit" 2>&1
    Pop-Location

    # Create .claude\handoff.md fixture (recent -- within 7 days)
    $claudeDir = Join-Path $tmp ".claude"
    New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
    $handoffPath = Join-Path $claudeDir "handoff.md"
    "## Context`nThis is a test handoff document." | Set-Content -LiteralPath $handoffPath -Encoding UTF8

    # Pipe JSON into session-context.ps1
    $json = "{`"session_id`":`"test-123`",`"cwd`":`"$($tmp.Replace('\','\\'))`",`"hook_event_name`":`"SessionStart`",`"source`":`"normal`"}"
    $result = Invoke-SessionContext -StdinJson $json

    Assert-True "Exit code 0 (git+handoff)" ($result.ExitCode -eq 0)
    Assert-True "Output contains 'Branch:'" ($result.Stdout -match "Branch:")
    Assert-True "Output contains 'Status:'" ($result.Stdout -match "Status:")
    Assert-True "Output contains 'Pending handoff'" ($result.Stdout -match "Pending handoff")
} finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------
# 3. Non-git temp dir (expect empty stdout, exit 0)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "-- Scenario: non-git directory --"

$tmp2 = Join-Path $env:TEMP ("continuity_test_" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmp2 | Out-Null

try {
    $json2 = "{`"session_id`":`"test-456`",`"cwd`":`"$($tmp2.Replace('\','\\'))`",`"hook_event_name`":`"SessionStart`",`"source`":`"normal`"}"
    $result2 = Invoke-SessionContext -StdinJson $json2

    Assert-True "Exit code 0 (non-git)" ($result2.ExitCode -eq 0)
    Assert-True "Stdout empty (non-git)" ([string]::IsNullOrWhiteSpace($result2.Stdout))
} finally {
    if (Test-Path -LiteralPath $tmp2) {
        Remove-Item -LiteralPath $tmp2 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------
# 4. source=compact against a git repo (expect empty stdout)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "-- Scenario: source=compact --"

$tmp3 = Join-Path $env:TEMP ("continuity_test_" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmp3 | Out-Null

try {
    Push-Location $tmp3
    $null = & git init 2>&1
    $null = & git config user.email "test@example.com" 2>&1
    $null = & git config user.name "Test" 2>&1
    "hello" | Set-Content -Path (Join-Path $tmp3 "hello.txt") -Encoding UTF8
    $null = & git add . 2>&1
    $null = & git commit -m "initial commit" 2>&1
    Pop-Location

    $json3 = "{`"session_id`":`"test-789`",`"cwd`":`"$($tmp3.Replace('\','\\'))`",`"hook_event_name`":`"SessionStart`",`"source`":`"compact`"}"
    $result3 = Invoke-SessionContext -StdinJson $json3

    Assert-True "Exit code 0 (compact)" ($result3.ExitCode -eq 0)
    Assert-True "Stdout empty (compact)" ([string]::IsNullOrWhiteSpace($result3.Stdout))
} finally {
    if (Test-Path -LiteralPath $tmp3) {
        Remove-Item -LiteralPath $tmp3 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ""
Write-Host "=== Results: $pass passed, $fail failed ==="
Write-Host ""

if ($fail -gt 0) {
    exit 1
}
exit 0
