@echo off
title Activar Inicio Automatico - Print_Server_Pi5
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Activar_Inicio_Automatico.ps1"
echo.
pause
