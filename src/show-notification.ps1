<#
.SYNOPSIS
    Shows a desktop notification with sound for Claude Code hooks.
.DESCRIPTION
    Uses NotifyIcon balloon tips for visual notification.
    Sound: plays custom .wav file if available, otherwise falls back to
    system sounds.  Place a "notification.wav" next to this script to use
    your own sound — it will be picked up automatically.
.PARAMETER Title
    Notification title.
.PARAMETER Message
    Notification body text.
.PARAMETER Sound
    One of: Default, IM, Mail, Reminder, SMS, Alarm, Silent
    OR a path to a .wav file (e.g. "C:\sounds\ding.wav")
    If omitted, looks for "notification.wav" alongside this script.
#>

param(
    [string]$Title   = "Claude Code",
    [string]$Message = "Task completed",
    [string]$Sound   = "Default"
)

$ErrorActionPreference = "Stop"
$LogFile = "$env:TEMP\claude-notifier.log"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    "[$ts] $Msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

Write-Log "START: Title='$Title' Message='$Message' Sound='$Sound'"

# ═══════════════════════════════════════════════════════════════════════════
# Sound — supports .wav files and system sound aliases
# ═══════════════════════════════════════════════════════════════════════════

function Play-NotifySound {
    param([string]$SoundArg)

    if ($SoundArg -eq "Silent") {
        Write-Log "SOUND: silent (skipped)"
        return
    }

    # ── 1. Explicit .wav path (absolute or relative) ──────────────────
    if ($SoundArg -match '\.wav$' -and (Test-Path $SoundArg)) {
        try {
            $player = New-Object System.Media.SoundPlayer
            $player.SoundLocation = (Resolve-Path $SoundArg).Path
            $player.Play()
            Write-Log "SOUND: custom wav='$SoundArg'"
            return
        }
        catch {
            Write-Log "SOUND FAIL (custom wav): $_"
        }
    }

    # ── 2. "notification.wav" alongside this script (auto-discovery) ──
    $autoWav = Join-Path $ScriptDir "notification.wav"
    if (Test-Path $autoWav) {
        try {
            $player = New-Object System.Media.SoundPlayer
            $player.SoundLocation = $autoWav
            $player.Play()
            Write-Log "SOUND: auto-discovered wav='$autoWav'"
            return
        }
        catch {
            Write-Log "SOUND FAIL (auto wav): $_"
        }
    }

    # ── 3. Fall back to system sound alias ─────────────────────────────
    try {
        switch ($SoundArg) {
            "IM"     { [System.Media.SystemSounds]::Exclamation.Play(); break }
            "Alarm"  { [System.Media.SystemSounds]::Hand.Play(); break }
            "Mail"   { [System.Media.SystemSounds]::Asterisk.Play(); break }
            "Reminder"{ [System.Media.SystemSounds]::Asterisk.Play(); break }
            "SMS"    { [System.Media.SystemSounds]::Exclamation.Play(); break }
            default  { [System.Media.SystemSounds]::Asterisk.Play(); break }
        }
        Write-Log "SOUND: system alias='$SoundArg'"
    }
    catch {
        Write-Log "SOUND FAIL (system): $_"
        try { [Console]::Beep(800, 200) } catch { }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Balloon notification
# ═══════════════════════════════════════════════════════════════════════════

function Show-Balloon {
    param([string]$Title, [string]$Message)

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(
            (Get-Command powershell.exe).Source
        )
        $notify.BalloonTipTitle = $Title
        $notify.BalloonTipText  = $Message
        $notify.BalloonTipIcon  = 'Info'
        $notify.Visible = $true
        $notify.ShowBalloonTip(7000)
        Start-Sleep -Milliseconds 300
        $notify.Dispose()
        Write-Log "BALLOON OK: Title='$Title'"
    }
    catch {
        Write-Log "BALLOON FAIL: $_"
        try { [Console]::Beep(800, 200) } catch { }
    }
}

# ── Main ──
Play-NotifySound -SoundArg $Sound
Show-Balloon -Title $Title -Message $Message
Write-Log "END"
