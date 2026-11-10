$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "Print_Server_Pi5.lnk"

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "      DESACTIVAR INICIO AUTOMATICO - PRINT_SERVER_PI5                " -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan

if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Host "[OK] Acceso directo eliminado de la carpeta de Inicio de Windows." -ForegroundColor Green
    Write-Host "Print_Server_Pi5 ya no se iniciara automaticamente al encender el equipo." -ForegroundColor Yellow
} else {
    Write-Host "[*] No se encontro ningun acceso directo configurado en Inicio." -ForegroundColor Gray
}
Write-Host "=====================================================================" -ForegroundColor Cyan
