# World Clock widget : Los Angeles (LA) / Tokyo
# - Always on top, top-right corner, semi-transparent
# - Drag with left mouse button, Ctrl + mouse wheel to resize (size and position are remembered)
# - Right-click for menu (settings, size, close); settings can switch between stacked and taskbar layouts
# - First run asks whether to start with Windows; change later in right-click > settings

# ===== Settings =====
$Opacity = 0.7     # 1.0 = solid, 0.7 = 70% opacity
$Margin  = 12      # distance from screen edge (px)
# ====================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ===== Start with Windows (asked once, saved per PC) =====
$AppDir         = Join-Path $env:LOCALAPPDATA 'WorldClock'
$SettingsPath   = Join-Path $AppDir 'settings.json'
$StableLauncher = Join-Path $AppDir 'WorldClock.bat'
$RunKey         = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName        = 'WorldClock'

function Save-WcSettings($s) {
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    $s | ConvertTo-Json | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function Set-WcAutoStart([bool]$on) {
    if ($on) {
        if (Test-Path -LiteralPath $StableLauncher) {
            # Start through the launcher so the latest version is downloaded at boot
            $cmd = 'cmd.exe /c start "" /min "' + $StableLauncher + '"'
        } else {
            $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $PSCommandPath + '"'
        }
        New-ItemProperty -Path $RunKey -Name $RunName -Value $cmd -PropertyType String -Force | Out-Null
    } else {
        Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue
    }
}

# Keep a launcher copy in the app folder (used by the desktop shortcut and start with Windows)
$LauncherText = @'
@echo off
rem ============================================================
rem  World Clock launcher (the only file teammates need)
rem  - Downloads the latest WorldClock.ps1 from WC_SOURCE on every start
rem  - Offline or download failed: runs the last downloaded copy
rem  - Double-click again: closes the running widget and reopens the latest
rem ============================================================

rem ---- Address of the latest WorldClock.ps1 (web URL or shared folder path) ----
set "WC_LAUNCHER=%~f0"
set "WC_SOURCE=https://raw.githubusercontent.com/SUNNY-duck/my-dashboard/main/worldclock/WorldClock.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& ([scriptblock]::Create(((Get-Content -LiteralPath '%~f0' -Raw) -split ('#PS'+'-START#'),2)[1]))"
exit /b

#PS-START#
$dir   = Join-Path $env:LOCALAPPDATA 'WorldClock'
$local = Join-Path $dir 'WorldClock.ps1'
$tmp   = "$local.download"
$src   = $env:WC_SOURCE
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# 1. Get the latest version
try {
    if ($src -match '^https?://') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $src -OutFile $tmp -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    } else {
        Copy-Item -LiteralPath $src -Destination $tmp -Force -ErrorAction Stop
    }
    # Replace only when the download is really the widget (not an error page)
    $head = Get-Content -LiteralPath $tmp -TotalCount 1
    if ($head -like '# World Clock widget*') {
        Move-Item -LiteralPath $tmp -Destination $local -Force
    } else {
        Remove-Item -LiteralPath $tmp -Force
    }
} catch {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $local)) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show("Could not download World Clock.`nCheck the network and try again.", 'World Clock')
    exit
}

# 2. Keep a copy of this launcher for "start with Windows"
$stable = Join-Path $dir 'WorldClock.bat'
$me = $env:WC_LAUNCHER
if ($me -and (Test-Path -LiteralPath $me) -and ($me -ne $stable)) {
    Copy-Item -LiteralPath $me -Destination $stable -Force -ErrorAction SilentlyContinue
}

