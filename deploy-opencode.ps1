<#
.SYNOPSIS
    Deploy / uninstall the OpenCode Windows desktop notifier plugin.
.DESCRIPTION
    Copies the notification plugin and PowerShell scripts to the OpenCode
    global config directory (~/.config/opencode/). The plugin loads automatically
    at OpenCode startup.
.PARAMETER Uninstall
    Removes the plugin and scripts from the OpenCode config directory.
.EXAMPLE
    .\deploy-opencode.ps1              # Install / update
    .\deploy-opencode.ps1 -Uninstall   # Remove
#>

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"

$opencodeDir  = "$env:USERPROFILE\.config\opencode"
$pluginsDir   = "$opencodeDir\plugins"
$scriptsDir   = "$opencodeDir\scripts"

# ═══════════════════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════════════════

if ($Uninstall) {
    Write-Host "=== Uninstalling OpenCode Notifier ===" -ForegroundColor Yellow
    Write-Host ""

    @(
        "$pluginsDir\opencode-notifier.js",
        "$scriptsDir\show-notification.ps1",
        "$scriptsDir\flash-glow.ps1",
        "$scriptsDir\notification.wav"
    ) | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item $_ -Force
            Write-Host "Removed $_" -ForegroundColor Green
        }
    }

    # Remove empty directories
    foreach ($dir in @($scriptsDir, $pluginsDir)) {
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

Write-Host "=== OpenCode Notifier — Deploy ===" -ForegroundColor Cyan
Write-Host ""

# 1. Ensure directories exist
$dirsCreated = $false
foreach ($dir in @($pluginsDir, $scriptsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $dirsCreated = $true
    }
}
if ($dirsCreated) {
    Write-Host "[1/3] Created directories" -ForegroundColor Green
}
else {
    Write-Host "[1/3] Directories exist" -ForegroundColor Gray
}

# 2. Copy plugin + scripts
$sources = @(
    @{ Src = "$PSScriptRoot\src\opencode-notifier.js";    Dst = "$pluginsDir\opencode-notifier.js" },
    @{ Src = "$PSScriptRoot\src\show-notification.ps1";   Dst = "$scriptsDir\show-notification.ps1" },
    @{ Src = "$PSScriptRoot\src\flash-glow.ps1";          Dst = "$scriptsDir\flash-glow.ps1" },
    @{ Src = "$PSScriptRoot\src\notification.wav";        Dst = "$scriptsDir\notification.wav" }
)

$missing = $sources | Where-Object { -not (Test-Path $_.Src) } | ForEach-Object { $_.Src }
if ($missing) {
    Write-Host "ERROR: Source files missing:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

foreach ($item in $sources) { Copy-Item -Force $item.Src -Destination $item.Dst }
Write-Host "[2/3] Copied plugin + scripts -> $opencodeDir\" -ForegroundColor Green

# 3. Summary
Write-Host "[3/3] Deploy complete." -ForegroundColor Green
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "  Plugin:   $pluginsDir\opencode-notifier.js"
Write-Host "  Scripts:  $scriptsDir\"
Write-Host ""
Write-Host "Restart OpenCode for the plugin to load." -ForegroundColor Yellow
