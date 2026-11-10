using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32;

namespace PrintServerInstaller
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;
            Console.Title = "Instalador Print_Server_Pi5 — HP LaserJet";

            // 1. Comprobación y auto-elevación a Administrador
            if (!IsAdministrator())
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("[!] Solicitando permisos de Administrador para instalar la impresora...");
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = Process.GetCurrentProcess().MainModule.FileName;
                    psi.Verb = "runas";
                    psi.UseShellExecute = true;
                    Process.Start(psi);
                    return;
                }
                catch
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("[X] Se requieren permisos de Administrador para configurar controladores.");
                    Console.ResetColor();
                    Console.ReadLine();
                    return;
                }
            }

            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("=====================================================================");
            Console.WriteLine("            🏴‍☠️  PRINT_SERVER_PI5 — INSTALADOR TODO EN UNO  🏴‍☠️       ");
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine();
            Console.WriteLine("Este instalador configurará automáticamente en tu equipo:");
            Console.WriteLine("  1. Impresora HP LaserJet M14-M17 compartida por CUPS (Red Local).");
            Console.WriteLine("  2. Monitor de bandeja del sistema (System Tray) con icono pirata.");
            Console.WriteLine("  3. Notificaciones Toast nativas (En proceso, Éxito, Atascos).");
            Console.WriteLine("  4. Desbloqueo y reanudación de cola en 1 clic (sin comandos).");
            Console.WriteLine("  5. Inicio automático con Windows.");
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

            if (!string.IsNullOrEmpty(serverHost))
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[*] Servidor preconfigurado detectado: " + serverHost);
                Console.ResetColor();
                Console.Write("¿Deseas usar esta IP? (Enter para Sí, o escribe una nueva IP): ");
                string custom = Console.ReadLine().Trim();
                if (!string.IsNullOrEmpty(custom)) serverHost = custom;
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("Por favor, introduce la dirección IP local de tu Raspberry Pi:");
                Console.WriteLine("(Ejemplo habitual: 192.168.1.100 o la IP asignada en tu router)");
                Console.ResetColor();

                while (string.IsNullOrEmpty(serverHost))
                {
                    Console.Write("Dirección IP: ");
                    serverHost = Console.ReadLine().Trim();
                }
            }

            // Comprobar conectividad
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.Write("[*] Comprobando conexión con " + serverHost + ":631... ");
            if (TestTcp(serverHost, 631))
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[OK - CONECTADO]");
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("[AVISO: El puerto 631 no respondió de inmediato, continuando...]");
                Console.ResetColor();
            }

            // Guardar en ip_servidor.txt
            try { File.WriteAllText(ipConfigFile, serverHost); } catch {}

            // 2. Instalación de la Impresora en Windows Spooler
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[*] Registrando impresora en Windows...");
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
                "Write-Host '[OK] Impresora configurada con controlador: ' $sel -ForegroundColor Green;\n";

            RunPowerShell(psScript);

            // 3. Registrar Print_Server_Pi5.exe en inicio automático
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[*] Configurando inicio automático del servicio de bandeja...");
            Console.ResetColor();

            string trayExe = Path.Combine(appDir, "Print_Server_Pi5.exe");
            if (File.Exists(trayExe))
            {
                try
                {
                    using (RegistryKey rk = Registry.CurrentUser.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", true))
                    {
                        rk.SetValue("Print_Server_Pi5", "\"" + trayExe + "\"");
                    }
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("[OK] Print_Server_Pi5 registrado para arrancar con Windows.");
                    Console.ResetColor();

                    // Iniciar el monitor inmediatamente
                    Process.Start(new ProcessStartInfo() {
                        FileName = trayExe,
                        WorkingDirectory = appDir
                    });
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("[OK] Monitor de bandeja iniciado correctamente junto al reloj.");
                    Console.ResetColor();
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[!] Nota sobre inicio automático: " + ex.Message);
                }
            }

            // 4. Preguntar página de prueba
            Console.WriteLine();
            Console.Write("¿Deseas enviar una página de prueba a la impresora ahora? (S/N) [Por defecto: S]: ");
            string resp = Console.ReadLine().Trim().ToUpper();
            if (resp == "" || resp.StartsWith("S"))
            {
                Console.WriteLine("[*] Enviando página de prueba...");
                RunPowerShell("Start-Process 'rundll32.exe' -ArgumentList 'printui.dll,PrintUIEntry /k /n \"" + printerName + "\"' -Wait;");
            }

            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("=====================================================================");
            Console.WriteLine("      ¡INSTALACIÓN COMPLETADA CON ÉXITO!                             ");
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine("• Impresora lista: " + printerName);
            Console.WriteLine("• Monitor activo:  Busca el icono pirata junto al reloj de Windows.");
            Console.WriteLine("• En caso de atasco: Clic derecho en el icono > Desbloquear y Reanudar.");
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine();
            Console.WriteLine("Presiona Enter para finalizar...");
            Console.ReadLine();
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
            psi.CreateNoWindow = false;
            Process p = Process.Start(psi);
            p.WaitForExit();
        }
    }
}
