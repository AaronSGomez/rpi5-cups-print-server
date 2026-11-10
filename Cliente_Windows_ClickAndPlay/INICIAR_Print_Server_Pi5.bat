@echo off
title Iniciar Print_Server_Pi5 (Monitor de Impresion)
cd /d "%~dp0"

echo =====================================================================
echo       INICIANDO SERVICIO PRINT_SERVER_PI5 EN SEGUNDO PLANO
echo =====================================================================
echo.

if not exist "ip_servidor.txt" (
    echo [!] Primera configuracion detectada.
    echo Introduce la direccion IP local de tu Raspberry Pi:
    echo (Ejemplo: 192.168.1.100 o la IP asignada en tu router)
    echo.
    set /p SERVER_IP="Direccion IP de la Raspberry Pi: "
    echo %SERVER_IP%> ip_servidor.txt
    echo [OK] IP guardada en ip_servidor.txt
    echo.
)

wscript.exe "Print_Server_Pi5.vbs"

echo [*] Servicio Print_Server_Pi5 activado correctamente.
echo [*] Permanecera en segundo plano vigilando las impresiones.
echo.
echo Recibiras notificaciones emergentes en Windows cuando:
echo   - Se envie un documento a la impresora
echo   - La impresion finalice con exito
echo   - Ocurra un atasco de papel o bloqueo de cola
echo =====================================================================
echo.
ping 127.0.0.1 -n 3 >nul
