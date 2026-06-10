# test.ps1 -- self-test for check-on-edit mod (no install required)
# Run from any directory; nothing under ~/.claude is touched.
# Exit 0 = all tests passed; Exit 1 = at least one failure.

$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script = Join-Path $Here "scripts\check-on-edit.ps1"

$pass = 0
$fail = 0

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if ($Condition) {
        Write-Host "  PASS: $Label"
        $script:pass++
    } else {
        Write-Host "  FAIL: $Label"
        $script:fail++
    }
}

# ============================================================
# TEST 1: PS parser validation of check-on-edit.ps1
# ============================================================
Write-Host ""
Write-Host "=== TEST 1: PS parser validation ==="

$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$parseErrors) | Out-Null
Assert-True ($parseErrors.Count -eq 0) "check-on-edit.ps1 parses with zero errors (got $($parseErrors.Count))"

$installPs1 = Join-Path $Here "install.ps1"
$iErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($installPs1, [ref]$null, [ref]$iErrors) | Out-Null
Assert-True ($iErrors.Count -eq 0) "install.ps1 parses with zero errors (got $($iErrors.Count))"

# ============================================================
# TEST 2: .py file in a temp dir WITHOUT ruff in PATH
#         Expect: exit 0, no output (no-op -- ruff absent)
# ============================================================
Write-Host ""
Write-Host "=== TEST 2: .py file, ruff absent in PATH -- expect exit 0 no-op ==="

$tmpDir = Join-Path $env:TEMP "coe-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

# Create a pyproject.toml so the ruff-config guard passes if ruff were present.
"[tool.ruff]`nline-length = 88" | Set-Content -LiteralPath (Join-Path $tmpDir "pyproject.toml") -Encoding UTF8

# A Python file with an obvious lint issue (unused import).
$pyFile = Join-Path $tmpDir "bad.py"
"import os`nx=1" | Set-Content -LiteralPath $pyFile -Encoding UTF8

