@echo off
rem Installs everything CareLink Extract needs on this PC (see Setup.ps1). Safe to run again.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" %*
echo.
echo Press any key to close this window.
pause >nul
