[CmdletBinding()]
param(
    [int]$IntervalMilliseconds = 750,
    [ValidateSet("TopRight", "TopLeft", "BottomRight", "BottomLeft")]
    [string]$Corner = "TopRight"
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

$stateDir = Join-Path $env:USERPROFILE ".claude\state"

$form = New-Object System.Windows.Forms.Form
$form.Text = "Claude State"
$form.Width = 220
$form.Height = 58
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

$dot = New-Object System.Windows.Forms.Panel
$dot.Width = 18
$dot.Height = 18
$dot.Left = 12
$dot.Top = 14
$dot.BackColor = [System.Drawing.Color]::Gray

$label = New-Object System.Windows.Forms.Label
$label.Left = 40
$label.Top = 11
$label.Width = 160
$label.Height = 24
$label.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$label.ForeColor = [System.Drawing.Color]::White
$label.Text = "CLAUDE NO STATE"

$tip = New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($form, "Waiting for Claude Code hook state.")
$tip.SetToolTip($label, "Waiting for Claude Code hook state.")
$tip.SetToolTip($dot, "Waiting for Claude Code hook state.")

$form.Controls.Add($dot)
$form.Controls.Add($label)

function Set-WindowCorner {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $margin = 16
    switch ($Corner) {
        "TopLeft" {
            $form.Left = $screen.Left + $margin
            $form.Top = $screen.Top + $margin
        }
        "BottomRight" {
            $form.Left = $screen.Right - $form.Width - $margin
            $form.Top = $screen.Bottom - $form.Height - $margin
        }
        "BottomLeft" {
            $form.Left = $screen.Left + $margin
            $form.Top = $screen.Bottom - $form.Height - $margin
        }
        default {
            $form.Left = $screen.Right - $form.Width - $margin
            $form.Top = $screen.Top + $margin
        }
    }
}

function Get-LatestState {
    if (-not (Test-Path -LiteralPath $stateDir)) {
        return $null
    }
    $latest = Get-ChildItem -LiteralPath $stateDir -Filter "*.json" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function Update-StateLight {
    $state = Get-LatestState
    if (-not $state) {
        $dot.BackColor = [System.Drawing.Color]::Gray
        $label.Text = "CLAUDE NO STATE"
        $tipText = "No Claude state file found yet. Submit a prompt in Claude Code."
    } elseif ($state.state -eq "working") {
        $dot.BackColor = [System.Drawing.Color]::LimeGreen
        $label.Text = "CLAUDE WORKING"
        $tipText = [string]$state.summary
        if ([string]::IsNullOrWhiteSpace($tipText)) {
            $tipText = "Claude is working or running tools."
        }
    } else {
        $dot.BackColor = [System.Drawing.Color]::Red
        $label.Text = "CLAUDE IDLE"
        $tipText = [string]$state.summary
        if ([string]::IsNullOrWhiteSpace($tipText)) {
            $tipText = "Claude is waiting."
        }
    }
    $tip.SetToolTip($form, $tipText)
    $tip.SetToolTip($label, $tipText)
    $tip.SetToolTip($dot, $tipText)
}

Set-WindowCorner
Update-StateLight

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(250, $IntervalMilliseconds)
$timer.Add_Tick({ Update-StateLight })
$timer.Start()

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
