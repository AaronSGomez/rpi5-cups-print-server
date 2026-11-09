@echo off
:: =============================================================================
:: LANZADOR DE INSTALACIÓN — CLIENTE WINDOWS IMPRESORA HP (CUPS / RASPBERRY PI 5)
:: setup_printer_client.bat
:: =============================================================================

title Instalador de Impresora en Red - Servidor Raspberry Pi 5
echo =====================================================================
echo    INSTALADOR CLIENTE WINDOWS - HP LASERJET M14-M17 (CUPS RPi5)
echo =====================================================================
echo.

:: Comprobar si se ejecuta con permisos de administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Solicitando permisos de Administrador...
    powershell -Command "Start-Process '%~0' -Verb RunAs"
    exit /b
)

:: Ejecutar el script PowerShell con bypass de execution policy
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_printer_client.ps1"

if %errorLevel% neq 0 (
    echo.
    echo [X] La instalacion ha finalizado con advertencias o errores.
    pause
)
