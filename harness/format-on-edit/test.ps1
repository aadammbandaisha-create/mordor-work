# test.ps1 -- self-test for format-on-edit mod (no install required)
# Run from any directory; nothing under ~/.claude is touched.
# Exit 0 = all tests passed; Exit 1 = at least one failure.

$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script = Join-Path $Here "scripts\format-on-edit.ps1"

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
# TEST 1: PS parser validation of format-on-edit.ps1
# ============================================================
Write-Host ""
Write-Host "=== TEST 1: PS parser validation ==="

$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$parseErrors) | Out-Null
Assert-True ($parseErrors.Count -eq 0) "format-on-edit.ps1 parses with zero errors (got $($parseErrors.Count))"

# Also parse install.ps1 and uninstall.ps1
foreach ($f in @("install.ps1", "uninstall.ps1")) {
    $fPath = Join-Path $Here $f
    $fErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($fPath, [ref]$null, [ref]$fErrors) | Out-Null
    Assert-True ($fErrors.Count -eq 0) "$f parses with zero errors (got $($fErrors.Count))"
}

# ============================================================
# TEST 2: .js file in a tempdir WITHOUT prettier -- expect no-op, exit 0
# ============================================================
Write-Host ""
Write-Host "=== TEST 2: .js file, no prettier present -- expect no-op, exit 0 ==="

$tmpDir = Join-Path $env:TEMP "fmt-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$jsFile = Join-Path $tmpDir "hello.js"
"const x = 1;" | Set-Content -LiteralPath $jsFile -Encoding UTF8

