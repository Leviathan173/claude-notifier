@echo off
REM Hook wrapper — writes marker then calls notification
REM -STA is required for WPF Window.ShowDialog()
echo [%date% %time%] Hook triggered: %~1 >> "%TEMP%\hook-triggered.txt"
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "C:/Users/50653/.claude/scripts/show-notification.ps1" -Title "Claude Code" -Message "%~1" -Sound "Default"
