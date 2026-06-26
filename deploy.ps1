<#
.SYNOPSIS
    One-click deploy / uninstall for the Claude Code Windows toast notifier.
.DESCRIPTION
    Copies the notification script to ~/.claude/scripts/ and merges the
    required hooks into ~/.claude/settings.json.  No external dependencies.
.PARAMETER Uninstall
    Removes the hooks from settings.json and deletes the notification script.
.EXAMPLE
    .\deploy.ps1              # Install / update
    .\deploy.ps1 -Uninstall   # Remove
#>

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$claudeDir   = "$env:USERPROFILE\.claude"
$scriptsDir  = "$claudeDir\scripts"
$settingsFile = "$claudeDir\settings.json"
$scriptName  = "show-notification.ps1"
$sourceScript = "$PSScriptRoot\src\$scriptName"
$destScript   = "$scriptsDir\$scriptName"

# ═══════════════════════════════════════════════════════════════════════════
# Helper: detect if running in bash (Git Bash / MSYS2)
# ═══════════════════════════════════════════════════════════════════════════

function Get-NativePath([string]$Path) {
    # Git Bash maps C:\ → /c/, but PowerShell needs native Windows paths.
    if ($Path -match '^/([a-zA-Z])/') {
        return "$($Matches[1].ToUpper()):\$($Path.Substring(3) -replace '/','\')"
    }
    return $Path
}

# ═══════════════════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════════════════

if ($Uninstall) {
    Write-Host "=== Uninstalling Claude Code Notifier ===" -ForegroundColor Yellow

    # Remove hooks from settings.json
    if (Test-Path $settingsFile) {
        Write-Host "Removing notification hooks from settings.json ..."
        $settings = Get-Content -Raw $settingsFile | ConvertFrom-Json

        if ($settings.hooks) {
            $removed = $false
            $events = @("Stop", "SubagentStop", "PreToolUse")
            foreach ($event in $events) {
                if ($settings.hooks.$event) {
                    $before = $settings.hooks.$event.Count
                    $settings.hooks.$event = @(
                        $settings.hooks.$event | Where-Object {
                            $_.hooks[0].command -notmatch 'claude-notifier|claude.*scripts.*show-notification'
                        }
                    )
                    $after = $settings.hooks.$event.Count
                    if ($after -eq 0) {
                        $settings.hooks.PSObject.Properties.Remove($event)
                    }
                    if ($before -ne $after) { $removed = $true }
                }
            }

            # If hooks object is now empty, remove it
            if ($settings.hooks.PSObject.Properties.Count -eq 0) {
                $settings.PSObject.Properties.Remove('hooks')
            }

            if ($removed) {
                $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsFile -Encoding utf8
                Write-Host "  Hooks removed." -ForegroundColor Green
            }
            else {
                Write-Host "  No matching hooks found." -ForegroundColor Gray
            }
        }
        else {
            Write-Host "  No hooks configured — nothing to remove." -ForegroundColor Gray
        }
    }

    # Remove notification script
    if (Test-Path $destScript) {
        Remove-Item $destScript -Force
        Write-Host "Removed $destScript" -ForegroundColor Green
    }
    else {
        Write-Host "Script not found at $destScript — already removed." -ForegroundColor Gray
    }

    Write-Host "`nUninstall complete. Restart Claude Code for changes to take effect." -ForegroundColor Yellow
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
Write-Host "[2/3] Copied $scriptName → $scriptsDir\" -ForegroundColor Green

# 3. Merge hooks into settings.json
Write-Host "[3/3] Merging hooks into settings.json ..."

if (-not (Test-Path $settingsFile)) {
    Write-Host "ERROR: settings.json not found at $settingsFile" -ForegroundColor Red
    Write-Host "Is Claude Code installed and configured?" -ForegroundColor Red
    exit 1
}

$settings = Get-Content -Raw $settingsFile | ConvertFrom-Json

# Ensure hooks property exists
if (-not $settings.hooks) {
    $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue @{} -Force
}

# Escape the destScript path for use in the command string
# Use double-backslash for JSON
$escapedScript = $destScript.Replace('\', '\\')

# Define the hook entries we want to add
$hookDefs = @(
    @{
        Event   = "Stop"
        Matcher = ""
        Command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$escapedScript`" -Title `"Claude Code`" -Message `"Task completed — Claude is waiting for you`" -Sound `"Default`""
        Timeout = 5
        Desc    = "Stop (task completion)"
    },
    @{
        Event   = "SubagentStop"
        Matcher = ""
        Command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$escapedScript`" -Title `"Claude Code`" -Message `"Subagent task completed`" -Sound `"Default`""
        Timeout = 5
        Desc    = "SubagentStop (subagent completion)"
    },
    @{
        Event   = "PreToolUse"
        Matcher = "AskUserQuestion"
        Command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$escapedScript`" -Title `"Claude Code — Input Needed`" -Message `"Claude needs your response — a question is waiting for you`" -Sound `"IM`""
        Timeout = 5
        Desc    = "PreToolUse (needs user input)"
    }
)

$addedCount = 0
$skippedCount = 0

foreach ($def in $hookDefs) {
    $event = $def.Event

    # Ensure the event array exists
    if (-not $settings.hooks.$event) {
        $settings.hooks | Add-Member -NotePropertyName $event -NotePropertyValue @() -Force
    }

    # Check if an identical entry already exists
    $exists = $false
    foreach ($entry in $settings.hooks.$event) {
        if ($entry.hooks -and $entry.hooks[0].command -eq $def.Command) {
            $exists = $true
            break
        }
    }

    if ($exists) {
        Write-Host "  [skip] $($def.Desc) — already configured" -ForegroundColor Gray
        $skippedCount++
        continue
    }

    # Build the hook entry
    $hookEntry = @{
        hooks = @(
            @{
                type    = "command"
                command = $def.Command
                timeout = $def.Timeout
            }
        )
    }

    if ($def.Matcher) {
        $hookEntry['matcher'] = $def.Matcher
    }

    # Append to the event array
    $newArray = @($settings.hooks.$event) + $hookEntry
    $settings.hooks.$event = $newArray

    Write-Host "  [add] $($def.Desc)" -ForegroundColor Green
    $addedCount++
}

# Write back settings.json
$settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsFile -Encoding utf8

Write-Host ""
Write-Host "=== Deploy Complete ===" -ForegroundColor Cyan
Write-Host "  Added:   $addedCount hook(s)" -ForegroundColor Green
Write-Host "  Skipped: $skippedCount hook(s) (already present)" -ForegroundColor Gray
Write-Host ""
Write-Host "Restart Claude Code for hooks to take effect." -ForegroundColor Yellow
