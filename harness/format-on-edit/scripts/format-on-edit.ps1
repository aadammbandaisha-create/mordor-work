# format-on-edit.ps1
# PostToolUse hook: runs the project-local formatter on the file Claude just edited/wrote.
# Never blocks the conversation; always exits 0.
# Sentinel arg (mordor:format-on-edit) is accepted and ignored.

$ErrorActionPreference = "SilentlyContinue"

# ---- optional debug log -----------------------------------------------
function Write-DebugLog {
    param([string]$Message)
    if ($env:CLAUDE_FORMAT_DEBUG -eq "1") {
        $logPath = Join-Path $env:USERPROFILE ".claude\format-on-edit.log"
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$ts $Message" | Add-Content -LiteralPath $logPath -Encoding UTF8
    }
}

# ---- read stdin JSON ---------------------------------------------------
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

# ---- extract file_path -------------------------------------------------
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

# ---- size guard (>1 MB) ------------------------------------------------
$item = Get-Item -LiteralPath $filePath
if ($item.Length -gt 1048576) {
    Write-DebugLog "File >1MB; skipping: $filePath"
    exit 0
}

# ---- path exclusions ---------------------------------------------------
$normalised = $filePath.Replace("\", "/")
foreach ($seg in @("node_modules", ".git", "/dist/", "/build/")) {
    if ($normalised -like "*$seg*") {
        Write-DebugLog "Excluded path segment '$seg': $filePath"
        exit 0
    }
}

# ---- helper: walk up to find a file ------------------------------------
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

# ---- helper: run an external formatter with a 15-second timeout --------
# RawArgs: pre-built argument string passed directly to the process (used for
# cmd.exe /c calls so the /c switch is not wrapped in quotes).
# QuotedArgs: array of individual arguments that each get double-quoted.
# Exactly one of RawArgs or QuotedArgs must be supplied.
function Invoke-WithTimeout {
    param(
        [string]$Exe,
        [string]$RawArgs = "",
        [string[]]$QuotedArgs = @(),
        [int]$TimeoutMs = 15000
    )
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        if ($RawArgs -ne "") {
            $psi.Arguments = $RawArgs
        } else {
            $psi.Arguments = ($QuotedArgs | ForEach-Object { "`"$_`"" }) -join " "
        }
        # Do NOT redirect stdout/stderr: reading them on WaitForExit would
        # require async draining to avoid a deadlock on large output. Since
        # this is a silent hook we simply let the OS discard the output.
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $finished = $proc.WaitForExit($TimeoutMs)
        if (-not $finished) {
            try { $proc.Kill() } catch {}
            Write-DebugLog "Formatter timed out ($TimeoutMs ms): $Exe"
        } else {
            Write-DebugLog "Formatter exited $($proc.ExitCode): $Exe"
        }
    } catch {
        Write-DebugLog "Formatter error: $($_.Exception.Message)"
    }
}

# ---- dispatch by extension ---------------------------------------------
$ext = [System.IO.Path]::GetExtension($filePath).ToLower()
$fileDir = [System.IO.Path]::GetDirectoryName($filePath)

$jsExts = @(".js", ".jsx", ".ts", ".tsx", ".json", ".css", ".scss", ".md", ".html", ".yml", ".yaml")
$pyExts = @(".py")
$psExts = @(".ps1", ".psm1")

if ($jsExts -contains $ext) {
    # Walk up for node_modules\.bin\prettier.cmd then biome.cmd
    $prettierCmd = Find-FileUpward -StartDir $fileDir -FileName "node_modules\.bin\prettier.cmd"
    $biomeCmd = Find-FileUpward -StartDir $fileDir -FileName "node_modules\.bin\biome.cmd"

    if ($prettierCmd) {
        Write-DebugLog "Running prettier on $filePath"
        $pCmd = $prettierCmd.Replace('"', '\"')
        $pFile = $filePath.Replace('"', '\"')
        Invoke-WithTimeout -Exe "cmd.exe" -RawArgs "/c `"$pCmd`" --write `"$pFile`""
    } elseif ($biomeCmd) {
        Write-DebugLog "Running biome on $filePath"
        $bCmd = $biomeCmd.Replace('"', '\"')
        $bFile = $filePath.Replace('"', '\"')
        Invoke-WithTimeout -Exe "cmd.exe" -RawArgs "/c `"$bCmd`" format --write `"$bFile`""
    } else {
        Write-DebugLog "No local prettier or biome found for $filePath"
    }

} elseif ($pyExts -contains $ext) {
    $ruffFound = $false
    try {
        $ruffCmd = Get-Command ruff -ErrorAction Stop
        $ruffFound = $true
    } catch {}

    if ($ruffFound) {
        $pyprojectPath = Find-FileUpward -StartDir $fileDir -FileName "pyproject.toml"
        $ruffTomlPath = Find-FileUpward -StartDir $fileDir -FileName "ruff.toml"
        if ($pyprojectPath -or $ruffTomlPath) {
            Write-DebugLog "Running ruff format on $filePath"
            Invoke-WithTimeout -Exe "ruff" -QuotedArgs @("format", $filePath)
        } else {
            Write-DebugLog "No pyproject.toml or ruff.toml found; skipping ruff for $filePath"
        }
    } else {
        Write-DebugLog "ruff not available; skipping $filePath"
    }

} elseif ($psExts -contains $ext) {
    $psaAvailable = $false
    try {
        $mods = Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction Stop
        if ($mods) { $psaAvailable = $true }
    } catch {}

    if ($psaAvailable) {
        try {
            Import-Module PSScriptAnalyzer -ErrorAction Stop
            $original = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
            $formatted = Invoke-Formatter -ScriptDefinition $original -ErrorAction Stop
            if ($formatted -ne $original) {
                $formatted | Set-Content -LiteralPath $filePath -Encoding UTF8 -NoNewline
                Write-DebugLog "PSScriptAnalyzer formatted $filePath"
            } else {
                Write-DebugLog "PSScriptAnalyzer: no changes for $filePath"
            }
        } catch {
            Write-DebugLog "PSScriptAnalyzer error: $($_.Exception.Message)"
        }
    } else {
        Write-DebugLog "PSScriptAnalyzer not available; skipping $filePath"
    }

} else {
    Write-DebugLog "No formatter for extension '$ext'; skipping $filePath"
}

exit 0
