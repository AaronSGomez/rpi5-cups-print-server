#Requires -Version 5.1
<#
=============================================================================
INSTALADOR DE CLIENTE WINDOWS - IMPRESORA HP LASERJET M14-M17 (CUPS / RPi5)
setup_printer_client.ps1
=============================================================================
Configura automaticamente la impresora de red local sobre IPP/CUPS en
equipos Windows 10 y Windows 11.
=============================================================================
#>

[CmdletBinding()]
param(
    [string]$ServerHost = "192.168.1.XXX",
    [int]$ServerPort = 631,
    [string]$QueueName = "HP_LaserJet_M14_M17",
    [string]$PrinterDisplayName = "HP LaserJet M14-M17 (RPi 5 Server)",
    [switch]$SetAsDefault = $false,
    [switch]$SkipTestPage = $false
)

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "  CONFIGURACION DE IMPRESORA CLIENTE (WINDOWS 10 / 11)" -ForegroundColor Cyan
Write-Host "  Servidor CUPS: http://$ServerHost`:$ServerPort/printers/$QueueName" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# 1. VERIFICACION Y AUTO-ELEVACION DE PRIVILEGIOS DE ADMINISTRADOR
# -----------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] Este script requiere permisos de Administrador para instalar controladores y puertos." -ForegroundColor Yellow
    Write-Host "[*] Solicitando elevacion de privilegios (UAC)..." -ForegroundColor Yellow
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# -----------------------------------------------------------------------------
# 2. CARGA DE CONFIGURACION DESDE .env LOCAL (SI EXISTE)
# -----------------------------------------------------------------------------
$envPath = Join-Path $PSScriptRoot ".env"
if (Test-Path $envPath) {
    Write-Host "[*] Leyendo variables desde .env local..." -ForegroundColor DarkGray
    Get-Content $envPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $k = $parts[0].Trim()
            $v = $parts[1].Trim().Trim('"').Trim("'")
            if ($k -eq "RPI_HOST" -and $v) { $ServerHost = $v }
            if ($k -eq "CUPS_PORT" -and $v) { $ServerPort = [int]$v }
            if ($k -eq "PRINTER_QUEUE_NAME" -and $v) { $QueueName = $v }
        }
    }
}

$IppUrl = "http://${ServerHost}:${ServerPort}/printers/${QueueName}"

# -----------------------------------------------------------------------------
# 3. VERIFICACION DE CONECTIVIDAD CON EL SERVIDOR CUPS
# -----------------------------------------------------------------------------
Write-Host "[*] Comprobando conectividad con el servidor $ServerHost en el puerto $ServerPort..." -ForegroundColor Cyan
$testConn = Test-NetConnection -ComputerName $ServerHost -Port $ServerPort -WarningAction SilentlyContinue

if (-not $testConn.TcpTestSucceeded) {
    Write-Host "[X] ERROR: No se puede conectar a $ServerHost en puerto $ServerPort" -ForegroundColor Red
    Write-Host "    - Comprueba que la Raspberry Pi este encendida." -ForegroundColor Yellow
    Write-Host "    - Verifica que el servicio CUPS este ejecutandose (sudo systemctl status cups)." -ForegroundColor Yellow
    Write-Host "    - Asegurate de estar en la misma red local Wi-Fi / Ethernet." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Presione Enter para salir"
    exit 1
}
Write-Host "[OK] Conexion establecida con exito con el servidor CUPS." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. SELECCION INTELIGENTE DEL CONTROLADOR (DRIVER)
# -----------------------------------------------------------------------------
Write-Host "[*] Detectando controladores de impresion compatibles en Windows..." -ForegroundColor Cyan
$availableDrivers = Get-PrinterDriver | Select-Object -ExpandProperty Name

$preferredDrivers = @(
    "HP LaserJet M14-M17 PCLmS",
    "HP LaserJet M14-M17",
    "Microsoft IPP Class Driver",
    "Microsoft PCL6 Class Driver",
    "Universal Print Class Driver",
    "Generic / Text Only"
)

$selectedDriver = $null
foreach ($cand in $preferredDrivers) {
    if ($availableDrivers -contains $cand) {
        $selectedDriver = $cand
        break
    }
}

