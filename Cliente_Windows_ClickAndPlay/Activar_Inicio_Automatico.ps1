$vbsPath = Join-Path $PSScriptRoot "Print_Server_Pi5.vbs"
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "Print_Server_Pi5.lnk"

# Verificar si hay IP guardada; si no, solicitarla
$ipFile = Join-Path $PSScriptRoot "ip_servidor.txt"
if (-not (Test-Path $ipFile)) {
    Write-Host "Introduce la direccion IP local de tu Raspberry Pi:" -ForegroundColor Yellow
    $ip = (Read-Host "Direccion IP").Trim()
    if ($ip) { Set-Content -Path $ipFile -Value $ip -Force }
}

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $vbsPath
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = "Servicio Print_Server_Pi5 - Monitor de Impresion HP LaserJet"
$shortcut.Save()

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "        ACTIVAR INICIO AUTOMATICO - SERVICIO PRINT_SERVER_PI5        " -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "[OK] Acceso directo registrado en la carpeta de Inicio de Windows:" -ForegroundColor Green
Write-Host "     $shortcutPath" -ForegroundColor White
Write-Host ""
Write-Host "A partir de ahora, Print_Server_Pi5 se iniciara de forma transparente" -ForegroundColor Green
Write-Host "en segundo plano cada vez que inicies sesion en este equipo." -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Cyan
