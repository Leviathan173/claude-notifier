@echo off
echo [%date% %time%] Flash: %~1 >> "%TEMP%\hook-triggered.txt"
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\scripts\show-notification.ps1" -Title "Claude Code" -Message "%~1" -Sound "Silent" -Flash -FlashColor "%~2"
