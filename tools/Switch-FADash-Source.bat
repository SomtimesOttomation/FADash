@echo off
rem Usage: Switch-FADash-Source.bat espn   (or: pretend). Close FADash first.
if "%~1"=="" (
  echo Usage: Switch-FADash-Source.bat espn ^| pretend
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-FADashSource.ps1" %1
pause
