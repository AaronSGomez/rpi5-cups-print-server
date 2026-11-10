using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Security.Principal;
using System.Text;
using System.Threading;
using Microsoft.Win32;

namespace PrintServerInstaller
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;
            Console.Title = "Instalador Print_Server_Pi5 — HP LaserJet";

            bool isSilent = false;
            foreach (string arg in args)
            {
                if (arg.Equals("/s", StringComparison.OrdinalIgnoreCase) ||
                    arg.Equals("/silent", StringComparison.OrdinalIgnoreCase) ||
                    arg.Equals("-q", StringComparison.OrdinalIgnoreCase))
                {
                    isSilent = true;
                }
            }

            // 1. Auto-elevación a Administrador si es necesario
            if (!IsAdministrator())
            {
                if (!isSilent)
                {
                    Console.ForegroundColor = ConsoleColor.Yellow;
                    Console.WriteLine("[!] Solicitando permisos de Administrador para configurar la impresora...");
                }

                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = Process.GetCurrentProcess().MainModule.FileName;
                    psi.Arguments = isSilent ? "/silent" : "";
                    psi.Verb = "runas";
                    psi.UseShellExecute = true;
                    Process.Start(psi);
                    return;
                }
                catch
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("[X] Se requieren permisos de Administrador para instalar controladores de Windows.");
                    Console.ResetColor();
                    if (!isSilent) Console.ReadLine();
                    return;
                }
            }

            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("=====================================================================");
            Console.WriteLine("            🏴‍☠️  PRINT_SERVER_PI5 — INSTALADOR AUTOMATIZADO 🏴‍☠️       ");
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine("Instalando de forma automatizada:");
            Console.WriteLine("  • Impresora de red HP LaserJet M14-M17 (CUPS IPP)");
            Console.WriteLine("  • Servicio de bandeja del sistema Print_Server_Pi5 con icono pirata");
            Console.WriteLine("  • Notificaciones flotantes y desbloqueo de atascos en 1 clic");
            Console.WriteLine("  • Inicio automático con Windows");
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine();

            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string ipConfigFile = Path.Combine(appDir, "ip_servidor.txt");
            string serverHost = "";

            if (File.Exists(ipConfigFile))
            {
                serverHost = File.ReadAllText(ipConfigFile).Trim();
            }

            // Si hay IP preconfigurada, instalar de forma 100% desatendida
            if (!string.IsNullOrEmpty(serverHost))
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[*] Modo desatendido: Servidor detectado en ip_servidor.txt: " + serverHost);
                Console.ResetColor();
            }
            else
            {
                // Solo si no existe ip_servidor.txt, pedirla una única vez
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("Introduce la dirección IP local de tu Raspberry Pi (servidor CUPS):");
                Console.WriteLine("(Ejemplo: 192.168.1.100 o la IP asignada en tu router)");
                Console.ResetColor();

                while (string.IsNullOrEmpty(serverHost))
                {
                    Console.Write("Dirección IP: ");
                    serverHost = Console.ReadLine().Trim();
                }

                try { File.WriteAllText(ipConfigFile, serverHost); } catch {}
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[OK] IP guardada en ip_servidor.txt");
                Console.ResetColor();
            }

            // 2. Comprobar conectividad
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.Write("[*] Comprobando conexión con " + serverHost + ":631... ");
            if (TestTcp(serverHost, 631))
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[CONECTADO OK]");
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("[Aviso: Puerto 631 no respondió de inmediato, continuando...]");
                Console.ResetColor();
            }

            // 3. Registrar Impresora en Windows Spooler
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[*] Configurando cola de impresión en Windows...");
            Console.ResetColor();

            string printerName = "HP LaserJet M14-M17 (Red Hogar)";
            string portUrl = "http://" + serverHost + ":631/printers/HP_LaserJet_M14_M17";

            string psScript = 
                "$pName = '" + printerName + "'; $port = '" + portUrl + "';\n" +
                "$drivers = Get-PrinterDriver | Select-Object -ExpandProperty Name;\n" +
                "$cand = @('HP LaserJet M14-M17 PCLmS', 'HP LaserJet M14-M17', 'Microsoft IPP Class Driver', 'Microsoft PCL6 Class Driver', 'Generic / Text Only');\n" +
                "$sel = $null; foreach ($c in $cand) { if ($drivers -contains $c) { $sel = $c; break; } };\n" +
                "if (-not $sel) { $sel = $drivers | Where-Object { $_ -match 'IPP' -or $_ -match 'PCL6' } | Select-Object -First 1 };\n" +
                "if (-not $sel) { $sel = 'Generic / Text Only' };\n" +
                "Get-Printer -Name $pName -ErrorAction SilentlyContinue | Remove-Printer -ErrorAction SilentlyContinue;\n" +
                "try { Add-Printer -Name $pName -DriverName $sel -PortName $port -ErrorAction Stop } catch {\n" +
                "  $cmd = '/b \"' + $pName + '\" /x /n \"' + $pName + '\" /if /f \"\" /r \"' + $port + '\" /m \"' + $sel + '\"';\n" +
                "  Start-Process 'rundll32.exe' -ArgumentList ('printui.dll,PrintUIEntry ' + $cmd) -Wait;\n" +
                "}\n" +
                "Write-Host '[OK] Impresora registrada con controlador: ' $sel -ForegroundColor Green;\n";

            RunPowerShell(psScript);

            // 4. Iniciar y registrar Print_Server_Pi5.exe en inicio automático
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[*] Configurando servicio residente de bandeja del sistema...");
            Console.ResetColor();

            string trayExe = Path.Combine(appDir, "Print_Server_Pi5.exe");
            if (File.Exists(trayExe))
            {
                try
                {
                    // Registro en inicio con Windows
                    using (RegistryKey rk = Registry.CurrentUser.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", true))
                    {
                        rk.SetValue("Print_Server_Pi5", "\"" + trayExe + "\"");
                    }

                    // Detener cualquier instancia previa si existiera
                    foreach (Process p in Process.GetProcessesByName("Print_Server_Pi5"))
                    {
                        try { p.Kill(); } catch {}
                    }

                    // Iniciar el monitor
                    Process.Start(new ProcessStartInfo() {
                        FileName = trayExe,
                        WorkingDirectory = appDir
                    });

                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("[OK] Print_Server_Pi5 iniciado en segundo plano junto al reloj.");
                    Console.ResetColor();
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[!] Nota sobre inicio de servicio: " + ex.Message);
                }
            }

            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("=====================================================================");
            Console.WriteLine("     ¡INSTALACIÓN COMPLETADA DE FORMA EXITOSA!                       ");
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine("• Impresora configurada: " + printerName);
            Console.WriteLine("• Servicio activo:      Icono de bandera pirata en la barra de tareas.");
            Console.WriteLine("• En caso de atasco:     Clic derecho en el icono > Desbloquear y Reanudar.");
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine();

            if (!isSilent)
            {
                Console.WriteLine("Finalizando en 3 segundos (o presiona Enter)...");
                int waited = 0;
                while (waited < 30)
                {
                    if (Console.KeyAvailable) { Console.ReadKey(); break; }
                    Thread.Sleep(100);
                    waited++;
                }
            }
        }

        static bool IsAdministrator()
        {
            WindowsIdentity id = WindowsIdentity.GetCurrent();
            WindowsPrincipal principal = new WindowsPrincipal(id);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        static bool TestTcp(string host, int port)
        {
            try
            {
                using (TcpClient client = new TcpClient())
                {
                    IAsyncResult result = client.BeginConnect(host, port, null, null);
                    bool success = result.AsyncWaitHandle.WaitOne(3000);
                    if (!success) return false;
                    client.EndConnect(result);
                    return true;
                }
            }
            catch { return false; }
        }

        static void RunPowerShell(string script)
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"" + script.Replace("\"", "\\\"") + "\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            Process p = Process.Start(psi);
            p.WaitForExit();
        }
    }
}
