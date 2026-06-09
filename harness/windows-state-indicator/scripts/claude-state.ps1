[CmdletBinding()]
param(
    [ValidateSet("working", "idle")]
    [string]$State = "idle",
    [string]$Sentinel = ""
)

$ErrorActionPreference = "SilentlyContinue"

function Get-StringValue {
    param($Value, [string]$Fallback = "")
    if ($null -eq $Value) {
        return $Fallback
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Fallback
    }
    return $text
}

function Get-AssistantText {
    param($Message)
    if ($null -eq $Message) {
        return ""
    }
    $content = $Message.content
    if ($null -eq $content) {
        return ""
    }
    if ($content -is [string]) {
        return $content
    }
    $parts = @()
    foreach ($item in @($content)) {
        if ($item.type -eq "text" -and $item.text) {
            $parts += [string]$item.text
        }
    }
    return ($parts -join "`n")
}

function Get-LastAssistantSummary {
    param([string]$TranscriptPath)
    if ([string]::IsNullOrWhiteSpace($TranscriptPath) -or -not (Test-Path -LiteralPath $TranscriptPath)) {
        return ""
    }
    $lines = Get-Content -LiteralPath $TranscriptPath -Tail 300
    [array]::Reverse($lines)
    foreach ($line in $lines) {
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        if ($event.type -eq "assistant") {
            $text = Get-AssistantText -Message $event.message
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                return $text
            }
        }
    }
    return ""
}

function Compress-Summary {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }
    $paragraphs = $Text -split "(\r?\n\s*\r?\n)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $last = if ($paragraphs.Count -gt 0) { $paragraphs[-1] } else { $Text }
    $clean = ($last -replace "\s+", " ").Trim()
    if ($clean.Length -gt 500) {
        return $clean.Substring(0, 500)
    }
    return $clean
}

function Show-WindowsNotification {
    param(
        [string]$Title,
        [string]$Body
    )
    if ([string]::IsNullOrWhiteSpace($Title)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($Body)) {
        $Body = "waiting on you"
    }

    $burntToast = Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue
    if ($burntToast) {
        New-BurntToastNotification -Text $Title, $Body | Out-Null
        return
    }

    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    Add-Type -AssemblyName System.Drawing | Out-Null
    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
    $notifyIcon.BalloonTipTitle = $Title
    $notifyIcon.BalloonTipText = $Body
    $notifyIcon.Visible = $true
    $notifyIcon.ShowBalloonTip(5000)
    Start-Sleep -Milliseconds 750
    $notifyIcon.Dispose()
}

$inputJson = [Console]::In.ReadToEnd()
$payload = $null
if (-not [string]::IsNullOrWhiteSpace($inputJson)) {
    try {
        $payload = $inputJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $payload = $null
    }
}

$sessionId = "unknown-$PID"
$transcript = ""
$cwd = ""
$hookEvent = ""
$hookMessage = ""
$toolName = ""
$lastAssistant = ""
$questionText = ""

if ($payload) {
    $sessionId = Get-StringValue $payload.session_id $sessionId
    $transcript = Get-StringValue $payload.transcript_path ""
    $cwd = Get-StringValue $payload.cwd ""
    $hookEvent = Get-StringValue $payload.hook_event_name ""
    $hookMessage = Get-StringValue $payload.message ""
    $toolName = Get-StringValue $payload.tool_name ""
    $lastAssistant = Get-StringValue $payload.last_assistant_message ""
    if ($hookEvent -eq "PreToolUse" -and $toolName -eq "AskUserQuestion" -and $payload.tool_input) {
        $questions = @($payload.tool_input.questions)
        if ($questions.Count -gt 0) {
            $questionText = Get-StringValue $questions[0].question ""
        }
    }
}

$rawSummary = $lastAssistant
if ([string]::IsNullOrWhiteSpace($rawSummary)) {
    $rawSummary = Get-LastAssistantSummary -TranscriptPath $transcript
}
$summary = Compress-Summary -Text $rawSummary

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$stateDir = Join-Path $claudeDir "state"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

Get-ChildItem -LiteralPath $stateDir -Filter "*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$stateFile = Join-Path $stateDir "$sessionId.json"
$statePayload = [pscustomobject]@{
    state = $State
    label = if ($State -eq "working") { "[WORKING]" } else { "[IDLE]" }
    summary = $summary
    cwd = $cwd
    hook_event = $hookEvent
    tool_name = $toolName
    transcript_path = $transcript
    updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
$statePayload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $stateFile -Encoding UTF8

try {
    $titleSummary = if ($summary.Length -gt 80) { $summary.Substring(0, 80) } else { $summary }
    [Console]::Title = "Claude $($statePayload.label) $titleSummary"
} catch {}

$isIdleReminder = $false
if ($hookEvent -eq "Notification" -and $hookMessage -match "waiting for your input") {
    $isIdleReminder = $true
}

if ($State -eq "idle" -and -not $isIdleReminder) {
    if (-not [string]::IsNullOrWhiteSpace($questionText)) {
        Show-WindowsNotification -Title "Claude needs an answer" -Body $questionText
    } elseif ($hookEvent -eq "Notification" -and -not [string]::IsNullOrWhiteSpace($hookMessage)) {
        Show-WindowsNotification -Title "Claude has stopped working" -Body $hookMessage
    } else {
        Show-WindowsNotification -Title "Claude has stopped working" -Body $summary
    }
}

exit 0
