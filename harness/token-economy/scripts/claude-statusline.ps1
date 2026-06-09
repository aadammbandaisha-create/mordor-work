[CmdletBinding()]
param(
    [string]$Sentinel = ""
)

$ErrorActionPreference = "SilentlyContinue"

$raw = [Console]::In.ReadToEnd()
$data = $null
if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $data = $null
    }
}

$model = ""
$costUsd = $null
$transcript = ""
$cwd = ""

if ($data) {
    if ($data.model -and $data.model.display_name) {
        $model = [string]$data.model.display_name
    }
    if ($data.cost -and $null -ne $data.cost.total_cost_usd) {
        $costUsd = [double]$data.cost.total_cost_usd
    }
    if ($data.transcript_path) {
        $transcript = [string]$data.transcript_path
    }
    if ($data.workspace -and $data.workspace.current_dir) {
        $cwd = [string]$data.workspace.current_dir
    } elseif ($data.cwd) {
        $cwd = [string]$data.cwd
    }
}

function Get-ContextTokens {
    param([string]$TranscriptPath)
    if ([string]::IsNullOrWhiteSpace($TranscriptPath) -or -not (Test-Path -LiteralPath $TranscriptPath)) {
        return 0
    }
    $lines = Get-Content -LiteralPath $TranscriptPath -Tail 120
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        try {
            $evt = $lines[$i] | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        if ($evt.isSidechain -eq $true) {
            continue
        }
        if ($evt.type -ne "assistant" -or $null -eq $evt.message -or $null -eq $evt.message.usage) {
            continue
        }
        $usage = $evt.message.usage
        if ($null -eq $usage.input_tokens) {
            continue
        }
        $total = [int64]$usage.input_tokens
        foreach ($field in @("cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens")) {
            if ($usage.PSObject.Properties.Name -contains $field -and $usage.$field) {
                $total += [int64]$usage.$field
            }
        }
        return $total
    }
    return 0
}

function Get-GitBranch {
    param([string]$StartDir)
    if ([string]::IsNullOrWhiteSpace($StartDir)) {
        return ""
    }
    $dir = $StartDir
    while ($dir) {
        $headFile = Join-Path $dir ".git\HEAD"
        if (Test-Path -LiteralPath $headFile) {
            $head = Get-Content -LiteralPath $headFile -TotalCount 1
            if ($head -match "ref: refs/heads/(.+)$") {
                return $Matches[1]
            }
            return $head.Substring(0, [Math]::Min(7, $head.Length))
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) {
            break
        }
        $dir = $parent
    }
    return ""
}

$limit = 200000
$used = Get-ContextTokens -TranscriptPath $transcript
$branch = Get-GitBranch -StartDir $cwd

$esc = [char]27
$reset = "$esc[0m"
$dim = "$esc[2m"
$green = "$esc[32m"
$yellow = "$esc[33m"
$red = "$esc[31m"
$cyan = "$esc[36m"

$segments = @()

if ($model) {
    $segments += "$cyan$model$reset"
}

if ($used -gt 0) {
    $pct = [math]::Round(100.0 * $used / $limit)
    $color = $green
    $warn = ""
    if ($pct -ge 80) {
        $color = $red
        $warn = " COMPACT SOON"
    } elseif ($pct -ge 60) {
        $color = $yellow
    }
    $usedK = [math]::Round($used / 1000.0)
    $segments += "${color}ctx ${pct}% (${usedK}k/200k)${warn}$reset"
}

if ($null -ne $costUsd -and $costUsd -gt 0) {
    $segments += ('${0:N2}' -f $costUsd)
}

if ($branch) {
    $segments += "${dim}git:$branch$reset"
}

if ($segments.Count -eq 0) {
    Write-Output "Claude"
} else {
    Write-Output ($segments -join " $dim|$reset ")
}
