#Requires -Version 5.1
<#
=============================================================================
INSTALADOR CLICK & PLAY - CLIENTE WINDOWS 10 / 11
=============================================================================
Configura automaticamente la impresora compartida HP LaserJet M14-M17
desde el servidor Raspberry Pi en cualquier equipo de la red local.
=============================================================================
#>

[CmdletBinding()]
param(
    [string]$PrinterDisplayName = "HP LaserJet M14-M17 (Red Hogar)",
    [string]$QueueName = "HP_LaserJet_M14_M17",
    [int]$Port = 631
)

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "       INSTALACION CLICK & PLAY - IMPRESORA RED LOCAL HOGAR          " -ForegroundColor Cyan
Write-Host "       Modelo: HP LaserJet Pro M14-M17 (Servidor Raspberry Pi)       " -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# 1. VERIFICACION DE ELEVACION DE ADMINISTRADOR
# -----------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] Elevando privilegios a Administrador para registrar el dispositivo..." -ForegroundColor Yellow
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# -----------------------------------------------------------------------------
# 2. DETERMINACION DE LA IP DEL SERVIDOR (AUTOMATICA O MANUAL)
# -----------------------------------------------------------------------------
$ipConfigFile = Join-Path $PSScriptRoot "ip_servidor.txt"
$activeHost = $null

# A) Comprobar si existe archivo local preconfigurado (ip_servidor.txt)
if (Test-Path $ipConfigFile) {
    $fileContent = (Get-Content $ipConfigFile -Raw).Trim()
    if ($fileContent) {
        Write-Host "[*] Archivo local ip_servidor.txt detectado: $fileContent" -ForegroundColor Cyan
        $activeHost = $fileContent
    }
}

