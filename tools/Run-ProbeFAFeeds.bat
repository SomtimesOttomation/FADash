@echo off
rem Runs tools\Probe-FAFeeds.ps1 (Windows PowerShell 5.1). About 15 requests, one per second. No odds are fetched.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Probe-FAFeeds.ps1"
echo.
pause
