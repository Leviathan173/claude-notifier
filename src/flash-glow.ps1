<#
.SYNOPSIS
    Breathing side-glow flash effect — called by Show-Flash.
    Left+right 200px gradient, sine-wave pulse, ~5 seconds.
.PARAMETER Color
    Hex color for the glow (e.g. #00C853 = green, #FFD600 = yellow)
#>
param([string]$Color = '#00C853')

Add-Type -AssemblyName PresentationFramework

$W = [System.Windows.SystemParameters]::PrimaryScreenWidth
$H = [System.Windows.SystemParameters]::PrimaryScreenHeight
$Bar = 250
$Dur = 5000
$Cyc = 2
$start = [DateTime]::Now

$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
    Topmost='True' ShowActivated='False' ShowInTaskbar='False' WindowStyle='None'
    AllowsTransparency='True' Background='Transparent'
    ResizeMode='NoResize' SizeToContent='Manual'
    Left='0' Top='0' Width='$W' Height='$H'
    IsHitTestVisible='False' Focusable='False'>
    <Grid>
        <Border Width='$Bar' Height='$H' HorizontalAlignment='Left'
                VerticalAlignment='Stretch' Opacity='0' Name='L'>
            <Border.Background>
                <LinearGradientBrush StartPoint='0,0' EndPoint='1,0'>
                    <GradientStop Color='$Color' Offset='0'/>
                    <GradientStop Color='Transparent' Offset='1'/>
                </LinearGradientBrush>
            </Border.Background>
        </Border>
        <Border Width='$Bar' Height='$H' HorizontalAlignment='Right'
                VerticalAlignment='Stretch' Opacity='0' Name='R'>
            <Border.Background>
                <LinearGradientBrush StartPoint='1,0' EndPoint='0,0'>
                    <GradientStop Color='$Color' Offset='0'/>
                    <GradientStop Color='Transparent' Offset='1'/>
                </LinearGradientBrush>
            </Border.Background>
        </Border>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)
$L = $win.FindName('L')
$R = $win.FindName('R')

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(30)
$timer.Add_Tick({
    $elapsed = ([DateTime]::Now - $start).TotalMilliseconds
    if ($elapsed -gt $Dur) { $win.Close(); $timer.Stop(); return }
    $sine = [Math]::Sin($elapsed / $Dur * [Math]::PI * 2 * $Cyc)
    $opacity = [Math]::Abs($sine) * 0.65
    $L.Opacity = $opacity
    $R.Opacity = $opacity
})

$win.Add_Loaded({ $timer.Start() })
$win.ShowDialog() | Out-Null
