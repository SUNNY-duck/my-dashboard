# World Clock widget : Los Angeles (LA) / Tokyo
# - Always on top, top-right corner, semi-transparent
# - Drag with left mouse button, right-click > Close to exit

# ===== Settings =====
$Opacity = 0.7     # 1.0 = solid, 0.7 = 70% opacity
$Margin  = 12      # distance from screen edge (px)
# ====================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

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

# Right-click menu
$menu = New-Object System.Windows.Controls.ContextMenu
$reset = New-Object System.Windows.Controls.MenuItem
$reset.Header = 'Move to top-right'
$reset.Add_Click($placeTopRight)
$close = New-Object System.Windows.Controls.MenuItem
$close.Header = 'Close'
$close.Add_Click({ $timer.Stop(); $window.Close() })
[void]$menu.Items.Add($reset)
[void]$menu.Items.Add($close)
$window.ContextMenu = $menu

[void]$window.ShowDialog()