if (-not $selectedDriver) {
    $selectedDriver = $availableDrivers | Where-Object { $_ -match "IPP" -or $_ -match "PCL6" } | Select-Object -First 1
}

if (-not $selectedDriver) {
    $selectedDriver = "Generic / Text Only"
}

Write-Host "[OK] Controlador seleccionado: '$selectedDriver'" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. CREACION O ACTUALIZACION DE LA COLA DE IMPRESION
# -----------------------------------------------------------------------------
Write-Host "[*] Configurando cola de impresion '$PrinterDisplayName'..." -ForegroundColor Cyan

$existingPrinter = Get-Printer -Name $PrinterDisplayName -ErrorAction SilentlyContinue
if ($existingPrinter) {
    Write-Host "[*] La cola existente '$PrinterDisplayName' sera actualizada..." -ForegroundColor DarkYellow
    Remove-Printer -Name $PrinterDisplayName -ErrorAction SilentlyContinue
}

try {
    Write-Host "[*] Registrando impresora con URL IPP: $IppUrl..." -ForegroundColor Cyan
    Add-Printer -Name $PrinterDisplayName -DriverName $selectedDriver -PortName $IppUrl -ErrorAction Stop
    Write-Host "[OK] Impresora agregada correctamente mediante Add-Printer." -ForegroundColor Green
}
catch {
    Write-Host "[!] Intentando vinculacion alternativa via spooler PrintUI..." -ForegroundColor Yellow
    try {
        $cmdArgs = "/b `"$PrinterDisplayName`" /x /n `"$PrinterDisplayName`" /if /f `"`" /r `"$IppUrl`" /m `"$selectedDriver`""
        Start-Process "rundll32.exe" -ArgumentList "printui.dll,PrintUIEntry $cmdArgs" -Wait
        Write-Host "[OK] Impresora agregada mediante PrintUI." -ForegroundColor Green
    }
    catch {
        Write-Host "[X] ERROR al registrar la impresora: $_" -ForegroundColor Red
        Write-Host "    Puede anadirla manualmente en: Configuracion > Impresoras y escaneres > Agregar impresora" -ForegroundColor Yellow
        Write-Host "    Seleccione 'La impresora no esta en la lista' -> 'Seleccionar una impresora compartida por nombre'" -ForegroundColor Yellow
        Write-Host "    Pegue la URL: $IppUrl" -ForegroundColor Yellow
        exit 1
    }
}

# -----------------------------------------------------------------------------
# 6. CONFIGURAR COMO PREDETERMINADA (OPCIONAL)
# -----------------------------------------------------------------------------
if ($SetAsDefault) {
    Write-Host "[*] Estableciendo '$PrinterDisplayName' como predeterminada..." -ForegroundColor Cyan
    (New-Object -ComObject WScript.Network).SetDefaultPrinter($PrinterDisplayName)
    Write-Host "[OK] Impresora predeterminada actualizada." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 7. ENVIO DE PAGINA DE PRUEBA
# -----------------------------------------------------------------------------
if (-not $SkipTestPage) {
    Write-Host ""
    $resp = Read-Host "¿Desea enviar una pagina de prueba ahora a la impresora? (S/N) [Por defecto: S]"
    if ($resp -eq "" -or $resp.ToUpper().StartsWith("S")) {
        Write-Host "[*] Enviando pagina de prueba de Windows..." -ForegroundColor Cyan
        try {
            Start-Process "rundll32.exe" -ArgumentList "printui.dll,PrintUIEntry /k /n `"$PrinterDisplayName`"" -Wait
            Write-Host "[OK] Comando de pagina de prueba enviado al Spooler de Windows." -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Enviando texto directo de prueba..." -ForegroundColor Yellow
            "Prueba de Impresion Windows -> Servidor RPi5 CUPS - $(Get-Date)" | Out-Printer -Name $PrinterDisplayName
        }
    }
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "  CONFIGURACION DE CLIENTE WINDOWS COMPLETADA CON EXITO" -ForegroundColor Green
Write-Host "  Nombre de cola local: $PrinterDisplayName" -ForegroundColor White
Write-Host "  Destino IPP:          $IppUrl" -ForegroundColor White
Write-Host "  Controlador en uso:   $selectedDriver" -ForegroundColor White
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host ""
Read-Host "Presione Enter para finalizar..."
