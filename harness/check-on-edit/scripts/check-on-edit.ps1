# check-on-edit.ps1
# PostToolUse hook: runs cheap project-local lint/type checks on the file
# Claude just edited/wrote. If problems are found, writes them to stderr and
# exits 2 so Claude sees the feedback on its next turn. Always exits 0 on
# tooling absence, guard conditions, or checker errors (no false positives).
# Sentinel arg (mordor:check-on-edit) is accepted and ignored.

$ErrorActionPreference = "SilentlyContinue"

# ---- optional debug log --------------------------------------------------
function Write-DebugLog {
    param([string]$Message)
    if ($env:CLAUDE_CHECK_DEBUG -eq "1") {
        $logPath = Join-Path $env:USERPROFILE ".claude\check-on-edit.log"
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$ts $Message" | Add-Content -LiteralPath $logPath -Encoding UTF8
    }
}

# ---- read stdin JSON -----------------------------------------------------
$raw = $null
try {
    $raw = [Console]::In.ReadToEnd()
} catch {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($raw)) {
    exit 0
}

$payload = $null
try {
    $payload = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-DebugLog "JSON parse error: $($_.Exception.Message)"
    exit 0
}

# ---- extract file_path ---------------------------------------------------
$filePath = $null
try {
    if ($payload.PSObject.Properties.Name -contains "tool_input") {
        $ti = $payload.tool_input
        if ($ti -and $ti.PSObject.Properties.Name -contains "file_path") {
            $filePath = [string]$ti.file_path
        }
    }
} catch {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($filePath)) {
    Write-DebugLog "No file_path in input; skipping"
    exit 0
}

if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
    Write-DebugLog "file_path not found or not a file: $filePath"
    exit 0
}

# ---- size guard (>1 MB) -------------------------------------------------
$item = Get-Item -LiteralPath $filePath
if ($item.Length -gt 1048576) {
    Write-DebugLog "File >1MB; skipping: $filePath"
    exit 0
}

# ---- path exclusions -----------------------------------------------------
$normalised = $filePath.Replace("\", "/")
foreach ($seg in @("node_modules", ".git", "/dist/", "/build/")) {
    if ($normalised -like "*$seg*") {
        Write-DebugLog "Excluded path segment '$seg': $filePath"
        exit 0
    }
}

# ---- helper: walk up to find a file/dir ----------------------------------
function Find-FileUpward {
    param([string]$StartDir, [string]$FileName)
    $dir = $StartDir
    while ($true) {
        $candidate = Join-Path $dir $FileName
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) {
            return $null
        }
        $dir = $parent
    }
}

# ---- helper: run checker, capture output, 12s timeout -------------------
# Returns a hashtable: @{ Output = "..."; ExitCode = N; TimedOut = $false }
# On any process-launch error returns $null.
function Invoke-Checker {
    param(
        [string]$Exe,
        [string]$Arguments,
        [int]$TimeoutMs = 12000
    )
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)

        # Drain stdout and stderr asynchronously to avoid deadlock.
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $finished = $proc.WaitForExit($TimeoutMs)
        if (-not $finished) {
            try { $proc.Kill() } catch {}
            Write-DebugLog "Checker timed out ($TimeoutMs ms): $Exe $Arguments"
            return $null
        }

        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $combined = ($stdout + $stderr).Trim()

        return @{ Output = $combined; ExitCode = $proc.ExitCode; TimedOut = $false }
    } catch {
        Write-DebugLog "Checker launch error: $($_.Exception.Message)"
        return $null
    }
}

# ---- helper: emit problems and exit 2 -----------------------------------
function Exit-WithProblems {
    param([string]$Text)
    # Cap at ~2 KB
    if ($Text.Length -gt 2048) {
        $Text = $Text.Substring(0, 2048) + "`n[...truncated]"
    }
    [Console]::Error.WriteLine($Text)
    exit 2
}

# ---- dispatch by extension ----------------------------------------------
$ext = [System.IO.Path]::GetExtension($filePath).ToLower()
$fileDir = [System.IO.Path]::GetDirectoryName($filePath)

Write-DebugLog "Processing $filePath (ext=$ext)"

# ---- .py: ruff check ----------------------------------------------------
if ($ext -eq ".py") {
    $ruffExe = $null
    try {
        $ruffCmd = Get-Command ruff -ErrorAction Stop
        $ruffExe = $ruffCmd.Source
    } catch {}

    if ($null -eq $ruffExe) {
        Write-DebugLog "ruff not found in PATH; skipping $filePath"
        exit 0
    }

    $pyprojectPath = Find-FileUpward -StartDir $fileDir -FileName "pyproject.toml"
    $ruffTomlPath = Find-FileUpward -StartDir $fileDir -FileName "ruff.toml"
    if ($null -eq $pyprojectPath -and $null -eq $ruffTomlPath) {
        Write-DebugLog "No pyproject.toml or ruff.toml found; skipping ruff for $filePath"
        exit 0
    }

    $escapedFile = $filePath.Replace('"', '\"')
    $result = Invoke-Checker -Exe $ruffExe -Arguments "check `"$escapedFile`""
    if ($null -eq $result) {
        # Tooling error or timeout -- silent exit
        exit 0
    }
    Write-DebugLog "ruff exited $($result.ExitCode) for $filePath"
    if ($result.ExitCode -eq 1 -and $result.Output.Length -gt 0) {
        Exit-WithProblems "ruff check: $filePath`n$($result.Output)"
    }
    exit 0
}