$stdinJson = '{"tool_name":"Edit","tool_input":{"file_path":"' + $pyFile.Replace('\', '\\') + '"}}'

# Run the hook with an empty PATH so ruff cannot be found.
$proc = New-Object System.Diagnostics.ProcessStartInfo
$proc.FileName = "powershell.exe"
$proc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" mordor:check-on-edit"
$proc.UseShellExecute = $false
$proc.CreateNoWindow = $true
$proc.RedirectStandardInput = $true
$proc.RedirectStandardOutput = $true
$proc.RedirectStandardError = $true
$proc.EnvironmentVariables["PATH"] = ""

$p = [System.Diagnostics.Process]::Start($proc)
$p.StandardInput.WriteLine($stdinJson)
$p.StandardInput.Close()
$stdoutTask = $p.StandardOutput.ReadToEndAsync()
$stderrTask = $p.StandardError.ReadToEndAsync()
$p.WaitForExit(15000) | Out-Null
$exitCode = $p.ExitCode
$stderrOut = $stderrTask.Result.Trim()

Assert-True ($exitCode -eq 0) "Exit code is 0 when ruff absent (got $exitCode)"
Assert-True ($stderrOut.Length -eq 0) "No stderr when ruff absent (got: $stderrOut)"

Remove-Item -LiteralPath $tmpDir -Recurse -Force

# ============================================================
# TEST 3: .ps1 fixture with a detectable violation
#         If PSScriptAnalyzer present: expect exit 2 + non-empty stderr.
#         If absent: skip with a note.
# ============================================================
Write-Host ""
Write-Host "=== TEST 3: .ps1 fixture with PSScriptAnalyzer ==="

$psaMods = $null
try {
    $psaMods = Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction Stop
} catch {}

if ($psaMods) {
    $tmpDir3 = Join-Path $env:TEMP "coe-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Force -Path $tmpDir3 | Out-Null

    # PSUseDeclaredVarsMoreThanAssignments -- assign a variable and never use it.
    $ps1File = Join-Path $tmpDir3 "violation.ps1"
    '$unusedVar = 42' | Set-Content -LiteralPath $ps1File -Encoding UTF8

    $stdinPs1 = '{"tool_name":"Edit","tool_input":{"file_path":"' + $ps1File.Replace('\', '\\') + '"}}'

    $proc3 = New-Object System.Diagnostics.ProcessStartInfo
    $proc3.FileName = "powershell.exe"
    $proc3.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" mordor:check-on-edit"
    $proc3.UseShellExecute = $false
    $proc3.CreateNoWindow = $true
    $proc3.RedirectStandardInput = $true
    $proc3.RedirectStandardOutput = $true
    $proc3.RedirectStandardError = $true

    $p3 = [System.Diagnostics.Process]::Start($proc3)
    $p3.StandardInput.WriteLine($stdinPs1)
    $p3.StandardInput.Close()
    $stdoutTask3 = $p3.StandardOutput.ReadToEndAsync()
    $stderrTask3 = $p3.StandardError.ReadToEndAsync()
    $p3.WaitForExit(30000) | Out-Null
    $exitCode3 = $p3.ExitCode
    $stderrOut3 = $stderrTask3.Result.Trim()

    Assert-True ($exitCode3 -eq 2) "Exit code is 2 for .ps1 with violation (got $exitCode3)"
    Assert-True ($stderrOut3.Length -gt 0) "stderr is non-empty for .ps1 with violation"

    Remove-Item -LiteralPath $tmpDir3 -Recurse -Force
} else {
    Write-Host "  SKIP: PSScriptAnalyzer not installed; skipping .ps1 violation test"
}

# ============================================================
# TEST 4: 3-entry settings-transform fixture
#   Build a settings object containing:
#     - windows-state-indicator PostToolUse entry (sentinel mordor:windows-state-indicator)
#     - format-on-edit PostToolUse entry          (sentinel mordor:format-on-edit)
#     - check-on-edit PostToolUse entry           (sentinel mordor:check-on-edit)
#   Run the transform twice (idempotency).
#   Assert: both sibling entries survive, exactly one check-on-edit entry each time.
# ============================================================
Write-Host ""
Write-Host "=== TEST 4: 3-entry settings-transform fixture ==="

$FixtureSentinel = "mordor:check-on-edit"

function F-RemoveOwnedEntries {
    param($Entries)
    $kept = @()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $owned = $false
        foreach ($hook in @($entry.hooks)) {
            $command = [string]$hook.command
            if ($command.Contains($FixtureSentinel)) {
                $owned = $true
                break
            }
        }
        if (-not $owned) {
            $kept += $entry
        }
    }
    return $kept
}

function F-NewHookEntry {
    param([string]$Matcher, [string]$Command)
    return [pscustomobject]@{
        matcher = $Matcher
        hooks   = @([pscustomobject]@{ type = "command"; command = $Command })
    }
}

function F-EnsurePropertyObject {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name)
    if (-not ($Object.PSObject.Properties.Name -contains $Name) -or $null -eq $Object.$Name) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{}) -Force
    }
}

function F-SetHookEvent {
    param(
        [Parameter(Mandatory)]$SettingsObject,
        [Parameter(Mandatory)][string]$EventName,
        [string]$Matcher,
        [Parameter(Mandatory)][string]$Command
    )
    F-EnsurePropertyObject -Object $SettingsObject -Name "hooks"
    $existing = @()
    if ($SettingsObject.hooks.PSObject.Properties.Name -contains $EventName) {
        $existing = F-RemoveOwnedEntries $SettingsObject.hooks.$EventName
    }
    $newEntries = @($existing) + (F-NewHookEntry -Matcher $Matcher -Command $Command)
    $SettingsObject.hooks | Add-Member -NotePropertyName $EventName -NotePropertyValue $newEntries -Force
}

$wsiCmd = "powershell.exe -File state.ps1 mordor:windows-state-indicator"
$foeCmd = "powershell.exe -File format-on-edit.ps1 mordor:format-on-edit"
$coeCmd = "powershell.exe -File check-on-edit.ps1 mordor:check-on-edit"

$mockSettings = [pscustomobject]@{
    hooks = [pscustomobject]@{
        PostToolUse = @(
            [pscustomobject]@{
                matcher = ""
                hooks   = @([pscustomobject]@{ type = "command"; command = $wsiCmd })
            },
            [pscustomobject]@{
                matcher = "Edit|Write"
                hooks   = @([pscustomobject]@{ type = "command"; command = $foeCmd })
            }
        )
    }
}

