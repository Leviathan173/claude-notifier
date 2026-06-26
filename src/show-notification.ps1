<#
.SYNOPSIS
    Shows a desktop notification with custom sound for Claude Code hooks.
.DESCRIPTION
    Uses a lightweight WPF popup — no automatic system sound, so only
    the custom .wav plays.  Auto-discovers notification.wav.
#>

param(
    [string]$Title   = "Claude Code",
    [string]$Message = "Task completed",
    [string]$Sound   = "Default"
)

$ErrorActionPreference = "Stop"
$LogFile   = "$env:TEMP\claude-notifier.log"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    "[$ts] $Msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

Write-Log "START: Title='$Title' Message='$Message' Sound='$Sound'"

# ═══════════════════════════════════════════════════════════════════════════
# Sound — only ONE source plays
# ═══════════════════════════════════════════════════════════════════════════

function Play-NotifySound {
    param([string]$SoundArg)

    if ($SoundArg -eq "Silent") { Write-Log "SOUND: silent"; return }

    # 1. Explicit .wav path
    if ($SoundArg -match '\.wav$' -and (Test-Path $SoundArg)) {
        try {
            (New-Object System.Media.SoundPlayer ((Resolve-Path $SoundArg).Path)).Play()
            Write-Log "SOUND: custom wav='$SoundArg'"
            return
        } catch { Write-Log "SOUND FAIL: $_" }
    }

    # 2. Auto-discovered notification.wav
    $autoWav = Join-Path $ScriptDir "notification.wav"
    if (Test-Path $autoWav) {
        try {
            (New-Object System.Media.SoundPlayer $autoWav).Play()
            Write-Log "SOUND: auto wav='$autoWav'"
            return
        } catch { Write-Log "SOUND FAIL: $_" }
    }

    # 3. Fallback: system sound
    try {
        switch ($SoundArg) {
            "IM"    { [System.Media.SystemSounds]::Exclamation.Play(); break }
            "Alarm" { [System.Media.SystemSounds]::Hand.Play(); break }
            default { [System.Media.SystemSounds]::Asterisk.Play(); break }
        }
        Write-Log "SOUND: system='$SoundArg'"
    } catch {
        try { [Console]::Beep(800, 200) } catch { }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# WPF popup — built programmatically, no XAML parsing issues
# ═══════════════════════════════════════════════════════════════════════════

function Show-Popup {
    param([string]$Title, [string]$Message)

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName WindowsBase -ErrorAction Stop

        # Escape text for XAML
        $safeTitle   = [System.Security.SecurityElement]::Escape($Title)
        $safeMessage = [System.Security.SecurityElement]::Escape($Message)

        $screenW = [System.Windows.SystemParameters]::PrimaryScreenWidth
        $screenH = [System.Windows.SystemParameters]::PrimaryScreenHeight

        $xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    Topmost="True"
    ShowInTaskbar="False"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    ResizeMode="NoResize"
    SizeToContent="WidthAndHeight"
    Left="$($screenW - 330)"
    Top="$($screenH - 140)">
    <Border Background="#2B2B2B" BorderBrush="#0078D4" BorderThickness="0,0,0,4"
            CornerRadius="6" Padding="20,14" SnapsToDevicePixels="True">
        <Border.Effect>
            <DropShadowEffect Color="Black" BlurRadius="12" ShadowDepth="2" Opacity="0.4"/>
        </Border.Effect>
        <StackPanel MaxWidth="280">
            <TextBlock Text="$safeTitle" FontWeight="Bold" FontSize="13"
                       Foreground="White" TextWrapping="Wrap" Margin="0,0,0,6"/>
            <TextBlock Text="$safeMessage" FontSize="12"
                       Foreground="#AAAAAA" TextWrapping="Wrap"/>
        </StackPanel>
    </Border>
</Window>
"@
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $window = [Windows.Markup.XamlReader]::Load($reader)

        # Auto-close after 5 seconds
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(5000)
        $timer.Add_Tick({
            $window.Close()
            $timer.Stop()
        })

        $window.Add_Loaded({ $timer.Start() })
        $window.ShowDialog() | Out-Null

        Write-Log "POPUP OK"
    }
    catch {
        Write-Log "POPUP FAIL: $_"
        try { [Console]::Beep(800, 200) } catch { }
    }
}

# ── Main ──
Play-NotifySound -SoundArg $Sound
Show-Popup -Title $Title -Message $Message
Write-Log "END"