# 3. Close a widget that is already running
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($local) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 4. Start the widget with no console window
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$local`""
)
'@
try {
    $want = ($LauncherText -replace "`r?`n", "`r`n") + "`r`n"
    $have = if (Test-Path -LiteralPath $StableLauncher) { [IO.File]::ReadAllText($StableLauncher) } else { '' }
    if ($have -ne $want) {
        New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
        [IO.File]::WriteAllText($StableLauncher, $want, [Text.Encoding]::ASCII)
    }
} catch { }

$script:settings = $null
if (Test-Path -LiteralPath $SettingsPath) {
    try { $script:settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json } catch { }
}
if (-not $script:settings) {
    $answer = [System.Windows.MessageBox]::Show(
        "PC를 켤 때 세계시계를 자동으로 실행할까요?`n`n나중에 시계를 오른쪽 클릭해서 [설정]에서 바꿀 수 있습니다.",
        '세계시계', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    $script:settings = [pscustomobject]@{ AutoStart = ($answer -eq [System.Windows.MessageBoxResult]::Yes) }
    Save-WcSettings $script:settings
}
try { Set-WcAutoStart ([bool]$script:settings.AutoStart) } catch { }
# =========================================================

# ===== Icon and desktop shortcut =====
$IconUrl  = 'https://raw.githubusercontent.com/SUNNY-duck/my-dashboard/main/worldclock/WorldClock.ico'
$IconPath = Join-Path $AppDir 'WorldClock.ico'
# Refresh the icon on every start so icon changes reach every PC
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $iconTmp = "$IconPath.download"
    Invoke-WebRequest -Uri $IconUrl -OutFile $iconTmp -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    if ((Get-Item -LiteralPath $iconTmp).Length -gt 0) { Move-Item -LiteralPath $iconTmp -Destination $IconPath -Force }
} catch {
    Remove-Item -LiteralPath "$IconPath.download" -Force -ErrorAction SilentlyContinue
}

$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) '세계시계.lnk'

function New-WcShortcut {
    # Copy the icon under a new file name each time so Windows does not show a cached old icon
    $iconForLnk = $null
    if (Test-Path -LiteralPath $IconPath) {
        Get-ChildItem -LiteralPath $AppDir -Filter 'WorldClock_*.ico' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        $iconForLnk = Join-Path $AppDir ('WorldClock_' + (Get-Date -Format 'yyyyMMddHHmmss') + '.ico')
        Copy-Item -LiteralPath $IconPath -Destination $iconForLnk -Force
    }
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($ShortcutPath)
    if (Test-Path -LiteralPath $StableLauncher) {
        $lnk.TargetPath = $StableLauncher
        $lnk.Arguments  = ''
    } else {
        $lnk.TargetPath = 'powershell.exe'
        $lnk.Arguments  = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $PSCommandPath + '"'
    }
    $lnk.WindowStyle      = 7   # minimized
    $lnk.WorkingDirectory = $AppDir
    if ($iconForLnk) { $lnk.IconLocation = "$iconForLnk,0" }
    $lnk.Description = 'World Clock (LA / Tokyo)'
    $lnk.Save()

    $script:settings | Add-Member -NotePropertyName ShortcutCreated -NotePropertyValue $true -Force
    $script:settings | Add-Member -NotePropertyName IconHash -NotePropertyValue $script:iconHash -Force
    Save-WcSettings $script:settings
    try { Start-Process ie4uinit.exe -ArgumentList '-show' -WindowStyle Hidden } catch { }
}

$script:iconHash = ''
if (Test-Path -LiteralPath $IconPath) {
    try { $script:iconHash = (Get-FileHash -LiteralPath $IconPath -Algorithm SHA256).Hash } catch { }
}

try {
    if (-not $script:settings.PSObject.Properties['ShortcutCreated']) {
        # First run: create the shortcut once (not recreated automatically if the user deletes it)
        New-WcShortcut
    } elseif (Test-Path -LiteralPath $ShortcutPath) {
        $target = (New-Object -ComObject WScript.Shell).CreateShortcut($ShortcutPath).TargetPath
        $iconChanged = $script:iconHash -and ($script:settings.PSObject.Properties['IconHash'] -eq $null -or $script:settings.IconHash -ne $script:iconHash)
        $wrongTarget = (Test-Path -LiteralPath $StableLauncher) -and ($target -ne $StableLauncher)
        # Icon changed on GitHub, or the shortcut skips the launcher (no auto update): rebuild it
        if ($iconChanged -or $wrongTarget) { New-WcShortcut }
    }
} catch { }

function Set-WcWindowIcon($w) {
    if (Test-Path -LiteralPath $IconPath) {
        try { $w.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$IconPath) } catch { }
    }
}
# =====================================

$zones = @(
    @{ Label = 'LA';    Id = 'Pacific Standard Time'; Std = 'PST'; Dst = 'PDT' }  # Amazon US report time, DST applied automatically
    @{ Label = 'TOKYO'; Id = 'Tokyo Standard Time';   Std = 'JST'; Dst = 'JST' }
)

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        SizeToContent="WidthAndHeight" WindowStartupLocation="Manual"
        Left="-3000" Top="0">
  <Border x:Name="Root" BorderBrush="#FF2A2A35" BorderThickness="1"/>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
Set-WcWindowIcon $window
$root = $window.FindName('Root')

$bc       = New-Object System.Windows.Media.BrushConverter
$culture  = [Globalization.CultureInfo]::InvariantCulture
$timeFont = New-Object System.Windows.Media.FontFamily 'Segoe UI Black, Arial Black, Segoe UI'
$DateColor = '#FFC9CED4'   # date text (brighter)

# ===== Display mode: Classic (stacked), BarA (taskbar, two-line labels), BarB (taskbar, one line) =====
$Modes = @('Classic', 'BarA', 'BarB')
$script:mode = 'Classic'
if ($script:settings.PSObject.Properties['Mode'] -and ($Modes -contains $script:settings.Mode)) { $script:mode = $script:settings.Mode }

# Size and position are remembered separately for each mode
function Get-WcSetting([string]$name) {
    $p = $script:settings.PSObject.Properties[$name]
    if ($p) { return $p.Value } else { return $null }
}
function Set-WcSetting([string]$name, $value) {
    $script:settings | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}
# Older versions saved Scale/Left/Top for the stacked clock only
if ((Get-WcSetting 'Scale') -ne $null -and (Get-WcSetting 'Scale_Classic') -eq $null) { Set-WcSetting 'Scale_Classic' (Get-WcSetting 'Scale') }
if ((Get-WcSetting 'Left')  -ne $null -and (Get-WcSetting 'Left_Classic')  -eq $null) { Set-WcSetting 'Left_Classic'  (Get-WcSetting 'Left') }
if ((Get-WcSetting 'Top')   -ne $null -and (Get-WcSetting 'Top_Classic')   -eq $null) { Set-WcSetting 'Top_Classic'   (Get-WcSetting 'Top') }

$script:scaleTf = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
$root.LayoutTransform = $script:scaleTf
$script:scale = 1.0
$script:items = @()

function New-WcText([string]$font, [double]$size, $weight, [string]$color) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.FontFamily = $font
    $tb.FontSize = $size
    $tb.FontWeight = $weight
    $tb.Foreground = $bc.ConvertFromString($color)
    $tb.VerticalAlignment = 'Center'
    return $tb
}
function New-WcTime([double]$size) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.FontFamily = $timeFont
    $tb.FontWeight = [System.Windows.FontWeights]::Black
    $tb.FontSize = $size
    $tb.Foreground = $bc.ConvertFromString('#FF6CFFA8')
    $tb.VerticalAlignment = 'Center'
    $tb.SetValue([System.Windows.Documents.Typography]::NumeralAlignmentProperty, [System.Windows.FontNumeralAlignment]::Tabular)
    return $tb
}
function New-WcSeparator([double]$height) {
    $sep = New-Object System.Windows.Shapes.Rectangle
    $sep.Width = 1
    $sep.Height = $height
    $sep.Fill = $bc.ConvertFromString('#FF3A3A46')
    $sep.Margin = [System.Windows.Thickness]::new(12, 0, 12, 0)
    $sep.VerticalAlignment = 'Center'
    return $sep
}

function Build-WcView {
    $bold = [System.Windows.FontWeights]::Bold
    $normalW = [System.Windows.FontWeights]::Normal
    $list = New-Object System.Collections.ArrayList

    switch ($script:mode) {
        'Classic' {
            $window.Opacity = $Opacity
            $root.CornerRadius = [System.Windows.CornerRadius]::new(12)
            $root.Background = $bc.ConvertFromString('#FF121218')
            $root.Padding = [System.Windows.Thickness]::new(18, 10, 18, 10)
            $panel = New-Object System.Windows.Controls.StackPanel
            [System.Windows.Controls.Grid]::SetIsSharedSizeScope($panel, $true)
            foreach ($z in $zones) {
                $grid = New-Object System.Windows.Controls.Grid
                $grid.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
                $c0 = New-Object System.Windows.Controls.ColumnDefinition
                $c0.Width = [System.Windows.GridLength]::Auto
                $c0.SharedSizeGroup = 'Label'
                $c1 = New-Object System.Windows.Controls.ColumnDefinition
                $c1.Width = [System.Windows.GridLength]::Auto
                [void]$grid.ColumnDefinitions.Add($c0)
                [void]$grid.ColumnDefinitions.Add($c1)
                $left = New-Object System.Windows.Controls.StackPanel
                $left.VerticalAlignment = 'Center'
                $city = New-WcText 'Segoe UI' 17 $bold '#FFE6E6E6'
                $date = New-WcText 'Consolas' 12 $normalW $DateColor
                [void]$left.Children.Add($city); [void]$left.Children.Add($date)
                $time = New-WcTime 36
                $time.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
                [System.Windows.Controls.Grid]::SetColumn($time, 1)
                [void]$grid.Children.Add($left); [void]$grid.Children.Add($time)
                [void]$panel.Children.Add($grid)
                [void]$list.Add([pscustomobject]@{ Zone = $z; Tz = [TimeZoneInfo]::FindSystemTimeZoneById($z.Id); City = $city; Date = $date; Time = $time; CityFmt = 'full'; DateFmt = 'yyyy-MM-dd ddd' })
            }
            $root.Child = $panel
        }
        'BarA' {
            $window.Opacity = 1.0
            $root.CornerRadius = [System.Windows.CornerRadius]::new(8)
            $root.Background = $bc.ConvertFromString('#E6121218')
            $root.Padding = [System.Windows.Thickness]::new(12, 3, 12, 3)
            $panel = New-Object System.Windows.Controls.StackPanel
            $panel.Orientation = 'Horizontal'
            $first = $true
            foreach ($z in $zones) {
                if (-not $first) { [void]$panel.Children.Add((New-WcSeparator 22)) }
                $first = $false
                $left = New-Object System.Windows.Controls.StackPanel
                $left.VerticalAlignment = 'Center'
                $city = New-WcText 'Segoe UI' 11 $bold '#FFE6E6E6'
                $date = New-WcText 'Consolas' 10 $normalW $DateColor
                [void]$left.Children.Add($city); [void]$left.Children.Add($date)
                $time = New-WcTime 22
                $time.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                [void]$panel.Children.Add($left); [void]$panel.Children.Add($time)
                [void]$list.Add([pscustomobject]@{ Zone = $z; Tz = [TimeZoneInfo]::FindSystemTimeZoneById($z.Id); City = $city; Date = $date; Time = $time; CityFmt = 'short'; DateFmt = 'MM-dd ddd' })
            }
            $root.Child = $panel
        }
        'BarB' {
            $window.Opacity = 1.0
            $root.CornerRadius = [System.Windows.CornerRadius]::new(15)
            $root.Background = $bc.ConvertFromString('#E6121218')
            $root.Padding = [System.Windows.Thickness]::new(14, 2, 14, 2)
            $panel = New-Object System.Windows.Controls.StackPanel
            $panel.Orientation = 'Horizontal'
            $first = $true
            foreach ($z in $zones) {
                if (-not $first) { [void]$panel.Children.Add((New-WcSeparator 16)) }
                $first = $false
                $city = New-WcText 'Segoe UI' 11 $bold '#FFCFD3D8'
                $time = New-WcTime 17
                $time.Margin = [System.Windows.Thickness]::new(8, 0, 8, 0)
                $date = New-WcText 'Consolas' 10 $normalW $DateColor
                [void]$panel.Children.Add($city); [void]$panel.Children.Add($time); [void]$panel.Children.Add($date)
                [void]$list.Add([pscustomobject]@{ Zone = $z; Tz = [TimeZoneInfo]::FindSystemTimeZoneById($z.Id); City = $city; Date = $date; Time = $time; CityFmt = 'label'; DateFmt = 'MM-dd ddd' })
            }
            $root.Child = $panel
        }
    }
    $script:items = $list

    $s = Get-WcSetting ("Scale_" + $script:mode)
    $script:scale = 1.0
    if ($s -ne $null) { try { $script:scale = [Math]::Min(2.0, [Math]::Max(0.6, [double]$s)) } catch { } }
    $script:scaleTf.ScaleX = $script:scale
    $script:scaleTf.ScaleY = $script:scale
    & $update
}

$update = {
    $utc = [DateTime]::UtcNow
    foreach ($i in $script:items) {
        $t    = [TimeZoneInfo]::ConvertTimeFromUtc($utc, $i.Tz)
        $abbr = if ($i.Tz.IsDaylightSavingTime($t)) { $i.Zone.Dst } else { $i.Zone.Std }
        switch ($i.CityFmt) {
            'full'  { $i.City.Text = '{0}  {1}' -f $i.Zone.Label, $abbr }
            'short' { $i.City.Text = '{0} {1}' -f $i.Zone.Label, $abbr }
            default { $i.City.Text = $i.Zone.Label }
        }
        $i.Date.Text = $t.ToString($i.DateFmt, $culture).ToUpper()
        $i.Time.Text = $t.ToString('HH:mm', $culture)
    }
}

# Keep the clock above the taskbar in taskbar modes
try {
    Add-Type -Namespace WcNative -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
'@ -ErrorAction Stop
    $script:canPin = $true
} catch { $script:canPin = $false }
function Set-WcOnTop {
    if (-not $script:canPin) { return }
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        if ($h -ne [IntPtr]::Zero) { [void][WcNative.Win]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0013) }  # TOPMOST, NOSIZE|NOMOVE|NOACTIVATE
    } catch { }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1000)
$timer.Add_Tick({
    & $update
    if ($script:mode -ne 'Classic') { Set-WcOnTop }
})

# Save size and position for the current mode
function Save-WcLayout {
    Set-WcSetting 'Mode' $script:mode
    Set-WcSetting ("Scale_" + $script:mode) ([Math]::Round($script:scale, 2))
    Set-WcSetting ("Left_"  + $script:mode) ([Math]::Round($window.Left))
    Set-WcSetting ("Top_"   + $script:mode) ([Math]::Round($window.Top))
    try { Save-WcSettings $script:settings } catch { }
}

# Default position: Classic = top-right, taskbar modes = on the taskbar left of the system clock
function Set-WcDefaultPosition {
    $window.UpdateLayout()
    $wa = [System.Windows.SystemParameters]::WorkArea
    if ($script:mode -eq 'Classic') {
        $window.Left = $wa.Right - $window.ActualWidth - $Margin
        $window.Top  = $wa.Top + $Margin
    } else {
        $screenH = [System.Windows.SystemParameters]::PrimaryScreenHeight
        $screenW = [System.Windows.SystemParameters]::PrimaryScreenWidth
        $band = $screenH - $wa.Bottom
        if ($band -ge 24) {
            $window.Top = $wa.Bottom + ($band - $window.ActualHeight) / 2
        } else {
            $window.Top = $wa.Bottom - $window.ActualHeight - 8   # taskbar hidden or not at the bottom
        }
        $window.Left = $screenW - $window.ActualWidth - 230
    }
    Save-WcLayout
}

# Restore the saved position for this mode if it is still on a screen
function Restore-WcPosition {
    $l = Get-WcSetting ("Left_" + $script:mode)
    $t = Get-WcSetting ("Top_"  + $script:mode)
    if ($l -ne $null -and $t -ne $null) {
        $l = [double]$l; $t = [double]$t
        $vl = [System.Windows.SystemParameters]::VirtualScreenLeft
        $vt = [System.Windows.SystemParameters]::VirtualScreenTop
        $vr = $vl + [System.Windows.SystemParameters]::VirtualScreenWidth
        $vb = $vt + [System.Windows.SystemParameters]::VirtualScreenHeight
        if ($l -ge $vl -and $t -ge $vt -and ($l + 40) -le $vr -and ($t + 10) -le $vb) {
            $window.Left = $l; $window.Top = $t
            return
        }
    }
    Set-WcDefaultPosition
}

function Set-WcMode([string]$newMode) {
    if ($newMode -eq $script:mode) { return }
    Save-WcLayout
    $script:mode = $newMode
    Build-WcView
    Restore-WcPosition
    Save-WcLayout
}

Build-WcView
$timer.Start()
$window.Add_ContentRendered({ Restore-WcPosition; if ($script:mode -ne 'Classic') { Set-WcOnTop } })

# Change size, keeping the right edge in place
function Set-WcScale([double]$value) {
    $value = [Math]::Round([Math]::Min(2.0, [Math]::Max(0.6, $value)), 2)
    $right = $window.Left + $window.ActualWidth
    $script:scale = $value
    $script:scaleTf.ScaleX = $value
    $script:scaleTf.ScaleY = $value
    $window.UpdateLayout()
    $window.Left = $right - $window.ActualWidth
    Save-WcLayout
}

# Ctrl + mouse wheel on the clock changes the size
$window.Add_PreviewMouseWheel({
    param($sender, $e)
    if (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0) {
        if ($e.Delta -gt 0) { Set-WcScale ($script:scale + 0.1) } else { Set-WcScale ($script:scale - 0.1) }
        $e.Handled = $true
    }
})

# Drag to move
$window.Add_MouseLeftButtonDown({ $window.DragMove(); Save-WcLayout })

# Settings window
$openSettings = {
    $script:setWin = New-Object System.Windows.Window
    $script:setWin.Title = '세계시계 설정'
    $script:setWin.SizeToContent = 'WidthAndHeight'
    $script:setWin.ResizeMode = 'NoResize'
    $script:setWin.WindowStartupLocation = 'CenterScreen'
    $script:setWin.Topmost = $true
    Set-WcWindowIcon $script:setWin

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = [System.Windows.Thickness]::new(24, 20, 24, 18)

    $modeTitle = New-Object System.Windows.Controls.TextBlock
    $modeTitle.Text = '시계 모양'
    $modeTitle.FontSize = 14
    $modeTitle.FontWeight = [System.Windows.FontWeights]::Bold
    $modeTitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    [void]$panel.Children.Add($modeTitle)

    $script:modeRadios = @{}
    foreach ($opt in @(
        @{ Key = 'Classic'; Text = '1. 기본 (세로로 쌓은 큰 시계)' },
        @{ Key = 'BarA';    Text = '2. 작업 표시줄 A (도시, 날짜 두 줄)' },
        @{ Key = 'BarB';    Text = '3. 작업 표시줄 B (한 줄)' })) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Content = $opt.Text
        $rb.GroupName = 'WcMode'
        $rb.FontSize = 13
        $rb.Margin = [System.Windows.Thickness]::new(4, 2, 0, 2)
        $rb.IsChecked = ($script:mode -eq $opt.Key)
        $script:modeRadios[$opt.Key] = $rb
        [void]$panel.Children.Add($rb)
    }

    $line = New-Object System.Windows.Controls.Separator
    $line.Margin = [System.Windows.Thickness]::new(0, 12, 0, 12)
    [void]$panel.Children.Add($line)

    $script:cbAuto = New-Object System.Windows.Controls.CheckBox
    $script:cbAuto.Content  = 'PC를 켤 때 자동 실행'
    $script:cbAuto.FontSize = 14
    $script:cbAuto.IsChecked = [bool]$script:settings.AutoStart

    $remake = New-Object System.Windows.Controls.Button
    $remake.Content = '바탕화면 바로가기 다시 만들기'
    $remake.Margin  = [System.Windows.Thickness]::new(0, 14, 0, 0)
    $remake.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
    $remake.HorizontalAlignment = 'Left'
    $remake.Add_Click({
        try {
            New-WcShortcut
            [void][System.Windows.MessageBox]::Show($script:setWin, '바탕화면에 바로가기를 다시 만들었습니다.', '세계시계')
        } catch {
            [void][System.Windows.MessageBox]::Show($script:setWin, '바로가기를 만들지 못했습니다.', '세계시계')
        }
    })

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = [System.Windows.Thickness]::new(0, 18, 0, 0)

    $save = New-Object System.Windows.Controls.Button
    $save.Content = '저장'
    $save.Width = 72
    $save.IsDefault = $true
    $save.Add_Click({
        $script:settings.AutoStart = [bool]$script:cbAuto.IsChecked
        try { Set-WcAutoStart ([bool]$script:settings.AutoStart) } catch { }
        foreach ($k in $script:modeRadios.Keys) {
            if ($script:modeRadios[$k].IsChecked) { Set-WcMode $k }
        }
        Save-WcSettings $script:settings
        $script:setWin.Close()
    })

    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = '취소'
    $cancel.Width = 72
    $cancel.IsCancel = $true
    $cancel.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)

    [void]$buttons.Children.Add($save)
    [void]$buttons.Children.Add($cancel)
    [void]$panel.Children.Add($script:cbAuto)
    [void]$panel.Children.Add($remake)
    [void]$panel.Children.Add($buttons)
    $script:setWin.Content = $panel
    [void]$script:setWin.ShowDialog()
}

# Right-click menu
$menu = New-Object System.Windows.Controls.ContextMenu
$settingsItem = New-Object System.Windows.Controls.MenuItem
$settingsItem.Header = '설정'
$settingsItem.Add_Click($openSettings)
$sizeItem = New-Object System.Windows.Controls.MenuItem
$sizeItem.Header = '크기'
$bigger = New-Object System.Windows.Controls.MenuItem
$bigger.Header = '크게 (Ctrl + 휠 위로)'
$bigger.StaysOpenOnClick = $true
$bigger.Add_Click({ Set-WcScale ($script:scale + 0.1) })
$smaller = New-Object System.Windows.Controls.MenuItem
$smaller.Header = '작게 (Ctrl + 휠 아래로)'
$smaller.StaysOpenOnClick = $true
$smaller.Add_Click({ Set-WcScale ($script:scale - 0.1) })
$normal = New-Object System.Windows.Controls.MenuItem
$normal.Header = '원래 크기'
$normal.Add_Click({ Set-WcScale 1.0 })
[void]$sizeItem.Items.Add($bigger)
[void]$sizeItem.Items.Add($smaller)
[void]$sizeItem.Items.Add($normal)

$reset = New-Object System.Windows.Controls.MenuItem
$reset.Header = '기본 위치로 이동'
$reset.Add_Click({ Set-WcDefaultPosition })
$close = New-Object System.Windows.Controls.MenuItem
$close.Header = '닫기'
$close.Add_Click({ Save-WcLayout; $timer.Stop(); $window.Close() })
[void]$menu.Items.Add($settingsItem)
[void]$menu.Items.Add($sizeItem)
[void]$menu.Items.Add($reset)
[void]$menu.Items.Add($close)
$window.ContextMenu = $menu

[void]$window.ShowDialog()
