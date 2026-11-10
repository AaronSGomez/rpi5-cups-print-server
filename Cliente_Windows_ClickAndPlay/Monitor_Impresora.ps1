[CmdletBinding()]
param(
    [string]$ServerHost = "",
    [int]$ServerPort = 631,
    [string]$QueueName = "HP_LaserJet_M14_M17",
    [switch]$TestOnly = $false
)

<#
=============================================================================
MONITOR DE NOTIFICACIONES DE IMPRESIÓN (WINDOWS 10 / 11) - CLICK & PLAY
Print_Server_Pi5 - Monitor_Impresora.ps1 (Versión Universal / Lectores)
=============================================================================
Monitoriza en segundo plano el servidor CUPS (Raspberry Pi) en la red local:
 - Notificación Toast cuando empieza una impresión
 - Notificación Toast cuando la página sale con éxito
 - Alerta roja sonora ante atasco de papel o bloqueo de la cola
 - Registro de actividad en monitor.log
 - Detección y solicitud dinámica de IP del servidor
=============================================================================
#>

# 1. VERIFICAR INSTANCIA ÚNICA (MUTEX)
$mutexName = "Global\Print_Server_Pi5_ClickAndPlay_Mutex"
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew -and -not $TestOnly) {
    Write-Host "[!] Print_Server_Pi5 ya se encuentra en ejecución en segundo plano." -ForegroundColor Yellow
    exit 0
}

# 2. CARGA O SOLICITUD DE LA IP DEL SERVIDOR
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$ipConfigFile = Join-Path $scriptDir "ip_servidor.txt"

if (-not $ServerHost -and (Test-Path $ipConfigFile)) {
    $c = (Get-Content $ipConfigFile -Raw).Trim()
    if ($c -and -not $c.StartsWith("#")) {
        $ServerHost = $c
    }
}

# Si aún no hay IP definida, solicitarla interactivamente
if (-not $ServerHost) {
    # Intentar por consola si hay terminal interactivo
    if ([Environment]::UserInteractive -and [Console]::WindowHeight -gt 0) {
        Write-Host "=====================================================================" -ForegroundColor Yellow
        Write-Host "      CONFIGURACION PRINT_SERVER_PI5 - SERVIDOR DE IMPRESION         " -ForegroundColor Yellow
        Write-Host "=====================================================================" -ForegroundColor Yellow
        Write-Host "Por favor, introduce la direccion IP local de tu Raspberry Pi:" -ForegroundColor White
        while (-not $ServerHost) {
            $ServerHost = (Read-Host "Direccion IP (ej: 192.168.1.100)").Trim()
        }
    } else {
        # Fallback gráfico con InputBox si se ejecutó en segundo plano o sin consola
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic
            $ServerHost = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Introduce la direccion IP local de la Raspberry Pi (servidor CUPS):",
                "Print_Server_Pi5 - Configuracion Inicial",
                "192.168.1.100"
            ).Trim()
        } catch {
            $ServerHost = "192.168.1.100"
        }
    }

    if ($ServerHost) {
        Set-Content -Path $ipConfigFile -Value $ServerHost -Force
    }
}

$logFile = Join-Path $scriptDir "monitor.log"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

