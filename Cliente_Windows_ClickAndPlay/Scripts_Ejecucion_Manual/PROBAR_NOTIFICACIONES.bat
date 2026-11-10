@echo off
title Probar Notificaciones Windows - Print_Server_Pi5
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Monitor_Impresora.ps1" -TestOnly
echo.
pause
