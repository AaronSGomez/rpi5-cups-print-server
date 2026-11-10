@echo off
title Desactivar Inicio Automatico - Print_Server_Pi5
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Desactivar_Inicio_Automatico.ps1"
echo.
pause
