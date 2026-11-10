@echo off
:: =============================================================================
:: 🏴‍☠️ INSTALADOR TODO EN UNO — PRINT_SERVER_PI5 (HP LASERJET M14-M17)
:: =============================================================================
setlocal enableextensions
cd /d "%~dp0"

title Instalador Todo en Uno - Print_Server_Pi5

if exist "%~dp0INSTALAR_PRINT_SERVER_PI5.exe" (
    start "" "%~dp0INSTALAR_PRINT_SERVER_PI5.exe"
    exit /b
)

:: Fallback con elevación UAC y PowerShell
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Solicitando permisos de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar_Impresora.ps1"
if %errorLevel% neq 0 pause
