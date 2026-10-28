<#
.SYNOPSIS
    Deploy / uninstall the OpenCode Windows desktop notifier.
.DESCRIPTION
    Copies everything to the OpenCode global config directory (~/.config/opencode/):

      plugins/notifier/tui.js      Windows Terminal tab ring + title mark (OpenCode V2 TUI plugin)
      scripts/notify-watcher.ps1   flash + sound, driven by the OpenCode event stream
      scripts/show-notification.ps1 / flash-glow.ps1 / notification.wav

    The desktop flash and sound cannot come from a plugin any more: OpenCode V2
    plugins run with a stubbed child_process, so spawn() never starts a process.
    A watcher process (started at logon from the Startup folder) follows the
    server event stream instead.
.PARAMETER Uninstall
    Stops the watcher and removes everything from the OpenCode config directory.
.EXAMPLE
    .\deploy-opencode.ps1              # Install / update
    .\deploy-opencode.ps1 -Uninstall   # Remove
#>

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"

$opencodeDir = "$env:USERPROFILE\.config\opencode"
$pluginsDir  = "$opencodeDir\plugins"
$pluginDir   = "$pluginsDir\notifier"
$scriptsDir  = "$opencodeDir\scripts"
$startupVbs  = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\opencode-notifier.vbs"
$watcherScript = "$scriptsDir\notify-watcher.ps1"

function Stop-Watcher {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like "*notify-watcher.ps1*" } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped watcher (pid $($_.ProcessId))" -ForegroundColor Green
        }
}

# ═══════════════════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════════════════

if ($Uninstall) {
    Write-Host "=== Uninstalling OpenCode Notifier ===" -ForegroundColor Yellow
    Write-Host ""

    Stop-Watcher

    @(
        "$pluginDir\tui.js",
        "$scriptsDir\notify-watcher.ps1",
        "$scriptsDir\show-notification.ps1",
        "$scriptsDir\flash-glow.ps1",
        "$scriptsDir\notification.wav",
        $startupVbs
    ) | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item $_ -Force
            Write-Host "Removed $_" -ForegroundColor Green
        }
    }

    # Remove empty directories
    foreach ($dir in @($pluginDir, $scriptsDir)) {
        if ((Test-Path $dir) -and -not (Get-ChildItem $dir -Force)) {
            Remove-Item $dir -Force
            Write-Host "Removed empty $dir" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "Uninstall complete. Restart OpenCode for changes to take effect." -ForegroundColor Yellow
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Install / Update
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "=== OpenCode Notifier - Deploy ===" -ForegroundColor Cyan
Write-Host ""

# 1. Ensure directories exist
foreach ($dir in @($pluginDir, $scriptsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}
Write-Host "[1/5] Directories ready" -ForegroundColor Green

# 2. Copy plugin + scripts
$sources = @(
    @{ Src = "$PSScriptRoot\src\opencode-notifier.js";  Dst = "$pluginDir\tui.js" },
    @{ Src = "$PSScriptRoot\src\notify-watcher.ps1";    Dst = "$scriptsDir\notify-watcher.ps1" },
    @{ Src = "$PSScriptRoot\src\show-notification.ps1"; Dst = "$scriptsDir\show-notification.ps1" },
    @{ Src = "$PSScriptRoot\src\flash-glow.ps1";        Dst = "$scriptsDir\flash-glow.ps1" },
    @{ Src = "$PSScriptRoot\src\notification.wav";      Dst = "$scriptsDir\notification.wav" }
)

$missing = $sources | Where-Object { -not (Test-Path $_.Src) } | ForEach-Object { $_.Src }
if ($missing) {
    Write-Host "ERROR: Source files missing:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

foreach ($item in $sources) { Copy-Item -Force $item.Src -Destination $item.Dst }
Write-Host "[2/5] Copied plugin + scripts -> $opencodeDir\" -ForegroundColor Green

# 3. Drop plugins from the V1 layout (they no longer load)
@("$pluginsDir\opencode-notifier.js", "$opencodeDir\plugin\opencode-notifier.js") | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item $_ -Force
        Write-Host "  removed legacy V1 plugin $_" -ForegroundColor Gray
    }
}
Write-Host "[3/5] Legacy V1 plugins cleared" -ForegroundColor Green

# 4. Autostart entry for the watcher (hidden, no admin needed)
$vbs = @"
' Starts the OpenCode desktop notifier watcher without a console window.
CreateObject("WScript.Shell").Run "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""$watcherScript""", 0, False
"@
Set-Content -Path $startupVbs -Value $vbs -Encoding ASCII
Write-Host "[4/5] Autostart entry written -> $startupVbs" -ForegroundColor Green

# 5. (Re)start the watcher now, detached from this console
Stop-Watcher
Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$watcherScript`" >> `"%TEMP%\notify-watcher.out.log`" 2>&1"
Start-Sleep -Seconds 2
Write-Host "[5/5] Watcher started" -ForegroundColor Green

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "  TUI plugin: $pluginDir\tui.js   (WT tab ring + title mark)"
Write-Host "  Watcher:    $watcherScript     (flash + sound)"
Write-Host ""
Write-Host "Restart OpenCode so the TUI plugin loads; the watcher is already running." -ForegroundColor Yellow
Write-Host "Logs: %TEMP%\claude-notifier.log   (watcher + scripts)"
Write-Host "      $env:USERPROFILE\opencode-notifier-debug.log   (TUI plugin)"
