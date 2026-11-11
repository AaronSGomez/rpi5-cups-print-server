using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Reflection;
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
                    Console.WriteLine("[!] Solicitando permisos de Administrador para instalar en el sistema...");
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
                    Console.WriteLine("[X] Se requieren permisos de Administrador para instalar controladores y servicios.");
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
            Console.WriteLine("Instalando permanentemente en este PC:");
            Console.WriteLine("  1. Impresora de red HP LaserJet M14-M17 (CUPS IPP).");
            Console.WriteLine("  2. Despliegue de archivos en C:\\Program Files\\Print_Server_Pi5\\.");
            Console.WriteLine("  3. Servicio residente de bandeja (System Tray) con icono pirata.");
            Console.WriteLine("  4. Notificaciones flotantes y desbloqueo de atascos en 1 clic.");
            Console.WriteLine("  5. Acceso directo en el Menú Inicio y arranque con Windows.");
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine();

            string currentDir = AppDomain.CurrentDomain.BaseDirectory;
            string localIpFile = Path.Combine(currentDir, "ip_servidor.txt");
            string serverHost = "";

            if (File.Exists(localIpFile))
            {
                serverHost = File.ReadAllText(localIpFile).Trim();
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
                // Solo si no existe ip_servidor.txt, solicitarla
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("Introduce la dirección IP local de tu Raspberry Pi (servidor CUPS):");
                Console.WriteLine("(Ejemplo habitual: 192.168.1.100 o la IP asignada en tu router)");
                Console.ResetColor();

                while (string.IsNullOrEmpty(serverHost))
                {
                    Console.Write("Dirección IP: ");
                    serverHost = Console.ReadLine().Trim();
                }

                try { File.WriteAllText(localIpFile, serverHost); } catch {}
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[OK] IP guardada para el instalador.");
                Console.ResetColor();
            }

            // 2. Comprobar conectividad con CUPS
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

            // 3. Crear directorio permanente en C:\Program Files\Print_Server_Pi5
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[*] Instalando archivos en el disco duro del PC...");
            Console.ResetColor();

            // Detener cualquier instancia previa antes de copiar/sobrescribir ejecutables
            StopExistingService();

            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string targetDir = Path.Combine(programFiles, "Print_Server_Pi5");
            try
            {
                try
                {
                    if (!Directory.Exists(targetDir)) Directory.CreateDirectory(targetDir);
                }
                catch
                {
                    string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                    targetDir = Path.Combine(localAppData, "Print_Server_Pi5");
                    if (!Directory.Exists(targetDir)) Directory.CreateDirectory(targetDir);
                }

                // Desplegar binarios principales (desde recurso incrustado o desde carpeta actual)
                DeployBundledFile("Print_Server_Pi5.exe", Path.Combine(currentDir, "Print_Server_Pi5.exe"), Path.Combine(targetDir, "Print_Server_Pi5.exe"));
                DeployBundledFile("pirata.ico", Path.Combine(currentDir, "pirata.ico"), Path.Combine(targetDir, "pirata.ico"));
                File.WriteAllText(Path.Combine(targetDir, "ip_servidor.txt"), serverHost);

                // Limpiar posible override antiguo en LocalAppData si existiera para usar la IP recién instalada
                try
                {
                    string userOverride = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "Print_Server_Pi5",
                        "ip_servidor.txt"
                    );
                    if (File.Exists(userOverride) && !string.Equals(Path.GetFullPath(userOverride), Path.GetFullPath(Path.Combine(targetDir, "ip_servidor.txt")), StringComparison.OrdinalIgnoreCase))
                    {
                        File.WriteAllText(userOverride, serverHost);
                    }
                }
                catch {}

                // Copiar scripts de ejecución manual si existen
                string manualSrc = Path.Combine(currentDir, "Scripts_Ejecucion_Manual");
                string manualDst = Path.Combine(targetDir, "Scripts_Ejecucion_Manual");
                if (Directory.Exists(manualSrc))
                {
                    if (!Directory.Exists(manualDst)) Directory.CreateDirectory(manualDst);
                    foreach (string f in Directory.GetFiles(manualSrc))
                    {
                        File.Copy(f, Path.Combine(manualDst, Path.GetFileName(f)), true);
                    }
                }

                // Generar script de desinstalación permanente en la carpeta de destino
                string uninstallerBat = Path.Combine(targetDir, "DESINSTALAR.bat");
                string uninstallerContent = 
                    "@echo off\r\n" +
                    "net session >nul 2>&1\r\n" +
                    "if %errorLevel% neq 0 (\r\n" +
                    "    powershell -Command \"Start-Process '%~f0' -Verb RunAs\"\r\n" +
                    "    exit /b\r\n" +
                    ")\r\n" +
                    "echo [*] Deteniendo servicio...\r\n" +
                    "taskkill /f /im Print_Server_Pi5.exe >nul 2>&1\r\n" +
                    "reg delete \"HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run\" /v \"Print_Server_Pi5\" /f >nul 2>&1\r\n" +
                    "reg delete \"HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run\" /v \"Print_Server_Pi5\" /f /reg:64 >nul 2>&1\r\n" +
                    "echo [*] Retirando impresora...\r\n" +
                    "powershell -NoProfile -Command \"Remove-Printer -Name 'HP LaserJet M14-M17 (Red Hogar)' -ErrorAction SilentlyContinue\"\r\n" +
                    "del \"%ProgramData%\\Microsoft\\Windows\\Start Menu\\Programs\\Print_Server_Pi5.lnk\" >nul 2>&1\r\n" +
                    "echo [OK] Impresora y servicio Print_Server_Pi5 desinstalados correctamente.\r\n" +
                    "pause\r\n";
                File.WriteAllText(uninstallerBat, uninstallerContent);

                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[OK] Archivos desplegados con éxito en: " + targetDir);
                Console.ResetColor();
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("[!] Nota sobre copia de archivos: " + ex.Message);
                Console.ResetColor();
                targetDir = currentDir; // Fallback al directorio actual
            }

            // 4. Registrar Impresora en Windows Spooler
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[*] Registrando impresora en Windows Spooler...");
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

            // 5. Crear acceso directo en el Menú Inicio de Windows
            try
            {
                string startMenu = Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms);
                string shortcutPath = Path.Combine(startMenu, "Print_Server_Pi5.lnk");
                string installedExe = Path.Combine(targetDir, "Print_Server_Pi5.exe");
                string installedIcon = Path.Combine(targetDir, "pirata.ico");

                string vbsShortcutScript = 
                    "$wsh = New-Object -ComObject WScript.Shell;\n" +
                    "$s = $wsh.CreateShortcut('" + shortcutPath.Replace("'", "''") + "');\n" +
                    "$s.TargetPath = '" + installedExe.Replace("'", "''") + "';\n" +
                    "$s.WorkingDirectory = '" + targetDir.Replace("'", "''") + "';\n" +
                    "$s.Description = 'Print_Server_Pi5 — HP LaserJet Monitor';\n" +
                    (File.Exists(installedIcon) ? "$s.IconLocation = '" + installedIcon.Replace("'", "''") + "';\n" : "") +
                    "$s.Save();\n";
                RunPowerShell(vbsShortcutScript);

                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[OK] Acceso directo registrado en el Menú Inicio de Windows.");
                Console.ResetColor();
            }
            catch {}

            // 6. Iniciar y registrar Print_Server_Pi5.exe en inicio automático con Windows
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("[*] Configurando servicio residente de bandeja del sistema...");
            Console.ResetColor();

            string targetTrayExe = Path.Combine(targetDir, "Print_Server_Pi5.exe");
            bool startupConfigured = false;
            bool serviceStarted = false;

            if (File.Exists(targetTrayExe))
            {
                // 6a. Registrar inicio automático para todos los usuarios en HKLM (vista 64 bits)
                try
                {
                    using (RegistryKey baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                    using (RegistryKey rk = baseKey.CreateSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run"))
                    {
                        rk.SetValue("Print_Server_Pi5", "\"" + targetTrayExe + "\" --startup");
                        startupConfigured = true;
                    }

                    // Limpiar posible duplicado en HKCU
                    try
                    {
                        using (RegistryKey hkcuBase = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
                        using (RegistryKey hkcuRun = hkcuBase.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", true))
                        {
                            if (hkcuRun != null) hkcuRun.DeleteValue("Print_Server_Pi5", false);
                        }
                    }
                    catch {}
                }
                catch
                {
                    try
                    {
                        using (RegistryKey hkcuBase = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
                        using (RegistryKey rk = hkcuBase.CreateSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run"))
                        {
                            rk.SetValue("Print_Server_Pi5", "\"" + targetTrayExe + "\" --startup");
                            startupConfigured = true;
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.ForegroundColor = ConsoleColor.Yellow;
                        Console.WriteLine("[!] No se pudo registrar el inicio automático: " + ex.Message);
                        Console.ResetColor();
                    }
                }

                if (startupConfigured)
                {
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("[OK] Inicio automático con Windows registrado correctamente.");
                    Console.ResetColor();
                }

                // 6b. Asegurar que no quede ninguna instancia previa y lanzar en la sesión de usuario
                StopExistingService();

                try
                {
                    // Lanzar mediante explorer.exe para que corra sin elevación en la sesión gráfica del usuario activo
                    Process.Start(new ProcessStartInfo() {
                        FileName = "explorer.exe",
                        Arguments = "\"" + targetTrayExe + "\"",
                        UseShellExecute = true
                    });
                    for (int i = 0; i < 8; i++)
                    {
                        Thread.Sleep(250);
                        if (Process.GetProcessesByName("Print_Server_Pi5").Length > 0)
                        {
                            serviceStarted = true;
                            break;
                        }
                    }
                }
                catch {}

                if (!serviceStarted)
                {
                    try
                    {
                        Process.Start(new ProcessStartInfo() {
                            FileName = targetTrayExe,
                            Arguments = "--startup",
                            WorkingDirectory = targetDir,
                            UseShellExecute = true
                        });
                        for (int i = 0; i < 6; i++)
                        {
                            Thread.Sleep(250);
                            if (Process.GetProcessesByName("Print_Server_Pi5").Length > 0)
                            {
                                serviceStarted = true;
                                break;
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.ForegroundColor = ConsoleColor.Yellow;
                        Console.WriteLine("[!] Nota sobre inicio de servicio: " + ex.Message);
                        Console.ResetColor();
                    }
                }

                if (serviceStarted)
                {
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("[OK] Print_Server_Pi5 iniciado en segundo plano junto al reloj.");
                    Console.ResetColor();
                }
                else
                {
                    Console.ForegroundColor = ConsoleColor.Yellow;
                    Console.WriteLine("[!] No se pudo confirmar el arranque automático de Print_Server_Pi5. Puedes abrirlo desde el Menú Inicio.");
                    Console.ResetColor();
                }
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("[X] ERROR: No se encontró Print_Server_Pi5.exe para instalar el servicio de bandeja.");
                Console.ResetColor();
            }

            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("=====================================================================");
            Console.WriteLine("     ¡INSTALACIÓN COMPLETADA DE FORMA EXITOSA!                       ");
            Console.WriteLine("=====================================================================");
            Console.ResetColor();
            Console.WriteLine("• Ruta de instalación:  " + targetDir);
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

        static void StopExistingService()
        {
            foreach (Process p in Process.GetProcessesByName("Print_Server_Pi5"))
            {
                try
                {
                    p.Kill();
                    p.WaitForExit(3000);
                }
                catch {}
            }
        }

        static void DeployBundledFile(string resourceName, string fallbackSrcPath, string dstPath)
        {
            try
            {
                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream resStream = asm.GetManifestResourceStream(resourceName))
                {
                    if (resStream != null)
                    {
                        using (FileStream fs = new FileStream(dstPath, FileMode.Create, FileAccess.Write))
                        {
                            resStream.CopyTo(fs);
                        }
                        return;
                    }
                }
            }
            catch {}

            CopyFileIfExists(fallbackSrcPath, dstPath);
        }

        static void CopyFileIfExists(string src, string dst)
        {
            try {
                if (File.Exists(src)) File.Copy(src, dst, true);
            } catch {}
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