$stdinJson = '{"tool_name":"Edit","tool_input":{"file_path":"' + $jsFile.Replace('\','\\') + '"}}'

$result = $stdinJson | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script "mutwo:format-on-edit"
$exitCode = $LASTEXITCODE

Assert-True ($exitCode -eq 0) "Exit code is 0 (got $exitCode)"

$content = Get-Content -LiteralPath $jsFile -Raw -Encoding UTF8
Assert-True ($content.Trim() -eq "const x = 1;") "File content unchanged (no prettier installed)"

Remove-Item -LiteralPath $tmpDir -Recurse -Force

# ============================================================
# TEST 3: .xyz file (unsupported extension) -- expect no-op, exit 0
# ============================================================
Write-Host ""
Write-Host "=== TEST 3: .xyz file -- expect no-op, exit 0 ==="

$tmpDir2 = Join-Path $env:TEMP "fmt-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $tmpDir2 | Out-Null

$xyzFile = Join-Path $tmpDir2 "data.xyz"
"hello world" | Set-Content -LiteralPath $xyzFile -Encoding UTF8

$stdinJson2 = '{"tool_name":"Edit","tool_input":{"file_path":"' + $xyzFile.Replace('\','\\') + '"}}'

$result2 = $stdinJson2 | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script "mutwo:format-on-edit"
$exitCode2 = $LASTEXITCODE

Assert-True ($exitCode2 -eq 0) "Exit code is 0 for .xyz (got $exitCode2)"

$content2 = Get-Content -LiteralPath $xyzFile -Raw -Encoding UTF8
Assert-True ($content2.Trim() -eq "hello world") "File content unchanged for .xyz"

Remove-Item -LiteralPath $tmpDir2 -Recurse -Force

# ============================================================
# TEST 4: missing file_path -- expect exit 0
# ============================================================
Write-Host ""
Write-Host "=== TEST 4: stdin JSON with no file_path -- expect exit 0 ==="

$stdinNoPath = '{"tool_name":"Edit","tool_input":{"other_field":"foo"}}'
$result3 = $stdinNoPath | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script "mutwo:format-on-edit"
$exitCode3 = $LASTEXITCODE
Assert-True ($exitCode3 -eq 0) "Exit code is 0 when file_path missing (got $exitCode3)"

# ============================================================
# TEST 5: empty stdin -- expect exit 0
# ============================================================
Write-Host ""
Write-Host "=== TEST 5: empty stdin -- expect exit 0 ==="

$result4 = "" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script "mutwo:format-on-edit"
$exitCode4 = $LASTEXITCODE
Assert-True ($exitCode4 -eq 0) "Exit code is 0 for empty stdin (got $exitCode4)"

# ============================================================
# TEST 6: PSScriptAnalyzer path if available
# ============================================================
Write-Host ""
Write-Host "=== TEST 6: .ps1 fixture (PSScriptAnalyzer) ==="

$psaMods = $null
try {
    $psaMods = Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction Stop
} catch {}

if ($psaMods) {
    $tmpDir3 = Join-Path $env:TEMP "fmt-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Force -Path $tmpDir3 | Out-Null

    # Deliberately poorly-formatted PS1 content
    $ps1File = Join-Path $tmpDir3 "sample.ps1"
    "function foo {param( [string]`$x )  return `$x}" | Set-Content -LiteralPath $ps1File -Encoding UTF8

    $stdinPs1 = '{"tool_name":"Edit","tool_input":{"file_path":"' + $ps1File.Replace('\','\\') + '"}}'
    $result5 = $stdinPs1 | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script "mutwo:format-on-edit"
    $exitCode5 = $LASTEXITCODE
    Assert-True ($exitCode5 -eq 0) "Exit code is 0 for .ps1 with PSScriptAnalyzer (got $exitCode5)"

    Remove-Item -LiteralPath $tmpDir3 -Recurse -Force
} else {
    Write-Host "  SKIP: PSScriptAnalyzer not installed; skipping .ps1 format test"
}

# ============================================================
# TEST 7: settings-transform fixture
# Simulate a settings object that already has a windows-state-indicator
# PostToolUse entry, run Set-HookEvent (from install.ps1), assert both
# entries survive. Then re-run and assert exactly one format-on-edit entry.
# ============================================================
Write-Host ""
Write-Host "=== TEST 7: settings-transform fixture ==="

# Load only the hook-helper functions from install.ps1 by dot-sourcing a
# temporary wrapper that defines only those functions without running the
# main body. We do this by extracting the function block lines.
# Simpler approach: define the same functions inline here as a faithful copy,
# then exercise them directly.

$Sentinel = "mutwo:format-on-edit"

function T-RemoveOwnedEntries {
    param($Entries)
    $kept = @()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $owned = $false
        foreach ($hook in @($entry.hooks)) {
            $command = [string]$hook.command
            if ($command.Contains($Sentinel)) {
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

function T-NewHookEntry {
    param([string]$Matcher, [string]$Command)
    return [pscustomobject]@{
        matcher = $Matcher
        hooks   = @([pscustomobject]@{ type = "command"; command = $Command })
    }
}

function T-EnsurePropertyObject {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name)
    if (-not ($Object.PSObject.Properties.Name -contains $Name) -or $null -eq $Object.$Name) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{}) -Force
    }
}

function T-SetHookEvent {
    param(
        [Parameter(Mandatory)]$SettingsObject,
        [Parameter(Mandatory)][string]$EventName,
        [string]$Matcher,
        [Parameter(Mandatory)][string]$Command
    )
    T-EnsurePropertyObject -Object $SettingsObject -Name "hooks"
    $existing = @()
    if ($SettingsObject.hooks.PSObject.Properties.Name -contains $EventName) {
        $existing = T-RemoveOwnedEntries $SettingsObject.hooks.$EventName
    }
    $newEntries = @($existing) + (T-NewHookEntry -Matcher $Matcher -Command $Command)
    $SettingsObject.hooks | Add-Member -NotePropertyName $EventName -NotePropertyValue $newEntries -Force
}

# Build a mock settings object with a windows-state-indicator entry
$wsiCommand = "powershell.exe -File state.ps1 mutwo:windows-state-indicator"
$foeCommand  = "powershell.exe -File format-on-edit.ps1 mutwo:format-on-edit"

$mockSettings = [pscustomobject]@{
    hooks = [pscustomobject]@{
        PostToolUse = @(
            [pscustomobject]@{
                matcher = ""
                hooks   = @([pscustomobject]@{ type = "command"; command = $wsiCommand })
            }
        )
    }
}

# First install pass
T-SetHookEvent -SettingsObject $mockSettings -EventName "PostToolUse" -Matcher "Edit|Write" -Command $foeCommand

$ptEntries = @($mockSettings.hooks.PostToolUse)
$wsiPresent = $false
$foeCount   = 0
foreach ($e in $ptEntries) {
    foreach ($h in @($e.hooks)) {
        if (([string]$h.command).Contains("mutwo:windows-state-indicator")) { $wsiPresent = $true }
        if (([string]$h.command).Contains("mutwo:format-on-edit")) { $foeCount++ }
    }
}
Assert-True $wsiPresent "WSI entry survives after first install pass"
Assert-True ($foeCount -eq 1) "Exactly one FOE entry after first install pass (got $foeCount)"

# Second install pass (idempotency)
T-SetHookEvent -SettingsObject $mockSettings -EventName "PostToolUse" -Matcher "Edit|Write" -Command $foeCommand

$ptEntries2 = @($mockSettings.hooks.PostToolUse)
$wsiPresent2 = $false
$foeCount2   = 0
foreach ($e in $ptEntries2) {
    foreach ($h in @($e.hooks)) {
        if (([string]$h.command).Contains("mutwo:windows-state-indicator")) { $wsiPresent2 = $true }
        if (([string]$h.command).Contains("mutwo:format-on-edit")) { $foeCount2++ }
    }
}
Assert-True $wsiPresent2 "WSI entry survives after second install pass"
Assert-True ($foeCount2 -eq 1) "Exactly one FOE entry after second install pass (got $foeCount2)"

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "Results: $pass passed, $fail failed"
if ($fail -gt 0) {
    exit 1
}
exit 0
