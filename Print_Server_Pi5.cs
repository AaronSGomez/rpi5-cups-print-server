using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Media;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace PrintServerPi5
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            bool createdNew;
            using (Mutex mutex = new Mutex(true, "Global\\Print_Server_Pi5_Tray_App", out createdNew))
            {
                if (!createdNew)
                {
                    MessageBox.Show("Print_Server_Pi5 ya está en ejecución en la bandeja del sistema (junto al reloj).",
                        "Print_Server_Pi5", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayApplicationContext(args));
            }
        }
    }

    public class TrayApplicationContext : ApplicationContext
    {
        private NotifyIcon trayIcon;
        private ContextMenuStrip contextMenu;
        private ToolStripMenuItem statusMenuItem;
        private ToolStripMenuItem startupMenuItem;
        private System.Windows.Forms.Timer pollTimer;

        private string serverHost = "192.168.1.40";
        private int serverPort = 631;
        private string queueName = "HP_LaserJet_M14_M17";
        private string configPath;

        private int lastKnownJobId = 0;
        private Dictionary<int, string> trackedJobs = new Dictionary<int, string>();
        private bool wasStopped = false;

        public TrayApplicationContext(string[] args)
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            configPath = Path.Combine(appDir, "ip_servidor.txt");

            LoadServerIp();

            bool forcePrompt = false;
            foreach (string a in args) { if (a == "--prompt-ip" || a == "-p") forcePrompt = true; }
            if (forcePrompt || !File.Exists(configPath))
            {
                PromptForServerIp();
            }

            InitializeComponents();
            StartMonitoring();
        }

        private void LoadServerIp()
        {
            try
            {
                if (File.Exists(configPath))
                {
                    string ip = File.ReadAllText(configPath).Trim();
                    if (!string.IsNullOrEmpty(ip) && !ip.StartsWith("#"))
                    {
                        serverHost = ip;
                    }
                }
            }
            catch {}
        }

        private void SaveServerIp(string ip)
        {
            try
            {
                serverHost = ip.Trim();
                File.WriteAllText(configPath, serverHost);
            }
            catch {}
        }

        private void PromptForServerIp()
        {
            using (Form prompt = new Form())
            {
                prompt.Width = 440;
                prompt.Height = 220;
                prompt.FormBorderStyle = FormBorderStyle.FixedDialog;
                prompt.Text = "Print_Server_Pi5 — Configuración de Servidor";
                prompt.StartPosition = FormStartPosition.CenterScreen;
                prompt.MaximizeBox = false;
                prompt.MinimizeBox = false;

                try {
                    prompt.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                } catch {}

                Label textLabel = new Label() { Left = 20, Top = 20, Width = 380, Height = 40, 
                    Text = "Introduce la dirección IP local de tu Raspberry Pi (servidor CUPS):\n(Ejemplo: 192.168.1.100 o la asignada en tu router)",
                    Font = new Font(prompt.Font, FontStyle.Regular)
                };
                TextBox textBox = new TextBox() { Left = 20, Top = 70, Width = 380, Text = serverHost, Font = new Font(prompt.Font.FontFamily, 10) };
                Button confirmation = new Button() { Text = "Conectar", Left = 180, Width = 100, Top = 120, Height = 32, DialogResult = DialogResult.OK };
                Button cancel = new Button() { Text = "Cancelar", Left = 300, Width = 100, Top = 120, Height = 32, DialogResult = DialogResult.Cancel };

                confirmation.Click += (sender, e) => { prompt.Close(); };
                cancel.Click += (sender, e) => { prompt.Close(); };

                prompt.Controls.Add(textLabel);
                prompt.Controls.Add(textBox);
                prompt.Controls.Add(confirmation);
                prompt.Controls.Add(cancel);
                prompt.AcceptButton = confirmation;
                prompt.CancelButton = cancel;

                if (prompt.ShowDialog() == DialogResult.OK && !string.IsNullOrEmpty(textBox.Text.Trim()))
                {
                    SaveServerIp(textBox.Text.Trim());
                }
            }
        }

        private void InitializeComponents()
        {
            contextMenu = new ContextMenuStrip();

            // Encabezado
            ToolStripMenuItem titleItem = new ToolStripMenuItem("🏴‍☠️ Print_Server_Pi5");
            titleItem.Font = new Font(contextMenu.Font, FontStyle.Bold);
            titleItem.Enabled = false;
            contextMenu.Items.Add(titleItem);

            // Estado actual
            statusMenuItem = new ToolStripMenuItem("Estado: Conectando...");
            statusMenuItem.Enabled = false;
            contextMenu.Items.Add(statusMenuItem);

            contextMenu.Items.Add(new ToolStripSeparator());

            // Acción 1: Reanudar / Desbloquear
            ToolStripMenuItem resumeItem = new ToolStripMenuItem("⚡ Desbloquear y Reanudar Impresora", null, (s, e) => ResumePrinter());
            resumeItem.Font = new Font(contextMenu.Font, FontStyle.Bold);
            contextMenu.Items.Add(resumeItem);

            // Acción 2: Cancelar / Limpiar trabajos
            ToolStripMenuItem cancelJobsItem = new ToolStripMenuItem("🧹 Cancelar trabajos atascados", null, (s, e) => CancelJobs());
            contextMenu.Items.Add(cancelJobsItem);

            // Acción 3: Abrir Web CUPS
            ToolStripMenuItem webItem = new ToolStripMenuItem("📋 Ver Cola de Trabajos (Web CUPS)", null, (s, e) => OpenWebCups());
            contextMenu.Items.Add(webItem);

            contextMenu.Items.Add(new ToolStripSeparator());

            // Acción 4: Cambiar IP
            ToolStripMenuItem changeIpItem = new ToolStripMenuItem("⚙️ Cambiar IP del Servidor...", null, (s, e) => {
                PromptForServerIp();
                UpdateStatusDirectly();
            });
            contextMenu.Items.Add(changeIpItem);

            // Acción 5: Iniciar con Windows
            startupMenuItem = new ToolStripMenuItem("🔄 Iniciar con Windows", null, (s, e) => ToggleStartup());
            startupMenuItem.Checked = IsStartupEnabled();
            contextMenu.Items.Add(startupMenuItem);

            contextMenu.Items.Add(new ToolStripSeparator());

            // Acción 6: Salir
            ToolStripMenuItem exitItem = new ToolStripMenuItem("❌ Salir de Print_Server_Pi5", null, (s, e) => Exit());
            contextMenu.Items.Add(exitItem);

            // Icono en bandeja
            trayIcon = new NotifyIcon();
            trayIcon.Text = "Print_Server_Pi5 — HP LaserJet";
            trayIcon.ContextMenuStrip = contextMenu;
            trayIcon.Visible = true;

            try
            {
                trayIcon.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch
            {
                string iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "pirata.ico");
                if (File.Exists(iconPath)) trayIcon.Icon = new Icon(iconPath);
                else trayIcon.Icon = SystemIcons.Application;
            }

            trayIcon.DoubleClick += (s, e) => OpenWebCups();
        }

        private void StartMonitoring()
        {
            InitLastJobId();

            pollTimer = new System.Windows.Forms.Timer();
            pollTimer.Interval = 3000;
            pollTimer.Tick += (s, e) => CheckPrinterStatus();
            pollTimer.Start();

            ShowNotification("🏴‍☠️ Print_Server_Pi5 Activo", "Vigilando HP LaserJet en " + serverHost, ToolTipIcon.Info);
        }

        private void InitLastJobId()
        {
            new Thread(() => {
                try {
                    string html = FetchHttp("http://" + serverHost + ":" + serverPort + "/jobs?which_jobs=all");
                    if (!string.IsNullOrEmpty(html)) {
                        MatchCollection matches = Regex.Matches(html, @"/printers/[^""]+"">[^<]+</A>-(\d+)");
                        foreach (Match m in matches) {
                            int id = int.Parse(m.Groups[1].Value);
                            if (id > lastKnownJobId) lastKnownJobId = id;
                        }
                    }
                } catch {}
            }).Start();
        }

        private void CheckPrinterStatus()
        {
            new Thread(() => {
                try
                {
                    string pUrl = "http://" + serverHost + ":" + serverPort + "/printers/" + queueName;
                    string pHtml = FetchHttp(pUrl);
                    if (pHtml == null)
                    {
                        UpdateStatus("🔴 Servidor no responde (" + serverHost + ")");
                        return;
                    }

                    Match m = Regex.Match(pHtml, @"printers/" + Regex.Escape(queueName) + @"[^>]*>[^<]+</A>\s*\(([^)]+)\)</H2>", RegexOptions.Singleline);
                    string rawStatus = m.Success ? m.Groups[1].Value.Trim() : "Desconocido";

                    bool isStopped = rawStatus.Contains("parada") || rawStatus.Contains("detenida") || rawStatus.Contains("stopped") || rawStatus.Contains("no aceptando");
                    bool isProcessing = rawStatus.Contains("procesando") || rawStatus.Contains("processing");
                    bool isJam = rawStatus.Contains("atasco") || rawStatus.Contains("jam") || rawStatus.Contains("media-jam");

                    if (isStopped)
                    {
                        UpdateStatus("🔴 DETENIDA: " + (isJam ? "Atasco de papel" : "Cola pausada"));
                        if (!wasStopped)
                        {
                            wasStopped = true;
                            SystemSounds.Hand.Play();
                            ShowNotification("⚠️ ATASCO O ERROR DE IMPRESIÓN",
                                "La impresora se ha detenido. Retira el papel y pulsa 'Desbloquear y Reanudar'.",
                                ToolTipIcon.Error);
                        }
                    }
                    else if (isProcessing)
                    {
                        UpdateStatus("🔵 Imprimiendo documento...");
                    }
                    else
                    {
                        UpdateStatus("🟢 Lista (" + serverHost + ")");
                        if (wasStopped)
                        {
                            wasStopped = false;
                            SystemSounds.Asterisk.Play();
                            ShowNotification("🟢 Impresora Reanudada", "La cola vuelve a estar activa y lista para imprimir.", ToolTipIcon.Info);
                        }
                    }

                    string jHtml = FetchHttp("http://" + serverHost + ":" + serverPort + "/jobs?which_jobs=all");
                    if (!string.IsNullOrEmpty(jHtml))
                    {
                        MatchCollection jMatches = Regex.Matches(jHtml, 
                            @"<A HREF=""/printers/[^""]+"">[^<]+</A>-(\d+)[^<]*</TD>\s*<TD>(.*?)</TD>\s*<TD>(.*?)</TD>\s*<TD>(.*?)</TD>\s*<TD>(.*?)</TD>\s*<TD>(.*?)</TD>",
                            RegexOptions.Singleline);

                        foreach (Match jm in jMatches)
                        {
                            int jId = int.Parse(jm.Groups[1].Value);
                            string jName = jm.Groups[2].Value.Replace("&nbsp;", "").Trim();
                            string jStatus = Regex.Replace(jm.Groups[6].Value, "<[^>]+>", " ").Replace("&nbsp;", "").Trim();

                            if (jId > lastKnownJobId)
                            {
                                lastKnownJobId = jId;
                                trackedJobs[jId] = jStatus;
                                ShowNotification("🖨️ Imprimiendo documento", "Trabajo #" + jId + " en proceso: " + jName, ToolTipIcon.Info);
                            }
                            else if (trackedJobs.ContainsKey(jId))
                            {
                                string prev = trackedJobs[jId];
                                if (jStatus != prev)
                                {
                                    trackedJobs[jId] = jStatus;
                                    if (jStatus.Contains("completado") || jStatus.Contains("completed"))
                                    {
                                        SystemSounds.Asterisk.Play();
                                        ShowNotification("✅ Impresión Completada con Éxito", "El documento #" + jId + " ha salido de la impresora.", ToolTipIcon.Info);
                                        trackedJobs.Remove(jId);
                                    }
                                    else if (jStatus.Contains("parado") || jStatus.Contains("stopped") || jStatus.Contains("error"))
                                    {
                                        SystemSounds.Hand.Play();
                                        ShowNotification("❌ Error en Documento #" + jId, "El trabajo se ha detenido: " + jStatus, ToolTipIcon.Error);
                                        trackedJobs.Remove(jId);
                                    }
                                }
                            }
                        }
                    }
                }
                catch {}
            }).Start();
        }

        private void UpdateStatus(string text)
        {
            if (statusMenuItem != null && contextMenu != null)
            {
                contextMenu.BeginInvoke(new Action(() => {
                    statusMenuItem.Text = "● " + text;
                    trayIcon.Text = "Print_Server_Pi5\n" + (text.Length > 50 ? text.Substring(0, 50) : text);
                }));
            }
        }

        private void UpdateStatusDirectly()
        {
            CheckPrinterStatus();
        }

        private void ShowNotification(string title, string text, ToolTipIcon icon)
        {
            try
            {
                trayIcon.ShowBalloonTip(4500, title, text, icon);
            }
            catch {}
        }

        private void ResumePrinter()
        {
            ShowNotification("Print_Server_Pi5", "Enviando orden de desbloqueo a " + serverHost + "...", ToolTipIcon.Info);
            new Thread(() => {
                bool ok = false;
                try
                {
                    string psScript = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Reanudar_Impresora.ps1");
                    if (File.Exists(psScript))
                    {
                        System.Diagnostics.ProcessStartInfo psi = new System.Diagnostics.ProcessStartInfo();
                        psi.FileName = "powershell.exe";
                        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + psScript + "\"";
                        psi.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;
                        psi.CreateNoWindow = true;
                        System.Diagnostics.Process p = System.Diagnostics.Process.Start(psi);
                        p.WaitForExit(6000);
                        if (p.ExitCode == 0) ok = true;
                    }
                }
                catch {}

                if (!ok)
                {
                    try
                    {
                        string postUrl = "http://" + serverHost + ":" + serverPort + "/printers/" + queueName;
                        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(postUrl);
                        req.Method = "POST";
                        req.ContentType = "application/x-www-form-urlencoded";
                        byte[] data = Encoding.UTF8.GetBytes("org.cups.sid=&OP=start-printer");
                        req.ContentLength = data.Length;
                        using (Stream st = req.GetRequestStream()) { st.Write(data, 0, data.Length); }
                        using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse()) {}
                        ok = true;
                    }
                    catch {}
                }

                Thread.Sleep(1000);
                CheckPrinterStatus();
                ShowNotification("🟢 Impresora Desbloqueada", "Cola de impresión reanudada correctamente.", ToolTipIcon.Info);
            }).Start();
        }

        private void CancelJobs()
        {
            if (MessageBox.Show("¿Deseas cancelar los trabajos de impresión atascados en el servidor?",
                "Cancelar Trabajos — Print_Server_Pi5", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                new Thread(() => {
                    try
                    {
                        string postUrl = "http://" + serverHost + ":" + serverPort + "/printers/" + queueName;
                        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(postUrl);
                        req.Method = "POST";
                        req.ContentType = "application/x-www-form-urlencoded";
                        byte[] data = Encoding.UTF8.GetBytes("org.cups.sid=&OP=purge-jobs");
                        req.ContentLength = data.Length;
                        using (Stream st = req.GetRequestStream()) { st.Write(data, 0, data.Length); }
                        using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse()) {}
                        ShowNotification("🧹 Cola Purgada", "Los trabajos atascados han sido eliminados.", ToolTipIcon.Info);
                        Thread.Sleep(1000);
                        CheckPrinterStatus();
                    }
                    catch (Exception ex)
                    {
                        MessageBox.Show("No se pudieron purgar los trabajos: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                }).Start();
            }
        }

        private void OpenWebCups()
        {
            try
            {
                System.Diagnostics.Process.Start("http://" + serverHost + ":" + serverPort + "/jobs");
            }
            catch {}
        }

        private string FetchHttp(string url)
        {
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
                req.Timeout = 3000;
                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                using (StreamReader sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    return sr.ReadToEnd();
                }
            }
            catch
            {
                return null;
            }
        }

        private bool IsStartupEnabled()
        {
            try
            {
                using (RegistryKey rk = Registry.CurrentUser.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", false))
                {
                    return rk.GetValue("Print_Server_Pi5") != null;
                }
            }
            catch { return false; }
        }

        private void ToggleStartup()
        {
            try
            {
                using (RegistryKey rk = Registry.CurrentUser.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", true))
                {
                    if (IsStartupEnabled())
                    {
                        rk.DeleteValue("Print_Server_Pi5", false);
                        startupMenuItem.Checked = false;
                        ShowNotification("Inicio con Windows", "Se ha desactivado el inicio automático.", ToolTipIcon.Info);
                    }
                    else
                    {
                        string exePath = Application.ExecutablePath;
                        rk.SetValue("Print_Server_Pi5", "\"" + exePath + "\"");
                        startupMenuItem.Checked = true;
                        ShowNotification("Inicio con Windows", "Print_Server_Pi5 se iniciará automáticamente con tu equipo.", ToolTipIcon.Info);
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Error al cambiar configuración de inicio: " + ex.Message);
            }
        }

        private void Exit()
        {
            if (pollTimer != null) pollTimer.Stop();
            if (trayIcon != null)
            {
                trayIcon.Visible = false;
                trayIcon.Dispose();
            }
            Application.Exit();
        }
    }
}
