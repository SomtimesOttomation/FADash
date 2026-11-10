@echo off
rem ESPN deep check only (League One and League Two matches, upcoming status names, injuries on rosters). Up to about 18 requests, one per second. No odds are saved.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Probe-FAFeeds.ps1" -Deep
echo.
pause
