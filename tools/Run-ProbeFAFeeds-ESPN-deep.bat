@echo off
rem ESPN deep check only (League One, League Two, status names, line-ups, players). About 12 requests, one per second. No odds are saved.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Probe-FAFeeds.ps1" -Deep
echo.
pause
