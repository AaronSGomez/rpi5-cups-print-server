@echo off
title Detener Print_Server_Pi5
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Detener_Monitor.ps1"
echo.
pause
