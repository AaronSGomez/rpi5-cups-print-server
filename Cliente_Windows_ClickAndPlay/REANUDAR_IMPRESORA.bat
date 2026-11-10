@echo off
title Reanudar Impresora HP LaserJet
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Reanudar_Impresora.ps1"
echo.
pause
