@echo off
:: =============================================================================
:: DESINSTALADOR CLICK & PLAY — IMPRESORA HP LASERJET M14-M17
:: =============================================================================
setlocal enableextensions
cd /d "%~dp0"

title Desinstalador de Impresora en Red

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo Eliminando impresora 'HP LaserJet M14-M17 (Red Hogar)'...
powershell -Command "Remove-Printer -Name 'HP LaserJet M14-M17 (Red Hogar)' -ErrorAction SilentlyContinue; Remove-Printer -Name 'HP LaserJet M14-M17 (RPi Server)' -ErrorAction SilentlyContinue; Write-Host '[OK] Impresora desinstalada con exito.' -ForegroundColor Green"
pause
