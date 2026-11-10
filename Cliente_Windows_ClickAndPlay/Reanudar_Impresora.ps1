[CmdletBinding()]
param(
    [string]$ServerHost = "",
    [string]$QueueName = "HP_LaserJet_M14_M17",
    [string]$User = ""
)

$ipFile = Join-Path $PSScriptRoot "ip_servidor.txt"
if (-not $ServerHost -and (Test-Path $ipFile)) {
    $c = (Get-Content $ipFile -Raw).Trim()
    if ($c) { $ServerHost = $c }
}

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "     REANUDAR Y DESBLOQUEAR COLA DE IMPRESION HP LASERJET            " -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan

if (-not $ServerHost) {
    Write-Host "Introduce la direccion IP local de la Raspberry Pi:" -ForegroundColor Yellow
    while (-not $ServerHost) {
        $ServerHost = (Read-Host "Direccion IP (ej: 192.168.1.100)").Trim()
    }
    Set-Content -Path $ipFile -Value $ServerHost -Force
}

if (-not $User) {
    $User = (Read-Host "Usuario SSH de la Raspberry Pi [por defecto: pi]").Trim()
    if (-not $User) { $User = "pi" }
}

Write-Host "[*] Conectando con servidor Raspberry Pi ($User@$ServerHost)..." -ForegroundColor Yellow

$cmd = "sudo cupsenable $QueueName && sudo cupsaccept $QueueName"
$res = & ssh.exe -o StrictHostKeyChecking=no -o ConnectTimeout=8 "${User}@${ServerHost}" $cmd 2>&1

function Send-QuickToast {
    param([string]$Title, [string]$Message)
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
        $texts = $xml.GetElementsByTagName("text")
        $texts.Item(0).AppendChild($xml.CreateTextNode($Title)) | Out-Null
        $texts.Item(1).AppendChild($xml.CreateTextNode($Message)) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe')
        $notifier.Show($toast)
    } catch {}
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Cola de impresion reanudada con exito." -ForegroundColor Green
    Send-QuickToast -Title "🟢 Impresora Reanudada" -Message "La cola $QueueName ha sido desbloqueada y ya acepta trabajos."
} else {
    Write-Host "[!] Respuesta del servidor: $res" -ForegroundColor DarkYellow
    Send-QuickToast -Title "HP LaserJet" -Message "Orden de reanudacion transmitida a la Raspberry Pi."
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "Proceso completado. Ya puedes volver a imprimir." -ForegroundColor White
Write-Host "=====================================================================" -ForegroundColor Green
