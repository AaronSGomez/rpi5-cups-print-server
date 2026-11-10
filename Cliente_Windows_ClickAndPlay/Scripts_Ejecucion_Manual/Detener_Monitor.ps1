Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "             DETENER SERVICIO PRINT_SERVER_PI5                       " -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan

$stopped = 0
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "Monitor_Impresora.ps1" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force
    $stopped++
}

if ($stopped -gt 0) {
    Write-Host "[OK] Servicio Print_Server_Pi5 ($stopped proceso(s)) detenido con exito." -ForegroundColor Green
} else {
    Write-Host "[*] Print_Server_Pi5 no se encontraba en ejecucion." -ForegroundColor Yellow
}
Write-Host "=====================================================================" -ForegroundColor Cyan
