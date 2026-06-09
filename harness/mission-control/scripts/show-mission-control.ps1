[CmdletBinding()]
param(
    [switch]$RenderOnce
)

$ErrorActionPreference = "SilentlyContinue"

# ---- WPF assemblies ----
Add-Type -AssemblyName PresentationFramework | Out-Null
Add-Type -AssemblyName PresentationCore      | Out-Null
Add-Type -AssemblyName WindowsBase           | Out-Null

# ---- paths ----
$StateDir   = Join-Path $env:USERPROFILE ".claude\state"
$PosFile    = Join-Path $env:USERPROFILE ".claude\mission-control.pos"
$ProjectsDir = Join-Path $env:USERPROFILE ".claude\projects"

# ---- pricing (embedded, same as usage-report.ps1) ----
$Pricing = @{
    opus   = @{ inn = 15.0; out = 75.0; cw = 18.75; cr = 1.50 }
    sonnet = @{ inn = 3.0;  out = 15.0; cw = 3.75;  cr = 0.30 }
    haiku  = @{ inn = 1.0;  out = 5.0;  cw = 1.25;  cr = 0.10 }
}

function Get-ModelFamily {
    param([string]$ModelId)
    foreach ($family in @("opus", "sonnet", "haiku")) {
        if ($ModelId -match $family) { return $family }
    }
    return "sonnet"
}

# ---- context % from transcript (adapted from claude-statusline.ps1) ----
function Get-ContextPct {
    param([string]$TranscriptPath)
    if ([string]::IsNullOrWhiteSpace($TranscriptPath)) { return -1 }
    if (-not (Test-Path -LiteralPath $TranscriptPath)) { return -1 }
    try {
        $lines = Get-Content -LiteralPath $TranscriptPath -Tail 120 -Encoding UTF8 -ErrorAction Stop
    } catch {
        return -1
    }
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        try {
            $evt = $lines[$i] | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        if ($evt.isSidechain -eq $true) { continue }
        if ($evt.type -ne "assistant" -or $null -eq $evt.message -or $null -eq $evt.message.usage) { continue }
        $usage = $evt.message.usage
        if ($null -eq $usage.input_tokens) { continue }
        $total = [int64]$usage.input_tokens
        foreach ($field in @("cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens")) {
            if ($usage.PSObject.Properties.Name -contains $field -and $usage.$field) {
                $total += [int64]$usage.$field
            }
        }
        $pct = [math]::Round(100.0 * $total / 200000)
        if ($pct -gt 100) { $pct = 100 }
        return [int]$pct
    }
    return -1
}

# ---- today's estimated spend (adapted from usage-report.ps1) ----
function Get-TodaySpend {
    $today = (Get-Date).ToString("yyyy-MM-dd")
    if (-not (Test-Path -LiteralPath $ProjectsDir)) { return 0.0 }
    $todayCutoff = (Get-Date).Date
    try {
        $files = Get-ChildItem -LiteralPath $ProjectsDir -Recurse -Filter "*.jsonl" -ErrorAction Stop |
            Where-Object { $_.LastWriteTime -ge $todayCutoff }
    } catch {
        return 0.0
    }
    $totalCost = 0.0
    foreach ($file in $files) {
        try {
            $allLines = [System.IO.File]::ReadLines($file.FullName)
        } catch {
            continue
        }
        foreach ($line in $allLines) {
            if ($line -notmatch '"usage"') { continue }
            try {
                $evt = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                continue
            }
            if ($evt.type -ne "assistant" -or $null -eq $evt.message -or $null -eq $evt.message.usage) { continue }
            $usage = $evt.message.usage
            if ($null -eq $usage.input_tokens) { continue }

            $dayStr = ""
            if ($evt.timestamp) {
                try { $dayStr = ([datetime]$evt.timestamp).ToLocalTime().ToString("yyyy-MM-dd") } catch { $dayStr = $today }
            } else {
                $dayStr = $today
            }
            if ($dayStr -ne $today) { continue }

            $modelId = ""
            if ($evt.message.model) { $modelId = [string]$evt.message.model }
            $family = Get-ModelFamily -ModelId $modelId
            $p = $Pricing[$family]

            $inTok  = [int64]$usage.input_tokens
            $outTok = if ($usage.output_tokens)                  { [int64]$usage.output_tokens }                  else { 0 }
            $cwTok  = if ($usage.cache_creation_input_tokens)    { [int64]$usage.cache_creation_input_tokens }    else { 0 }
            $crTok  = if ($usage.cache_read_input_tokens)        { [int64]$usage.cache_read_input_tokens }        else { 0 }
            $totalCost += ($inTok * $p.inn + $outTok * $p.out + $cwTok * $p.cw + $crTok * $p.cr) / 1000000.0
        }
    }
    return $totalCost
}

