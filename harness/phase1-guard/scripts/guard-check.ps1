# guard-check.ps1
# PreToolUse hook: detects destructive shell commands and logs them.
# Default mode: LOG-ONLY. Never blocks. Always exits 0 unless MORDOR_GUARD_MODE=enforce.
# Sentinel arg (mordor:phase1-guard) is accepted and ignored.
#
# Stdin JSON expected fields:
#   tool_name       string   e.g. "Bash"
#   tool_input      object   { command: "..." } for Bash / PowerShell

$ErrorActionPreference = "SilentlyContinue"

# ---- DESTRUCTIVE PATTERN LIST (edit here to add/remove patterns) --------
# Each entry is a regex (case-insensitive) matched against the command string.
# The first capturing group (or the full match) is used as matchedPattern in the log.
$DestructivePatterns = @(
    # Unix hard-deletes
    "rm\s+(-\S*r\S*f|-\S*f\S*r)\b",
    # Windows rmdir / rd with /s
    "(?:rd|rmdir)\s+/s\b",
    # Windows del with wildcards and /f or /q
    "del\s+/[fq].*\*",
    # PowerShell Remove-Item with both -Recurse and -Force
    "Remove-Item\b.*-Recurse\b.*-Force\b",
    "Remove-Item\b.*-Force\b.*-Recurse\b",
    # git destructive ops
    "git\s+reset\s+--hard\b",
    "git\s+clean\s+-\S*f\S*d\b",
    "git\s+clean\s+-\S*d\S*f\b",
    "git\s+push\b.*(?:--force(?!-with-lease)\b|-f\b)",
    "git\s+checkout\s+--\s*\.",
    "git\s+checkout\s+\.\s*$",
    # Redirection onto known config files
    ">\s*~[/\\]\.claude[/\\]settings\.json\b",
    ">\s*%USERPROFILE%[/\\]\.claude[/\\]settings\.json\b",
    # Drive formatting
    "\bformat\s+[a-zA-Z]:",
    # Disk management tools
    "\bdiskpart\b",
    "\bcipher\s+/w\b",
    # Ownership / ACL abuse
    "\btakeown\b",
    "icacls\b.*\/grant\s+everyone\b",
    # Fork bomb
    ":\(\)\{",
    # Power / shutdown
    "\bshutdown\b",
    "\bStop-Computer\b",
    # PowerShell storage destructors
    "\bFormat-Volume\b",
    "\bClear-Disk\b"
)

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
    exit 0
}

# ---- extract command string ----------------------------------------------
$command = $null
try {
    if ($payload.PSObject.Properties.Name -contains "tool_input") {
        $ti = $payload.tool_input
        if ($ti -and $ti.PSObject.Properties.Name -contains "command") {
            $command = [string]$ti.command
        }
    }
} catch {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($command)) {
    exit 0
}

$toolName = ""
try {
    if ($payload.PSObject.Properties.Name -contains "tool_name") {
        $toolName = [string]$payload.tool_name
    }
} catch {}

# ---- match against patterns ----------------------------------------------
$matchedPattern = $null
foreach ($pattern in $DestructivePatterns) {
    try {
        if ($command -imatch $pattern) {
            $matchedPattern = $pattern
            break
        }
    } catch {
        # bad regex -- skip
    }
}

if ($null -eq $matchedPattern) {
    exit 0
}

# ---- matched: log --------------------------------------------------------
$logDir = Join-Path $env:USERPROFILE ".claude"
$logPath = Join-Path $logDir "guard-log.jsonl"

# Allow override for testing via MORDOR_GUARD_LOG env var
if (-not [string]::IsNullOrWhiteSpace($env:MORDOR_GUARD_LOG)) {
    $logPath = $env:MORDOR_GUARD_LOG
}

$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$commandTrunc = $command
if ($commandTrunc.Length -gt 400) {
    $commandTrunc = $commandTrunc.Substring(0, 400)
}

# Determine mode before building the log entry so the audit record is accurate
$modeField = if ($env:MORDOR_GUARD_MODE -eq "enforce") { "enforce" } else { "log-only" }

$logEntry = [pscustomobject]@{
    ts             = $ts
    tool           = $toolName
    matchedPattern = $matchedPattern
    command        = $commandTrunc
    wouldBlock     = $true
    mode           = $modeField
}

try {
    $logDir2 = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $logDir2)) {
        New-Item -ItemType Directory -Force -Path $logDir2 | Out-Null
    }
    ($logEntry | ConvertTo-Json -Compress) | Add-Content -LiteralPath $logPath -Encoding UTF8
} catch {}

# ---- enforce mode --------------------------------------------------------
$mode = $env:MORDOR_GUARD_MODE
if ($mode -eq "enforce") {
    [Console]::Error.WriteLine("Blocked by mordor phase1-guard: $matchedPattern")
    exit 2
}

# log-only (default): allow
exit 0