function Count-Sibling {
    param($Entries, [string]$Tag)
    $n = 0
    foreach ($e in @($Entries)) {
        foreach ($h in @($e.hooks)) {
            if (([string]$h.command).Contains($Tag)) { $n++ }
        }
    }
    return $n
}

# First install pass
F-SetHookEvent -SettingsObject $mockSettings -EventName "PostToolUse" -Matcher "Edit|Write" -Command $coeCmd

$pt1 = @($mockSettings.hooks.PostToolUse)
$wsiCount1 = Count-Sibling -Entries $pt1 -Tag "mordor:windows-state-indicator"
$foeCount1 = Count-Sibling -Entries $pt1 -Tag "mordor:format-on-edit"
$coeCount1 = Count-Sibling -Entries $pt1 -Tag "mordor:check-on-edit"

Assert-True ($wsiCount1 -eq 1) "WSI entry survives after first install pass (count=$wsiCount1)"
Assert-True ($foeCount1 -eq 1) "FOE entry survives after first install pass (count=$foeCount1)"
Assert-True ($coeCount1 -eq 1) "Exactly one COE entry after first install pass (count=$coeCount1)"

# Second install pass (idempotency)
F-SetHookEvent -SettingsObject $mockSettings -EventName "PostToolUse" -Matcher "Edit|Write" -Command $coeCmd

$pt2 = @($mockSettings.hooks.PostToolUse)
$wsiCount2 = Count-Sibling -Entries $pt2 -Tag "mordor:windows-state-indicator"
$foeCount2 = Count-Sibling -Entries $pt2 -Tag "mordor:format-on-edit"
$coeCount2 = Count-Sibling -Entries $pt2 -Tag "mordor:check-on-edit"

Assert-True ($wsiCount2 -eq 1) "WSI entry survives after second install pass (count=$wsiCount2)"
Assert-True ($foeCount2 -eq 1) "FOE entry survives after second install pass (count=$foeCount2)"
Assert-True ($coeCount2 -eq 1) "Exactly one COE entry after second install pass (count=$coeCount2)"

# ============================================================
# TEST 5: miscellaneous guards -- empty stdin, missing file_path
# ============================================================
Write-Host ""
Write-Host "=== TEST 5: guard conditions -- empty stdin, missing file_path ==="

$proc5a = New-Object System.Diagnostics.ProcessStartInfo
$proc5a.FileName = "powershell.exe"
$proc5a.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" mordor:check-on-edit"
$proc5a.UseShellExecute = $false
$proc5a.CreateNoWindow = $true
$proc5a.RedirectStandardInput = $true
$proc5a.RedirectStandardOutput = $true
$proc5a.RedirectStandardError = $true

$p5a = [System.Diagnostics.Process]::Start($proc5a)
$p5a.StandardInput.Close()
$p5a.StandardOutput.ReadToEnd() | Out-Null
$p5a.StandardError.ReadToEnd() | Out-Null
$p5a.WaitForExit(10000) | Out-Null
Assert-True ($p5a.ExitCode -eq 0) "Exit 0 for empty stdin (got $($p5a.ExitCode))"

$proc5b = New-Object System.Diagnostics.ProcessStartInfo
$proc5b.FileName = "powershell.exe"
$proc5b.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" mordor:check-on-edit"
$proc5b.UseShellExecute = $false
$proc5b.CreateNoWindow = $true
$proc5b.RedirectStandardInput = $true
$proc5b.RedirectStandardOutput = $true
$proc5b.RedirectStandardError = $true

$p5b = [System.Diagnostics.Process]::Start($proc5b)
$p5b.StandardInput.WriteLine('{"tool_name":"Edit","tool_input":{"other":"foo"}}')
$p5b.StandardInput.Close()
$p5b.StandardOutput.ReadToEnd() | Out-Null
$p5b.StandardError.ReadToEnd() | Out-Null
$p5b.WaitForExit(10000) | Out-Null
Assert-True ($p5b.ExitCode -eq 0) "Exit 0 for missing file_path (got $($p5b.ExitCode))"

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "Results: $pass passed, $fail failed"
if ($fail -gt 0) {
    exit 1
}
exit 0
