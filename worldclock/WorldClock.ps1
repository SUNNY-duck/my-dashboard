# World Clock widget : Los Angeles (LA) / Tokyo
# - Always on top, top-right corner, semi-transparent
# - Drag with left mouse button, right-click for menu (settings, close)
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
if (-not (Test-Path -LiteralPath $IconPath)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $IconUrl -OutFile $IconPath -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    } catch { }
}

# Create the "세계시계" desktop shortcut once (not recreated if the user deletes it)
if (-not $script:settings.PSObject.Properties['ShortcutCreated']) {
    try {
        $lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) '세계시계.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($lnkPath)
        if (Test-Path -LiteralPath $StableLauncher) {
            $lnk.TargetPath  = $StableLauncher
            $lnk.WindowStyle = 7   # minimized
        } else {
            $lnk.TargetPath  = 'powershell.exe'
            $lnk.Arguments   = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $PSCommandPath + '"'
            $lnk.WindowStyle = 7
        }
        $lnk.WorkingDirectory = $AppDir
        if (Test-Path -LiteralPath $IconPath) { $lnk.IconLocation = "$IconPath,0" }
        $lnk.Description = 'World Clock (LA / Tokyo)'
        $lnk.Save()
        $script:settings | Add-Member -NotePropertyName ShortcutCreated -NotePropertyValue $true -Force
        Save-WcSettings $script:settings
    } catch { }
}

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
  <Border CornerRadius="12" Background="#FF121218" Padding="18,10,18,10"
          BorderBrush="#FF2A2A35" BorderThickness="1">
    <StackPanel x:Name="Rows"/>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$window.Opacity = $Opacity
Set-WcWindowIcon $window
$rows = $window.FindName('Rows')

$bc       = New-Object System.Windows.Media.BrushConverter
$culture  = [Globalization.CultureInfo]::InvariantCulture
$timeFont = New-Object System.Windows.Media.FontFamily 'Segoe UI Black, Arial Black, Segoe UI'

# Rows share the label column width so the clocks line up with a small gap
[System.Windows.Controls.Grid]::SetIsSharedSizeScope($rows, $true)

$items = foreach ($z in $zones) {
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById($z.Id)

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

    $city = New-Object System.Windows.Controls.TextBlock
    $city.FontFamily = 'Segoe UI'
    $city.FontSize   = 17
    $city.FontWeight = [System.Windows.FontWeights]::Bold
    $city.Foreground = $bc.ConvertFromString('#FFE6E6E6')

    $date = New-Object System.Windows.Controls.TextBlock
    $date.FontFamily = 'Consolas'
    $date.FontSize   = 12
    $date.Foreground = $bc.ConvertFromString('#FF9AA0A6')

    [void]$left.Children.Add($city)
    [void]$left.Children.Add($date)
    [System.Windows.Controls.Grid]::SetColumn($left, 0)

    $time = New-Object System.Windows.Controls.TextBlock
    $time.FontFamily = $timeFont
    $time.FontWeight = [System.Windows.FontWeights]::Black
    $time.FontSize   = 36
    $time.Foreground = $bc.ConvertFromString('#FF6CFFA8')
    $time.VerticalAlignment = 'Center'
    $time.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
    $time.SetValue([System.Windows.Documents.Typography]::NumeralAlignmentProperty, [System.Windows.FontNumeralAlignment]::Tabular)
    [System.Windows.Controls.Grid]::SetColumn($time, 1)

    [void]$grid.Children.Add($left)
    [void]$grid.Children.Add($time)
    [void]$rows.Children.Add($grid)

    [pscustomobject]@{ Label = $z.Label; Std = $z.Std; Dst = $z.Dst; Tz = $tz; City = $city; Date = $date; Time = $time }
}

$update = {
    $utc = [DateTime]::UtcNow
    foreach ($i in $items) {
        $t   = [TimeZoneInfo]::ConvertTimeFromUtc($utc, $i.Tz)
        $abbr = if ($i.Tz.IsDaylightSavingTime($t)) { $i.Dst } else { $i.Std }
        $i.City.Text = '{0}  {1}' -f $i.Label, $abbr
        $i.Date.Text = $t.ToString('yyyy-MM-dd ddd', $culture).ToUpper()
        $i.Time.Text = $t.ToString('HH:mm', $culture)
    }
}
& $update

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1000)
$timer.Add_Tick($update)
$timer.Start()

# Place at top-right of the work area
$placeTopRight = {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $wa.Right - $window.ActualWidth - $Margin
    $window.Top  = $wa.Top + $Margin
}
$window.Add_ContentRendered($placeTopRight)

# Drag to move
$window.Add_MouseLeftButtonDown({ $window.DragMove() })

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

    $script:cbAuto = New-Object System.Windows.Controls.CheckBox
    $script:cbAuto.Content  = 'PC를 켤 때 자동 실행'
    $script:cbAuto.FontSize = 14
    $script:cbAuto.IsChecked = [bool]$script:settings.AutoStart

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
        Save-WcSettings $script:settings
        try { Set-WcAutoStart ([bool]$script:settings.AutoStart) } catch { }
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
    [void]$panel.Children.Add($buttons)
    $script:setWin.Content = $panel
    [void]$script:setWin.ShowDialog()
}

# Right-click menu
$menu = New-Object System.Windows.Controls.ContextMenu
$settingsItem = New-Object System.Windows.Controls.MenuItem
$settingsItem.Header = '설정'
$settingsItem.Add_Click($openSettings)
$reset = New-Object System.Windows.Controls.MenuItem
$reset.Header = '오른쪽 위로 이동'
$reset.Add_Click($placeTopRight)
$close = New-Object System.Windows.Controls.MenuItem
$close.Header = '닫기'
$close.Add_Click({ $timer.Stop(); $window.Close() })
[void]$menu.Items.Add($settingsItem)
[void]$menu.Items.Add($reset)
[void]$menu.Items.Add($close)
$window.ContextMenu = $menu

[void]$window.ShowDialog()