# ---- load state cards ----
function Get-StateCards {
    if (-not (Test-Path -LiteralPath $StateDir)) { return @() }
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
    try {
        $files = Get-ChildItem -LiteralPath $StateDir -Filter "*.json" -ErrorAction Stop
    } catch {
        return @()
    }
    $cards = @()
    foreach ($f in $files) {
        try {
            $obj = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        $updatedAt = $null
        if ($obj.updated_at) {
            try { $updatedAt = [datetime]::Parse($obj.updated_at, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch {}
        }
        if ($null -eq $updatedAt) { $updatedAt = $f.LastWriteTimeUtc }
        if ($updatedAt -lt $cutoff) { continue }

        # title: leaf folder of cwd, else basename
        $title = $f.BaseName
        if ($obj.cwd -and -not [string]::IsNullOrWhiteSpace([string]$obj.cwd)) {
            $leaf = Split-Path -Leaf ([string]$obj.cwd)
            if (-not [string]::IsNullOrWhiteSpace($leaf)) { $title = $leaf }
        }

        $summary = ""
        if ($obj.summary) { $summary = [string]$obj.summary }
        if ($summary.Length -gt 140) { $summary = $summary.Substring(0, 140) + "..." }

        $stateVal = "idle"
        if ($obj.state) { $stateVal = [string]$obj.state }

        $transcript = ""
        if ($obj.transcript_path) { $transcript = [string]$obj.transcript_path }

        $cards += [pscustomobject]@{
            Title      = $title
            State      = $stateVal
            Summary    = $summary
            UpdatedAt  = $updatedAt
            Transcript = $transcript
        }
    }
    # sort newest first, cap 8
    $cards = $cards | Sort-Object UpdatedAt -Descending | Select-Object -First 8
    return @($cards)
}

function Get-RelativeAge {
    param([datetime]$UpdatedAt)
    $diff = (Get-Date).ToUniversalTime() - $UpdatedAt
    if ($diff.TotalSeconds -lt 60)  { return ("{0:N0}s ago" -f $diff.TotalSeconds) }
    if ($diff.TotalMinutes -lt 60)  { return ("{0:N0}m ago" -f $diff.TotalMinutes) }
    if ($diff.TotalHours   -lt 24)  { return ("{0:N0}h ago" -f $diff.TotalHours) }
    return ("{0:N0}d ago" -f $diff.TotalDays)
}

function Get-StateColor {
    param([string]$State, [datetime]$UpdatedAt)
    $ageMins = ((Get-Date).ToUniversalTime() - $UpdatedAt).TotalMinutes
    if ($ageMins -gt 10) { return "#9a9a9a" }  # stale = gray
    if ($State -eq "working") { return "#2ecc71" }  # green
    return "#e74c3c"  # red
}

# ---- headless self-test (-RenderOnce) ----
if ($RenderOnce) {
    $cards = Get-StateCards
    $spend = Get-TodaySpend
    $ctxPct = -1
    $ctxSession = "none"
    if ($cards.Count -gt 0) {
        $ctxPct = Get-ContextPct -TranscriptPath $cards[0].Transcript
        $ctxSession = $cards[0].Title
    }

    Write-Output "mission-control -RenderOnce"
    Write-Output ("cards: {0}" -f $cards.Count)
    foreach ($c in $cards) {
        $age = Get-RelativeAge -UpdatedAt $c.UpdatedAt
        $color = Get-StateColor -State $c.State -UpdatedAt $c.UpdatedAt
        Write-Output ("  [{0}] title={1}  state={2}  color={3}  age={4}  summary={5}" -f ($cards.IndexOf($c) + 1), $c.Title, $c.State, $color, $age, $c.Summary)
    }
    if ($ctxPct -ge 0) {
        Write-Output ("ctx: {0}% (session: {1})" -f $ctxPct, $ctxSession)
    } else {
        Write-Output "ctx: n/a"
    }
    Write-Output ("today-spend: ~`${0:N2}" -f $spend)
    exit 0
}

# ---- WPF window ----
$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="mission control"
    Width="380"
    MinHeight="60"
    MaxHeight="600"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    Topmost="True"
    ShowInTaskbar="False"
    ResizeMode="NoResize"
    SizeToContent="Height">
  <Border Background="#1e1e1e" CornerRadius="6">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <!-- title bar -->
      <Border Grid.Row="0" Background="#141414" CornerRadius="6,6,0,0" x:Name="TitleBar" Cursor="SizeAll">
        <Grid Margin="10,6,8,6">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="mission control" Foreground="#9a9a9a"
                     FontFamily="Segoe UI" FontSize="11" VerticalAlignment="Center"/>
          <Button Grid.Column="1" x:Name="PinBtn" Content="pin" Foreground="#9a9a9a"
                  Background="Transparent" BorderThickness="0" FontSize="10"
                  FontFamily="Segoe UI" Padding="4,2" Cursor="Hand" Margin="0,0,4,0"/>
          <Button Grid.Column="2" x:Name="CloseBtn" Content="x" Foreground="#9a9a9a"
                  Background="Transparent" BorderThickness="0" FontSize="11"
                  FontFamily="Segoe UI" Padding="4,2" Cursor="Hand"/>
        </Grid>
      </Border>

      <!-- header strip -->
      <Border Grid.Row="1" Background="#1a1a1a" Margin="0,0,0,0" Padding="10,6">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" x:Name="CtxLabel" Text="ctx: --"
                     Foreground="#9a9a9a" FontFamily="Segoe UI" FontSize="11" VerticalAlignment="Center"/>
          <TextBlock Grid.Column="1" x:Name="SpendLabel" Text="today --"
                     Foreground="#9a9a9a" FontFamily="Segoe UI" FontSize="11" VerticalAlignment="Center"/>
        </Grid>
      </Border>

      <!-- scrollable card area -->
      <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled" MaxHeight="500">
        <StackPanel x:Name="CardPanel" Margin="6,4,6,6"/>
      </ScrollViewer>
    </Grid>
  </Border>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$titleBar  = $window.FindName("TitleBar")
$closeBtn  = $window.FindName("CloseBtn")
$pinBtn    = $window.FindName("PinBtn")
$ctxLabel  = $window.FindName("CtxLabel")
$spendLabel = $window.FindName("SpendLabel")
$cardPanel  = $window.FindName("CardPanel")

# ---- drag ----
$titleBar.Add_MouseLeftButtonDown({ $window.DragMove() })

# ---- close ----
$closeBtn.Add_Click({ $window.Close() })

# ---- pin toggle ----
$pinBtn.Add_Click({
    if ($window.Topmost) {
        $window.Topmost = $false
        $pinBtn.Foreground = [System.Windows.Media.Brushes]::DimGray
    } else {
        $window.Topmost = $true
        $pinBtn.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x9a, 0x9a, 0x9a))
    }
})

# ---- position memory ----
function Restore-Position {
    if (-not (Test-Path -LiteralPath $PosFile)) { return }
    try {
        $raw = Get-Content -LiteralPath $PosFile -Raw -Encoding UTF8 -ErrorAction Stop
        $parts = $raw.Trim().Split(" ")
        if ($parts.Count -ge 2) {
            $x = [double]$parts[0]
            $y = [double]$parts[1]
            $window.Left = $x
            $window.Top  = $y
        }
    } catch {}
}

function Save-Position {
    try {
        ("{0} {1}" -f $window.Left, $window.Top) | Set-Content -LiteralPath $PosFile -Encoding UTF8 -ErrorAction Stop
    } catch {}
}

$window.Add_LocationChanged({ Save-Position })

# ---- color helpers ----
function ConvertHex-ToBrush {
    param([string]$Hex)
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    return [System.Windows.Media.SolidColorBrush]::new($c)
}

$BrushBg      = ConvertHex-ToBrush "#2a2a2a"
$BrushText    = ConvertHex-ToBrush "#e6e6e6"
$BrushSubtext = ConvertHex-ToBrush "#9a9a9a"
$BrushWorking = ConvertHex-ToBrush "#2ecc71"
$BrushIdle    = ConvertHex-ToBrush "#e74c3c"
$BrushStale   = ConvertHex-ToBrush "#9a9a9a"
$BrushGreen   = ConvertHex-ToBrush "#2ecc71"
$BrushAmber   = ConvertHex-ToBrush "#f39c12"
$BrushRed     = ConvertHex-ToBrush "#e74c3c"
$BrushSubtextPlain = ConvertHex-ToBrush "#9a9a9a"

function Get-DotBrush {
    param([string]$State, [datetime]$UpdatedAt)
    $ageMins = ((Get-Date).ToUniversalTime() - $UpdatedAt).TotalMinutes
    if ($ageMins -gt 10) { return $BrushStale }
    if ($State -eq "working") { return $BrushWorking }
    return $BrushIdle
}

# ---- spend cache ----
$script:SpendCache      = 0.0
$script:SpendCacheAt    = [datetime]::MinValue

function Get-CachedSpend {
    $now = Get-Date
    if (($now - $script:SpendCacheAt).TotalSeconds -gt 30) {
        $script:SpendCache   = Get-TodaySpend
        $script:SpendCacheAt = $now
    }
    return $script:SpendCache
}

# ---- build a single card element ----
function New-CardElement {
    param([pscustomobject]$Card)

    $border = [System.Windows.Controls.Border]::new()
    $border.Background    = $BrushBg
    $border.CornerRadius  = [System.Windows.CornerRadius]::new(4)
    $border.Margin        = [System.Windows.Thickness]::new(0, 0, 0, 4)
    $border.Padding       = [System.Windows.Thickness]::new(10, 7, 10, 7)

    $grid = [System.Windows.Controls.Grid]::new()
    $col0 = [System.Windows.Controls.ColumnDefinition]::new()
    $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
    $col1 = [System.Windows.Controls.ColumnDefinition]::new()
    $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($col0)
    $grid.ColumnDefinitions.Add($col1)

    # colored dot
    $dot = [System.Windows.Controls.Border]::new()
    $dot.Width      = 8
    $dot.Height     = 8
    $dot.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $dot.Background = Get-DotBrush -State $Card.State -UpdatedAt $Card.UpdatedAt
    $dot.Margin     = [System.Windows.Thickness]::new(0, 2, 8, 0)
    $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    [System.Windows.Controls.Grid]::SetColumn($dot, 0)

    # text stack
    $stack = [System.Windows.Controls.StackPanel]::new()
    [System.Windows.Controls.Grid]::SetColumn($stack, 1)

    # title row
    $titleRow = [System.Windows.Controls.Grid]::new()
    $tc0 = [System.Windows.Controls.ColumnDefinition]::new()
    $tc0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $tc1 = [System.Windows.Controls.ColumnDefinition]::new()
    $tc1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
    $titleRow.ColumnDefinitions.Add($tc0)
    $titleRow.ColumnDefinitions.Add($tc1)

    $titleTb = [System.Windows.Controls.TextBlock]::new()
    $titleTb.Text       = $Card.Title
    $titleTb.Foreground = $BrushText
    $titleTb.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    $titleTb.FontSize   = 12
    $titleTb.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    [System.Windows.Controls.Grid]::SetColumn($titleTb, 0)

    $age = Get-RelativeAge -UpdatedAt $Card.UpdatedAt
    $ageTb = [System.Windows.Controls.TextBlock]::new()
    $ageTb.Text       = $age
    $ageTb.Foreground = $BrushSubtextPlain
    $ageTb.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    $ageTb.FontSize   = 10
    $ageTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
    $ageTb.Margin     = [System.Windows.Thickness]::new(6, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($ageTb, 1)

    $titleRow.Children.Add($titleTb) | Out-Null
    $titleRow.Children.Add($ageTb)   | Out-Null

    $stack.Children.Add($titleRow) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($Card.Summary)) {
        $summaryTb = [System.Windows.Controls.TextBlock]::new()
        $summaryTb.Text         = $Card.Summary
        $summaryTb.Foreground   = $BrushSubtextPlain
        $summaryTb.FontFamily   = [System.Windows.Media.FontFamily]::new("Segoe UI")
        $summaryTb.FontSize     = 10
        $summaryTb.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $summaryTb.Margin       = [System.Windows.Thickness]::new(0, 3, 0, 0)
        $stack.Children.Add($summaryTb) | Out-Null
    }

    $grid.Children.Add($dot)   | Out-Null
    $grid.Children.Add($stack) | Out-Null
    $border.Child = $grid

    return $border
}

# ---- tick ----
function Update-Dashboard {
    try {
        $cards = Get-StateCards

        # header: ctx%
        $ctxPct = -1
        if ($cards.Count -gt 0) {
            $ctxPct = Get-ContextPct -TranscriptPath $cards[0].Transcript
        }
        if ($ctxPct -ge 0) {
            $ctxLabel.Text = "ctx: ${ctxPct}%"
            if ($ctxPct -ge 80) {
                $ctxLabel.Foreground = $BrushRed
            } elseif ($ctxPct -ge 60) {
                $ctxLabel.Foreground = $BrushAmber
            } else {
                $ctxLabel.Foreground = $BrushGreen
            }
        } else {
            $ctxLabel.Text       = "ctx: --"
            $ctxLabel.Foreground = $BrushSubtextPlain
        }

        # header: spend
        $spend = Get-CachedSpend
        $spendLabel.Text = ("today ~`${0:N2}" -f $spend)

        # rebuild cards
        $cardPanel.Children.Clear()
        if ($cards.Count -eq 0) {
            $nocard = [System.Windows.Controls.TextBlock]::new()
            $nocard.Text       = "no active sessions"
            $nocard.Foreground = $BrushSubtextPlain
            $nocard.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
            $nocard.FontSize   = 11
            $nocard.Margin     = [System.Windows.Thickness]::new(4, 8, 4, 8)
            $nocard.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $cardPanel.Children.Add($nocard) | Out-Null
        } else {
            foreach ($card in $cards) {
                $el = New-CardElement -Card $card
                $cardPanel.Children.Add($el) | Out-Null
            }
        }
    } catch {
        # never crash the window
    }
}

# ---- startup position, then show ----
$window.Add_SourceInitialized({
    Restore-Position
    Update-Dashboard
})

# ---- DispatcherTimer at 2.5s ----
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [System.TimeSpan]::FromMilliseconds(2500)
$timer.Add_Tick({ Update-Dashboard })
$timer.Start()

[void]$window.ShowDialog()