# ---- .ts/.tsx: tsc --noEmit else eslint ---------------------------------
if ($ext -eq ".ts" -or $ext -eq ".tsx") {
    # Prefer tsc if local binary found
    $tscBin = Find-FileUpward -StartDir $fileDir -FileName "node_modules\.bin\tsc.cmd"
    if ($null -eq $tscBin) {
        $tscBin = Find-FileUpward -StartDir $fileDir -FileName "node_modules\.bin\tsc"
    }

    if ($tscBin) {
        $escapedBin = $tscBin.Replace('"', '\"')
        $result = Invoke-Checker -Exe "cmd.exe" -Arguments "/c `"$escapedBin`" --noEmit --pretty false"
        if ($null -eq $result) {
            exit 0
        }
        Write-DebugLog "tsc exited $($result.ExitCode) for $filePath"
        if ($result.ExitCode -eq 1 -and $result.Output.Length -gt 0) {
            Exit-WithProblems "tsc --noEmit: $($result.Output)"
        }
        exit 0
    }

    # Fall through to eslint (shared with .js/.jsx below)
    $eslintBin = Find-FileUpward -StartDir $fileDir -FileName "node_modules\.bin\eslint.cmd"
    if ($null -eq $eslintBin) {
        $eslintBin = Find-FileUpward -StartDir $fileDir -FileName "node_modules\.bin\eslint"
    }
    if ($eslintBin) {
        $escapedBin = $eslintBin.Replace('"', '\"')
        $escapedFile = $filePath.Replace('"', '\"')
        $result = Invoke-Checker -Exe "cmd.exe" -Arguments "/c `"$escapedBin`" `"$escapedFile`" -f compact"
        if ($null -eq $result) {
            exit 0
        }
        Write-DebugLog "eslint exited $($result.ExitCode) for $filePath"
        if ($result.ExitCode -eq 1 -and $result.Output.Length -gt 0) {
            Exit-WithProblems "eslint: $filePath`n$($result.Output)"
        }
        exit 0
    }

    Write-DebugLog "No local tsc or eslint found for $filePath"
    exit 0
}

# ---- .js/.jsx: eslint ---------------------------------------------------
if ($ext -eq ".js" -or $ext -eq ".jsx") {
    $eslintBin = Find-FileUpward -StartDir $fileDir -FileName "node_modules\.bin\eslint.cmd"
    if ($null -eq $eslintBin) {
        $eslintBin = Find-FileUpward -StartDir $fileDir -FileName "node_modules\.bin\eslint"
    }
    if ($eslintBin) {
        $escapedBin = $eslintBin.Replace('"', '\"')
        $escapedFile = $filePath.Replace('"', '\"')
        $result = Invoke-Checker -Exe "cmd.exe" -Arguments "/c `"$escapedBin`" `"$escapedFile`" -f compact"
        if ($null -eq $result) {
            exit 0
        }
        Write-DebugLog "eslint exited $($result.ExitCode) for $filePath"
        if ($result.ExitCode -eq 1 -and $result.Output.Length -gt 0) {
            Exit-WithProblems "eslint: $filePath`n$($result.Output)"
        }
        exit 0
    }
    Write-DebugLog "No local eslint found for $filePath"
    exit 0
}

# ---- .ps1/.psm1: PSScriptAnalyzer ---------------------------------------
if ($ext -eq ".ps1" -or $ext -eq ".psm1") {
    $psaAvailable = $false
    try {
        $mods = Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction Stop
        if ($mods) { $psaAvailable = $true }
    } catch {}

    if (-not $psaAvailable) {
        Write-DebugLog "PSScriptAnalyzer not available; skipping $filePath"
        exit 0
    }

    try {
        Import-Module PSScriptAnalyzer -ErrorAction Stop
        $findings = Invoke-ScriptAnalyzer -Path $filePath -Severity Error,Warning -ErrorAction Stop
        if ($findings -and $findings.Count -gt 0) {
            $lines = @()
            foreach ($f in $findings) {
                $lines += "$($f.Severity) [$($f.RuleName)] line $($f.Line): $($f.Message)"
            }
            $text = "PSScriptAnalyzer: $filePath`n" + ($lines -join "`n")
            Write-DebugLog "PSScriptAnalyzer found $($findings.Count) issue(s) in $filePath"
            Exit-WithProblems $text
        }
        Write-DebugLog "PSScriptAnalyzer clean for $filePath"
    } catch {
        Write-DebugLog "PSScriptAnalyzer error: $($_.Exception.Message)"
    }
    exit 0
}

# ---- no checker for this extension --------------------------------------
Write-DebugLog "No checker for extension '$ext'; skipping $filePath"
exit 0