# 3. MOTOR DE NOTIFICACIONES TOAST (WINDOWS 10 / 11)
function Send-PrintToast {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")][string]$Type = "Info"
    )

    Write-Log "NOTIFICACIÓN [$Type]: $Title - $Message"

    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
        $texts = $xml.GetElementsByTagName("text")
        $texts.Item(0).AppendChild($xml.CreateTextNode($Title)) | Out-Null
        $texts.Item(1).AppendChild($xml.CreateTextNode($Message)) | Out-Null

        if ($Type -eq "Error" -or $Type -eq "Warning") {
            try { [System.Media.SystemSounds]::Hand.Play() } catch {}
        } elseif ($Type -eq "Success") {
            try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
        }

        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe')
        $notifier.Show($toast)
        return $true
    }
    catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            $icon = [System.Windows.Forms.ToolTipIcon]::Info
            if ($Type -eq "Error" -or $Type -eq "Warning") { $icon = [System.Windows.Forms.ToolTipIcon]::Error }
            elseif ($Type -eq "Success") { $icon = [System.Windows.Forms.ToolTipIcon]::Info }
            
            $notify = New-Object System.Windows.Forms.NotifyIcon
            $notify.Icon = [System.Drawing.SystemIcons]::Information
            $notify.Visible = $true
            $notify.ShowBalloonTip(5000, $Title, $Message, $icon)
            Start-Sleep -Seconds 2
            $notify.Dispose()
            return $true
        }
        catch {
            Write-Log "Error al mostrar notificación: $_"
            return $false
        }
    }
}

# 4. CONSULTA AL SERVIDOR CUPS
function Get-CupsPrinterStatus {
    $uri = "http://${ServerHost}:${ServerPort}/printers/${QueueName}"
    try {
        $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        $html = $resp.Content
        $statusPattern = 'printers/' + [regex]::Escape($QueueName) + '[^>]*>[^<]+</A>\s*\(([^)]+)\)</H2>'
        if ($html -match $statusPattern) {
            $raw = $matches[1].Trim()
            $isStopped = ($raw -match "parada" -or $raw -match "detenida" -or $raw -match "stopped" -or $raw -match "no aceptando")
            $isProcessing = ($raw -match "procesando" -or $raw -match "processing")
            $isJam = ($raw -match "atasco" -or $raw -match "jam" -or $raw -match "media-jam")
            return [PSCustomObject]@{
                Raw = $raw
                IsStopped = $isStopped
                IsProcessing = $isProcessing
                IsJam = $isJam
                Online = $true
            }
        }
        return [PSCustomObject]@{ Raw = "Desconocido"; IsStopped = $false; IsProcessing = $false; IsJam = $false; Online = $true }
    }
    catch {
        return [PSCustomObject]@{ Raw = "Sin conexion"; IsStopped = $false; IsProcessing = $false; IsJam = $false; Online = $false }
    }
}

function Get-CupsRecentJobs {
    $uri = "http://${ServerHost}:${ServerPort}/jobs?which_jobs=all"
    try {
        $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        $html = $resp.Content
        $pattern = '<A HREF="/printers/[^"]+">[^<]+</A>-(\d+)[^<]*</TD>\s*<TD>(.*?)</TD>\s*<TD>(.*?)</TD>\s*<TD>(.*?)</TD>\s*<TD>(.*?)</TD>\s*<TD>(.*?)</TD>'
        $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $matches = $regex.Matches($html)
        $jobs = @()
        foreach ($m in $matches) {
            $jobs += [PSCustomObject]@{
                Id = [int]$m.Groups[1].Value
                Name = ($m.Groups[2].Value -replace '&nbsp;','').Trim()
                User = ($m.Groups[3].Value -replace '&nbsp;','').Trim()
                Size = ($m.Groups[4].Value -replace '&nbsp;','').Trim()
                Pages = ($m.Groups[5].Value -replace '&nbsp;','').Trim()
                Status = ($m.Groups[6].Value -replace '<BR>',' ' -replace '&nbsp;','' -replace '\s+',' ').Trim()
            }
        }
        return $jobs
    }
    catch {
        return @()
    }
}

# 5. MODO DE PRUEBA RÁPIDA (-TestOnly)
if ($TestOnly) {
    Write-Host "[*] Enviando notificaciones de prueba al escritorio..." -ForegroundColor Cyan
    Send-PrintToast -Title "Print_Server_Pi5 - Test" -Message "Monitor conectado correctamente a $ServerHost." -Type "Info"
    Start-Sleep -Seconds 2
    Send-PrintToast -Title "Impresión Completada" -Message "Página de prueba finalizada con éxito." -Type "Success"
    Start-Sleep -Seconds 2
    Send-PrintToast -Title "Alerta de Impresora" -Message "Simulación: Atasco de papel detectado." -Type "Error"
    Write-Host "[OK] Pruebas finalizadas." -ForegroundColor Green
    exit 0
}

