@echo off
:: =============================================================================
:: INSTALADOR CLICK & PLAY — IMPRESORA HP LASERJET M14-M17 (RED LOCAL HOGAR)
:: =============================================================================
setlocal enableextensions
cd /d "%~dp0"

title Instalador de Impresora en Red Local

:: Comprobar si se ejecuta con permisos de administrador; si no, auto-elevar con UAC
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo =====================================================================
    echo  Solicitando permisos de Administrador para instalar la impresora...
    echo =====================================================================
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Ejecutar el script PowerShell en modo interactivo y transparente
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar_Impresora.ps1"

if %errorLevel% neq 0 (
    echo.
    echo [!] Hubo una advertencia o error durante la instalacion.
    pause
)
