<#
.SYNOPSIS
    Breathing side-glow flash effect — called by Show-Flash.
    Left+right 200px gradient, sine-wave pulse, ~5 seconds.
.PARAMETER Color
    Hex color for the glow (e.g. #00C853 = green, #FFD600 = yellow)
#>
param([string]$Color = '#00C853')

Add-Type -AssemblyName PresentationFramework

# Win32 interop — required so mouse events fall THROUGH the overlay to the
# window beneath. WPF's IsHitTestVisible only affects WPF's internal hit-test;
# the underlying HWND still swallows clicks unless WS_EX_TRANSPARENT is set
# (and WS_EX_LAYERED is required for WS_EX_TRANSPARENT to take effect).
Add-Type -Namespace ClaudeNotifier -Name NativeWin -MemberDefinition @'
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    public static extern int GetWindowLong(System.IntPtr hWnd, int nIndex);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    public static extern int SetWindowLong(System.IntPtr hWnd, int nIndex, int dwNewLong);
'@

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

$win.Add_Loaded({
    # Make the HWND click-through: OR in WS_EX_TRANSPARENT (0x20) and
    # WS_EX_LAYERED (0x80000) on GWL_EXSTYLE (-20). Without this, the
    # borderless full-screen overlay still steals mouse input from the
    # window underneath, even though its content is transparent.
    $helper = [System.Windows.Interop.WindowInteropHelper]::new($win)
    $hwnd = $helper.Handle
    $GWL_EXSTYLE = -20
    $WS_EX_TRANSPARENT = 0x20
    $WS_EX_LAYERED = 0x80000
    $ex = [ClaudeNotifier.NativeWin]::GetWindowLong($hwnd, $GWL_EXSTYLE)
    [ClaudeNotifier.NativeWin]::SetWindowLong($hwnd, $GWL_EXSTYLE,
        $ex -bor $WS_EX_TRANSPARENT -bor $WS_EX_LAYERED) | Out-Null
    $timer.Start()
})
$win.ShowDialog() | Out-Null