# 6. BUCLE PRINCIPAL DE MONITORIZACIÓN
Write-Log "Print_Server_Pi5 iniciado para $QueueName en ${ServerHost}:${ServerPort}"
Send-PrintToast -Title "Print_Server_Pi5 Activo" -Message "Vigilando cola de impresión en $ServerHost." -Type "Info"

$initialJobs = Get-CupsRecentJobs
$lastKnownJobId = 0
if ($initialJobs.Count -gt 0) {
    $lastKnownJobId = ($initialJobs | Measure-Object -Property Id -Maximum).Maximum
}

$trackedJobs = @{}
$wasStopped = $false

try {
    while ($true) {
        $pStatus = Get-CupsPrinterStatus
        $recentJobs = Get-CupsRecentJobs

        # A) Detección de atasco / detención de la cola
        if ($pStatus.Online) {
            if ($pStatus.IsStopped -and -not $wasStopped) {
                $wasStopped = $true
                $desc = if ($pStatus.IsJam) { "¡Atasco de papel detectado en la impresora!" } else { "La cola de impresión se ha detenido por fallo o atasco." }
                Send-PrintToast -Title "⚠️ ATASCO O ERROR DE IMPRESIÓN" -Message "$desc Retira el papel y haz doble clic en 'REANUDAR_IMPRESORA'." -Type "Error"
            }
            elseif (-not $pStatus.IsStopped -and $wasStopped) {
                $wasStopped = $false
                Send-PrintToast -Title "🟢 Impresora Lista y Reanudada" -Message "La cola vuelve a estar activa y lista para imprimir." -Type "Success"
            }
        }

        # B) Seguimiento de trabajos
        foreach ($job in $recentJobs) {
            if ($job.Id -gt $lastKnownJobId) {
                $lastKnownJobId = $job.Id
                $trackedJobs[$job.Id] = $job.Status
                Send-PrintToast -Title "🖨️ Imprimiendo documento" -Message "Trabajo #${($job.Id)} en proceso: '$($job.Name)' ($($job.Pages) pág)." -Type "Info"
            }
            elseif ($trackedJobs.ContainsKey($job.Id)) {
                $prevStatus = $trackedJobs[$job.Id]
                if ($job.Status -ne $prevStatus) {
                    $trackedJobs[$job.Id] = $job.Status

                    if ($job.Status -match "completado" -or $job.Status -match "completed") {
                        Send-PrintToast -Title "✅ Impresión Completada con Éxito" -Message "El trabajo #${($job.Id)} ha salido correctamente de la impresora." -Type "Success"
                        $trackedJobs.Remove($job.Id)
                    }
                    elseif ($job.Status -match "parado" -or $job.Status -match "stopped" -or $job.Status -match "error" -or $job.Status -match "aborted") {
                        Send-PrintToast -Title "❌ Error en Trabajo #${($job.Id)}" -Message "El trabajo se ha detenido o ha fallado: $($job.Status)" -Type "Error"
                        $trackedJobs.Remove($job.Id)
                    }
                    elseif ($job.Status -match "cancelado" -or $job.Status -match "canceled") {
                        Send-PrintToast -Title "ℹ️ Trabajo #${($job.Id)} Cancelado" -Message "La impresión ha sido cancelada." -Type "Info"
                        $trackedJobs.Remove($job.Id)
                    }
                }
            }
        }

        if ($trackedJobs.Count -gt 0 -or $pStatus.IsProcessing) {
            Start-Sleep -Milliseconds 1500
        } else {
            Start-Sleep -Seconds 3
        }
    }
}
finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
    Write-Log "Print_Server_Pi5 finalizado."
}