# B) Si no hay archivo o está vacío, solicitar la IP al usuario
if (-not $activeHost) {
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host "  CONFIGURACION DE RED LOCAL - SERVIDOR DE IMPRESION" -ForegroundColor Yellow
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host "Por favor, introduce la direccion IP local de la Raspberry Pi:" -ForegroundColor White
    Write-Host "(Ejemplo habitual: 192.168.1.100 o la IP asignada en tu router)" -ForegroundColor DarkGray
    Write-Host ""
    
    while (-not $activeHost) {
        $userInput = (Read-Host "Direccion IP de la Raspberry Pi").Trim()
        if ($userInput) {
            $activeHost = $userInput
        } else {
            Write-Host "[!] La IP no puede estar vacia. Intentalo de nuevo." -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "[*] Comprobando conexion con $activeHost en el puerto $Port (CUPS)..." -ForegroundColor Cyan
$testConn = Test-NetConnection -ComputerName $activeHost -Port $Port -WarningAction SilentlyContinue

if (-not $testConn.TcpTestSucceeded) {
    Write-Host ""
    Write-Host "[X] ERROR: No se pudo conectar a $activeHost en el puerto $Port" -ForegroundColor Red
    Write-Host "    1. Comprueba que la Raspberry Pi este encendida y conectada al router." -ForegroundColor Yellow
    Write-Host "    2. Verifica que este equipo este en la misma red Wi-Fi o cable Ethernet." -ForegroundColor Yellow
    Write-Host "    3. Comprueba que la direccion IP introducida sea la correcta." -ForegroundColor Yellow
    Write-Host ""
    # Si fallo y habia un archivo guardado, borrarlo para que pregunte la proxima vez
    if (Test-Path $ipConfigFile) {
        Remove-Item $ipConfigFile -Force -ErrorAction SilentlyContinue
    }
    Read-Host "Presione Enter para salir..."
    exit 1
}

# Guardar la IP comprobada en el archivo local para no volver a pedirla en este equipo
if (-not (Test-Path $ipConfigFile)) {
    try {
        Set-Content -Path $ipConfigFile -Value $activeHost -NoNewline
        Write-Host "[OK] IP memorizada en ip_servidor.txt para proximas ejecuciones." -ForegroundColor DarkGray
    } catch {}
}

$IppUrl = "http://${activeHost}:${Port}/printers/${QueueName}"
Write-Host "[OK] Conexion con el servidor CUPS establecida con exito." -ForegroundColor Green
Write-Host "[OK] URL IPP de destino: $IppUrl" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# 3. SELECCION AUTOMATICA DEL MEJOR CONTROLADOR WINDOWS
# -----------------------------------------------------------------------------
Write-Host "[*] Comprobando controladores disponibles en este equipo..." -ForegroundColor Cyan
$installedDrivers = Get-PrinterDriver | Select-Object -ExpandProperty Name

$preferredDrivers = @(
    "HP LaserJet M14-M17 PCLmS",
    "HP LaserJet M14-M17",
    "Microsoft IPP Class Driver",
    "Microsoft PCL6 Class Driver",
    "Universal Print Class Driver",
    "Generic / Text Only"
)

$selectedDriver = $null
foreach ($driverName in $preferredDrivers) {
    if ($installedDrivers -contains $driverName) {
        $selectedDriver = $driverName
        break
    }
}

if (-not $selectedDriver) {
    $selectedDriver = $installedDrivers | Where-Object { $_ -match "IPP" -or $_ -match "PCL" } | Select-Object -First 1
}

if (-not $selectedDriver) {
    $selectedDriver = "Generic / Text Only"
}

Write-Host "[OK] Driver seleccionado: '$selectedDriver'" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# 4. INSTALACION O ACTUALIZACION DE LA COLA LOCAL
# -----------------------------------------------------------------------------
Write-Host "[*] Registrando cola de impresion '$PrinterDisplayName'..." -ForegroundColor Cyan

# Eliminar instalacion previa para asegurar configuracion limpia
$existing = Get-Printer -Name $PrinterDisplayName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "    -> Actualizando configuracion previa..." -ForegroundColor DarkYellow
    Remove-Printer -Name $PrinterDisplayName -ErrorAction SilentlyContinue
}

try {
    Add-Printer -Name $PrinterDisplayName -DriverName $selectedDriver -PortName $IppUrl -ErrorAction Stop
    Write-Host "[OK] Impresora registrada con exito via Windows IPP." -ForegroundColor Green
}
catch {
    Write-Host "[!] Reintentando mediante interfaz nativa PrintUI..." -ForegroundColor Yellow
    try {
        $argsPrintUI = "/b `"$PrinterDisplayName`" /x /n `"$PrinterDisplayName`" /if /f `"`" /r `"$IppUrl`" /m `"$selectedDriver`""
        Start-Process "rundll32.exe" -ArgumentList "printui.dll,PrintUIEntry $argsPrintUI" -Wait
        Write-Host "[OK] Impresora registrada con exito via PrintUI." -ForegroundColor Green
    }
    catch {
        Write-Host "[X] ERROR al registrar la cola: $_" -ForegroundColor Red
        Read-Host "Presione Enter para salir..."
        exit 1
    }
}

# -----------------------------------------------------------------------------
# 5. ESTABLECER COMO IMPRESORA PREDETERMINADA
# -----------------------------------------------------------------------------
Write-Host "[*] Estableciendo '$PrinterDisplayName' como impresora predeterminada..." -ForegroundColor Cyan
try {
    (New-Object -ComObject WScript.Network).SetDefaultPrinter($PrinterDisplayName)
    Write-Host "[OK] Marcada como impresora por defecto en Windows." -ForegroundColor Green
} catch {
    Write-Host "[WARN] No se pudo cambiar la impresora predeterminada automaticamente." -ForegroundColor DarkYellow
}

# -----------------------------------------------------------------------------
# 6. PAGINA DE PRUEBA
# -----------------------------------------------------------------------------
Write-Host ""
$resp = Read-Host "Deseas enviar una pagina de prueba ahora? (S/N) [Por defecto: S]"
if ($resp -eq "" -or $resp.ToUpper().StartsWith("S")) {
    Write-Host "[*] Enviando pagina de prueba al Spooler de impresion..." -ForegroundColor Cyan
    try {
        Start-Process "rundll32.exe" -ArgumentList "printui.dll,PrintUIEntry /k /n `"$PrinterDisplayName`"" -Wait
        Write-Host "[OK] Trabajo de prueba enviado a la impresora con exito." -ForegroundColor Green
    }
    catch {
        "*** Prueba de impresion local Click and Play - $(Get-Date) ***" | Out-Printer -Name $PrinterDisplayName
        Write-Host "[OK] Trabajo enviado." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "      INSTALACION COMPLETADA! LA IMPRESORA YA ESTA LISTA             " -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "  Nombre en Windows:  $PrinterDisplayName" -ForegroundColor White
Write-Host "  Servidor destino:   $IppUrl" -ForegroundColor White
Write-Host "  Controlador usado:  $selectedDriver" -ForegroundColor White
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host ""
Read-Host "Presione Enter para cerrar este instalador..."
