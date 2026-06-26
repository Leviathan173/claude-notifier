<#
.SYNOPSIS
    One-click deploy / uninstall for the Claude Code Windows toast notifier.
.DESCRIPTION
    Copies the notification script to ~/.claude/scripts/ and merges the
    required hooks into ~/.claude/settings.json using Node.js for reliable
    JSON manipulation (PowerShell ConvertFrom-Json can choke on complex
    settings.json files).
.PARAMETER Uninstall
    Removes the hooks from settings.json and deletes the notification script.
.EXAMPLE
    .\deploy.ps1              # Install / update
    .\deploy.ps1 -Uninstall   # Remove
#>

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"

$claudeDir    = "$env:USERPROFILE\.claude"
$scriptsDir   = "$claudeDir\scripts"
$settingsFile = "$claudeDir\settings.json"
$scriptName   = "show-notification.ps1"
$sourceScript = "$PSScriptRoot\src\$scriptName"
$destScript   = "$scriptsDir\$scriptName"
$mergeJs      = "$PSScriptRoot\src\merge-hooks.js"

# ── Helper: find Node.js ───────────────────────────────────────────────────

function Find-Node {
    # Try 'node' on PATH (works in most environments)
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { return $node.Source }

    # Common install locations
    $candidates = @(
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe",
        "$env:LOCALAPPDATA\fnm_multishells\*\node.exe",
        "$env:APPDATA\nvm\*\node.exe"
    )
    foreach ($c in $candidates) {
        $found = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    throw "Node.js not found.  Please install Node.js or add it to your PATH."
}

# ═══════════════════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════════════════

if ($Uninstall) {
    Write-Host "=== Uninstalling Claude Code Notifier ===" -ForegroundColor Yellow
    Write-Host ""

    $nodeExe = Find-Node

    # Remove hooks from settings.json
    if (Test-Path $settingsFile) {
        Write-Host "Removing notification hooks from settings.json ..."

        if (-not (Test-Path $mergeJs)) {
            Write-Host "ERROR: merge-hooks.js not found at $mergeJs" -ForegroundColor Red
            exit 1
        }

        $result = & $nodeExe $mergeJs uninstall $settingsFile 2>&1
        Write-Host $result
    }

    # Remove notification script
    if (Test-Path $destScript) {
        Remove-Item $destScript -Force
        Write-Host "Removed $destScript" -ForegroundColor Green
    }
    if (Test-Path "$scriptsDir\hook-wrapper.cmd") {
        Remove-Item "$scriptsDir\hook-wrapper.cmd" -Force
        Write-Host "Removed $scriptsDir\hook-wrapper.cmd" -ForegroundColor Green
    }
    else {
        Write-Host "Script not found at $destScript — already removed." -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Uninstall complete. Restart Claude Code for changes to take effect." -ForegroundColor Yellow
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Install / Update
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "=== Claude Code Notifier — One-Click Deploy ===" -ForegroundColor Cyan
Write-Host ""

# 1. Ensure scripts directory exists
if (-not (Test-Path $scriptsDir)) {
    New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
    Write-Host "[1/3] Created $scriptsDir" -ForegroundColor Green
}
else {
    Write-Host "[1/3] Directory $scriptsDir exists" -ForegroundColor Gray
}

# 2. Copy notification script
if (-not (Test-Path $sourceScript)) {
    Write-Host "ERROR: Source script not found at $sourceScript" -ForegroundColor Red
    Write-Host "Make sure you run deploy.ps1 from the project root." -ForegroundColor Red
    exit 1
}

Copy-Item -Force $sourceScript -Destination $destScript
Copy-Item -Force "$PSScriptRoot\src\hook-wrapper.cmd" -Destination "$scriptsDir\hook-wrapper.cmd"
Write-Host "[2/3] Copied scripts -> $scriptsDir\" -ForegroundColor Green

# 3. Merge hooks into settings.json
Write-Host "[3/3] Merging hooks into settings.json ..."

if (-not (Test-Path $settingsFile)) {
    Write-Host "ERROR: settings.json not found at $settingsFile" -ForegroundColor Red
    Write-Host "Is Claude Code installed and configured?" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $mergeJs)) {
    Write-Host "ERROR: merge-hooks.js not found at $mergeJs" -ForegroundColor Red
    exit 1
}

$nodeExe = Find-Node
$result = & $nodeExe $mergeJs install $settingsFile $destScript 2>&1
Write-Host $result

# Parse the JSON summary from the last line
$summaryLine = ($result | Where-Object { $_ -match '^\{"added"' }) | Select-Object -Last 1
if ($summaryLine) {
    $summary = $summaryLine | ConvertFrom-Json
    $addedCount   = $summary.added
    $skippedCount = $summary.skipped
}
else {
    $addedCount   = 0
    $skippedCount = 0
}

Write-Host ""
Write-Host "=== Deploy Complete ===" -ForegroundColor Cyan
Write-Host "  Added:   $addedCount hook(s)" -ForegroundColor Green
Write-Host "  Skipped: $skippedCount hook(s) (already present)" -ForegroundColor Gray
Write-Host ""
Write-Host "Restart Claude Code for hooks to take effect." -ForegroundColor Yellow
