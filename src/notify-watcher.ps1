<#
.SYNOPSIS
    Watches the OpenCode event stream and plays the desktop flash + sound when a
    session finishes or waits for the user.
.NOTES
    Started at logon by the opencode-notifier.vbs shortcut in the Startup folder.
    OpenCode V2 plugins run in a sandbox without process access, so this runs
    outside of OpenCode instead of as a plugin.
#>

$ErrorActionPreference = 'Continue'
$notifier = Join-Path $PSScriptRoot 'show-notification.ps1'
$wav = Join-Path $PSScriptRoot 'notification.wav'
$passwordFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'service.json'
$logFile = Join-Path $env:TEMP 'claude-notifier.log'

function Write-WatcherLog {
    param([string]$Msg)
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] watcher: $Msg" | Out-File -FilePath $logFile -Append -Encoding utf8
}

# Shortcut: every OpenCode server start picks a new port, so the URL is looked
# up once per (re)connect instead of reading the service registration file.
$rules = @(
    @{ Color = 'Green';  Pattern = '"type":"(session\.idle|session\.execution\.succeeded)"' },
    @{ Color = 'Yellow'; Pattern = '"type":"(permission\.asked|form\.created|session\.execution\.failed)"' }
)

Write-WatcherLog 'started'

while ($true) {
    try {
        $url = (& opencode service status 2>&1 | Select-String -Pattern '^https?://' | Select-Object -First 1)
        if (-not $url) { Start-Sleep -Seconds 10; continue }
        $url = $url.ToString().Trim()
        $password = (Get-Content $passwordFile -Raw | ConvertFrom-Json).password

        & curl.exe -N -s -u "opencode:$password" "$url/api/event" | ForEach-Object {
            if ("$_" -notlike 'data: *') { return }
            foreach ($rule in $rules) {
                if ("$_" -match $rule.Pattern) {
                    Write-WatcherLog "$($rule.Color) event"
                    Start-Process -WindowStyle Hidden -FilePath powershell.exe `
                        -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$notifier`" -Flash -FlashColor $($rule.Color) -Sound `"$wav`""
                    break
                }
            }
        }
        Write-WatcherLog 'stream closed'
    } catch {
        Write-WatcherLog "error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 5
}
