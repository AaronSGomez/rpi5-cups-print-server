/**
 * PRINT//CORE 5 — LÓGICA INTERACTIVA Y EXPERIENCIA DE USUARIO
 * Motor de búsqueda de drivers, consola interactiva, inspector de nodos y tabs
 */

document.addEventListener("DOMContentLoaded", () => {
    initThemeToggle();
    initTopologyInspector();
    initDriverSearchEngine();
    initOsTabs();
    initInteractiveTerminal();
    initClipboardCopy();
    initCupsNodeConnector();
});

/* -----------------------------------------------------------------------------
   1. GESTIÓN DE TEMA (LIGHT TECHNICAL PAPER / HIGH-CONTRAST OLED)
   ----------------------------------------------------------------------------- */
function initThemeToggle() {
    const toggleBtn = document.getElementById("theme-toggle-btn");
    const currentTheme = localStorage.getItem("printcore_theme") || "light";
    
    if (currentTheme === "dark") {
        document.documentElement.setAttribute("data-theme", "dark");
        if (toggleBtn) toggleBtn.textContent = "[ LIGHT THEME ]";
    }

    if (toggleBtn) {
        toggleBtn.addEventListener("click", () => {
            const isDark = document.documentElement.getAttribute("data-theme") === "dark";
            if (isDark) {
                document.documentElement.removeAttribute("data-theme");
                localStorage.setItem("printcore_theme", "light");
                toggleBtn.textContent = "[ DARK THEME ]";
            } else {
                document.documentElement.setAttribute("data-theme", "dark");
                localStorage.setItem("printcore_theme", "dark");
                toggleBtn.textContent = "[ LIGHT THEME ]";
            }
        });
    }
}

/* -----------------------------------------------------------------------------
   2. INSPECTOR DE ARQUITECTURA Y TOPOLOGÍA DE HARDWARE
   ----------------------------------------------------------------------------- */
const TOPOLOGY_DATA = {
    cups: {
        tag: "NÚCLEO DE IMPRESIÓN // PUERTO 631",
        title: "CUPS 2.4.x (Common UNIX Printing System)",
        content: "Servidor de colas centralizado con protocolo IPP/2.1. Escucha en todas las interfaces de red locales (Port 631) permitiendo a clientes Windows, Linux y Android enviar trabajos crudos (RAW), PWG-Raster o PCLmS sin autenticación restrictiva mediante directivas 'Allow @LOCAL'.",
        specs: [
            { label: "Directorio Conf", value: "/etc/cups/cupsd.conf" },
            { label: "Política de Error", value: "ErrorPolicy retry-job" },
            { label: "Servicio Systemd", value: "cups.service (active)" },
            { label: "Sockets", value: "0.0.0.0:631 & [::]:631" }
        ]
    },
    usb: {
        tag: "INTERFAZ FÍSICA // HARDWARE KERNEL",
        title: "Bus USB 2.0 / 3.0 & Mitigación Udev",
        content: "La serie HP LaserJet M14-M17 (Vendor: 03f0) apaga su controlador tras minutos de reposo. Se implementa una regla udev para fijar power/control='on' y power/autosuspend='-1'. Crucialmente, se desactiva y enmascara el demonio 'ipp-usb' para evitar el bloqueo exclusivo EBUSY.",
        specs: [
            { label: "Device ID", value: "ID 03f0:be2a (HP M14-M17)" },
            { label: "Regla Udev", value: "/etc/udev/rules.d/99-hp-no-autosuspend.rules" },
            { label: "Control de Energía", value: "power/control = on (-1)" },
            { label: "Daemon ipp-usb", value: "MASKED (systemctl mask ipp-usb)" }
        ]
    },
    avahi: {
        tag: "DESCUBRIMIENTO ZERO-CONFIG // DNS-SD 5353",
        title: "Avahi Daemon (mDNS / AirPrint / Mopria)",
        content: "Difunde el anuncio del servicio de impresión mediante Multicast DNS (puerto 5353 UDP) en el dominio '.local'. Permite a dispositivos móviles Android e iOS detectar la impresora de forma instantánea sin requerir drivers ni configuración manual de IPs.",
        specs: [
            { label: "Protocolo", value: "DNS-SD / mDNS (_ipp._tcp, _pdl-datastream._tcp)" },
            { label: "Puerto Multicast", value: "5353 / UDP" },
            { label: "Archivo Conf", value: "/etc/avahi/avahi-daemon.conf" },
            { label: "Compatibilidad", value: "Apple AirPrint & Android Mopria" }
        ]
    },
    samba: {
        tag: "COMPATIBILIDAD WINDOWS // PUERTO 445",
        title: "Samba 4.x (Spooler SMB y Point-and-Print)",
        content: "Mapea automáticamente las colas de CUPS como recursos compartidos SMB (\\\192.168.1.XXX\\HP_LaserJet_M14_M17). Permite que equipos Windows antiguos o clientes sin soporte IPP nativo se conecten mediante el protocolo tradicional de compartición de archivos e impresoras.",
        specs: [
            { label: "Puerto SMB", value: "445/tcp y 139/tcp" },
            { label: "Directorio Spool", value: "/var/spool/samba (Permisos 1777)" },
            { label: "Directorio Drivers", value: "/var/lib/samba/printers" },
            { label: "Archivo Conf", value: "/etc/samba/smb.conf ([printers])" }
        ]
    },
    firewall: {
        tag: "SEGURIDAD PERIMETRAL // UFW LINUX",
        title: "Firewall UFW con Aislamiento LAN",
        content: "Garantiza que la Raspberry Pi 5 exponga los servicios de impresión únicamente a las subredes privadas locales (192.168.0.0/16 y 10.0.0.0/8), cerrando cualquier vector hacia interfaces externas o conexiones no autorizadas.",
        specs: [
            { label: "Regla IPP", value: "ALLOW from 192.168.0.0/16 to 631/tcp" },
            { label: "Regla Samba", value: "ALLOW from 192.168.0.0/16 to 445/tcp, 139/tcp" },
            { label: "Regla mDNS", value: "ALLOW to any 5353/udp" },
            { label: "Estado Firewall", value: "ufw status: ACTIVE" }
        ]
    }
};

function initTopologyInspector() {
    const nodes = document.querySelectorAll(".blueprint-node");
    const tagEl = document.getElementById("inspector-tag");
    const titleEl = document.getElementById("inspector-title");
    const contentEl = document.getElementById("inspector-content");
    const specsEl = document.getElementById("inspector-specs");

    if (!nodes.length) return;

    nodes.forEach(node => {
        node.addEventListener("click", () => {
            nodes.forEach(n => n.classList.remove("active"));
            node.classList.add("active");

            const nodeId = node.getAttribute("data-node");
            const data = TOPOLOGY_DATA[nodeId];

            if (data) {
                tagEl.textContent = data.tag;
                titleEl.textContent = data.title;
                contentEl.textContent = data.content;

                let specsHtml = "";
                data.specs.forEach(spec => {
                    specsHtml += `
                        <div class="inspector-specs-item">
                            <span class="spec-label">${spec.label}:</span>
                            <span class="spec-value">${spec.value}</span>
                        </div>
                    `;
                });
                specsEl.innerHTML = specsHtml;
            }
        });
    });
}

/* -----------------------------------------------------------------------------
   3. MOTOR DE BÚSQUEDA Y FILTRO DE DRIVERS (PRINTER_DRIVERS_DB)
   ----------------------------------------------------------------------------- */
function initDriverSearchEngine() {
    const searchInput = document.getElementById("driver-search-input");
    const chips = document.querySelectorAll(".brand-chip");
    const gridContainer = document.getElementById("drivers-results-grid");

    if (!gridContainer || typeof PRINTER_DRIVERS_DB === "undefined") return;

    let selectedBrand = "ALL";
    let searchQuery = "";

    function renderDrivers() {
        gridContainer.innerHTML = "";

        const filtered = PRINTER_DRIVERS_DB.filter(driver => {
            const matchesBrand = selectedBrand === "ALL" || driver.brand.toUpperCase() === selectedBrand.toUpperCase();
            const textToSearch = `${driver.brand} ${driver.family} ${driver.models.join(" ")} ${driver.driverType} ${driver.debianPackages.join(" ")}`.toLowerCase();
            const matchesQuery = !searchQuery || textToSearch.includes(searchQuery.toLowerCase());
            return matchesBrand && matchesQuery;
        });

        if (filtered.length === 0) {
            gridContainer.innerHTML = `
                <div style="grid-column: 1 / -1; padding: 3rem; text-align: center; border: 2px dashed var(--border-strong); background: var(--bg-surface);">
                    <p style="font-family: var(--font-mono); font-size: 1.1rem; color: var(--accent-vermilion); font-weight: 700;">
                        [!] NO SE ENCONTRARON MODELOS COINCIDENTES
                    </p>
                    <p style="color: var(--ink-secondary); margin-top: 0.5rem; font-size: 0.9rem;">
                        Prueba buscando 'LaserJet', 'Brother', 'EcoTank', 'Gutenprint' o 'everywhere'.
                    </p>
                </div>
            `;
            return;
        }

        filtered.forEach(item => {
            const card = document.createElement("div");
            card.className = "driver-result-card";
            card.innerHTML = `
                <div>
                    <div class="driver-card-header">
                        <span class="driver-brand-badge">${item.brand} // ${item.family}</span>
                        <span style="font-family: var(--font-mono); font-size: 0.72rem; color: var(--ink-muted);">${item.models.length} modelos</span>
                    </div>
                    <h3 class="driver-model-title">${item.models[0]}</h3>
                    <p style="font-size: 0.85rem; color: var(--ink-secondary); margin-bottom: 0.75rem;">
                        <strong>Driver:</strong> ${item.driverType}
                    </p>
                    <div class="driver-packages-tag">
                        <strong>Paquetes:</strong> ${item.debianPackages.join(", ")}
                    </div>
                    <ul class="driver-quirks-list">
                        ${item.quirks.map(q => `<li>${q}</li>`).join("")}
                    </ul>
                </div>
                <div>
                    <div style="font-family: var(--font-mono); font-size: 0.7rem; color: var(--ink-muted); margin-bottom: 0.25rem;">
                        COMANDO DE APROVISIONAMIENTO CUPS:
                    </div>
                    <div class="driver-command-box">
                        <code>${item.command}</code>
                        <button class="copy-cmd-btn" data-copy="${encodeURIComponent(item.command)}">COPIAR</button>
                    </div>
                </div>
            `;
            gridContainer.appendChild(card);
        });

        // Vincular botones copiar generados dinámicamente
        initDynamicCopyButtons();
    }

    if (searchInput) {
        searchInput.addEventListener("input", (e) => {
            searchQuery = e.target.value.trim();
            renderDrivers();
        });
    }

    chips.forEach(chip => {
        chip.addEventListener("click", () => {
            chips.forEach(c => c.classList.remove("active"));
            chip.classList.add("active");
            selectedBrand = chip.getAttribute("data-brand") || "ALL";
            renderDrivers();
        });
    });

    renderDrivers();
}

/* -----------------------------------------------------------------------------
   4. PESTAÑAS DE CONFIGURACIÓN DE CLIENTES (WINDOWS / ANDROID / IOS)
   ----------------------------------------------------------------------------- */
function initOsTabs() {
    const tabs = document.querySelectorAll(".os-tab-btn");
    const panels = document.querySelectorAll(".os-tab-content-panel");

    if (!tabs.length || !panels.length) return;

    tabs.forEach(tab => {
        tab.addEventListener("click", () => {
            tabs.forEach(t => t.classList.remove("active"));
            panels.forEach(p => p.classList.remove("active"));

            tab.classList.add("active");
            const targetId = tab.getAttribute("data-tab");
            const targetPanel = document.getElementById(targetId);
            if (targetPanel) {
                targetPanel.classList.add("active");
            }
        });
    });
}

/* -----------------------------------------------------------------------------
   5. CONSOLA DE DIAGNÓSTICO INTERACTIVA
   ----------------------------------------------------------------------------- */
const TERMINAL_OUTPUTS = {
    "lpstat -p -d -v": 
`la impresora HP_LaserJet_M14_M17 está inactiva. activada desde lun 09 nov 2026 11:18:28
destino predeterminado del sistema: HP_LaserJet_M14_M17
dispositivo para HP_LaserJet_M14_M17: hp:/usb/HP_LaserJet_M14-M17?serial=03F0_BE2A_SER
dispositivo para PDF: cups-pdf:/
planificador de tareas (cupsd): EJECUTÁNDOSE [OK]`,

    "driverless":
`ipp://HP%20LaserJet%20M15a%20(EF3E58)%20(USB)._ipp._tcp.local/
ipp://PDF%20Virtual%20Printer._ipp._tcp.local/`,

    "lsusb":
`Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 001 Device 002: ID 03f0:be2a HP, Inc HP LaserJet M14-M17
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 003 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 004 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub`,

    "sudo hp-probe -b usb":
`HP Linux Imaging and Printing System (ver. 3.22.10)
Printer Discovery Utility ver. 4.1
--------------------
| DEVICE DISCOVERY |
--------------------
  Device URI                                     Model              
  ---------------------------------------------  -------------------
  hp:/usb/HP_LaserJet_M14-M17?serial=03F0_BE2A_SER  HP LaserJet M14-M17
Found 1 printer(s) on the 'usb' bus. Done.`,

    "sudo systemctl status cups avahi-daemon smbd":
`● cups.service - CUPS Scheduler
     Loaded: loaded (/usr/lib/systemd/system/cups.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-11-09 10:55:08 CET; 1h 25min ago

● avahi-daemon.service - Avahi mDNS/DNS-SD Stack
     Loaded: loaded (/usr/lib/systemd/system/avahi-daemon.service; enabled)
     Active: active (running) (Port 5353/udp open - AirPrint & Mopria broadcast)

● smbd.service - Samba SMB Daemon
     Loaded: loaded (/usr/lib/systemd/system/smbd.service; enabled)
     Active: active (running) (Port 445/tcp open - Spooler [printers] shared)`,

    "cups_unstick_queue.sh":
`[+] Verificando estado de colas en el planificador...
[+] Reanudando colas pausadas: 'HP_LaserJet_M14_M17'...
[OK] cupsenable HP_LaserJet_M14_M17: éxito.
[OK] cupsaccept HP_LaserJet_M14_M17: éxito.
[OK] Estado actual: lista para recibir trabajos desde la red.`
};

function initInteractiveTerminal() {
    const cmdButtons = document.querySelectorAll(".term-cmd-btn");
    const terminalOutput = document.getElementById("terminal-output-container");

    if (!cmdButtons.length || !terminalOutput) return;

    cmdButtons.forEach(btn => {
        btn.addEventListener("click", () => {
            const cmd = btn.getAttribute("data-cmd");
            const output = TERMINAL_OUTPUTS[cmd] || `orden ejecutada: ${cmd}\n[OK]`;

            terminalOutput.innerHTML += `
                <div class="terminal-prompt-line">
                    <span style="color:#60A5FA;">admin@raspberrypi</span>:<span style="color:#FBBF24;">~</span>$ <strong>${cmd}</strong>
                </div>
                <div class="terminal-output-block">${output}</div>
            `;
            terminalOutput.scrollTop = terminalOutput.scrollHeight;
        });
    });
}

/* -----------------------------------------------------------------------------
   6. UTILIDAD DE COPIADO AL PORTAPAPELES
   ----------------------------------------------------------------------------- */
function initClipboardCopy() {
    document.querySelectorAll("[data-copy-target]").forEach(btn => {
        btn.addEventListener("click", () => {
            const targetId = btn.getAttribute("data-copy-target");
            const el = document.getElementById(targetId);
            if (el) {
                navigator.clipboard.writeText(el.textContent.trim()).then(() => {
                    const originalText = btn.textContent;
                    btn.textContent = "COPIADO [OK]";
                    btn.style.background = "#10B981";
                    setTimeout(() => {
                        btn.textContent = originalText;
                        btn.style.background = "";
                    }, 2000);
                });
            }
        });
    });
}

function initDynamicCopyButtons() {
    document.querySelectorAll(".copy-cmd-btn").forEach(btn => {
        btn.addEventListener("click", () => {
            const rawCmd = decodeURIComponent(btn.getAttribute("data-copy"));
            navigator.clipboard.writeText(rawCmd).then(() => {
                const originalText = btn.textContent;
                btn.textContent = "COPIADO";
                btn.style.background = "#10B981";
                setTimeout(() => {
                    btn.textContent = originalText;
                    btn.style.background = "";
                }, 1800);
            });
        });
    });
}


/* -----------------------------------------------------------------------------
   7. GESTOR DE NODO LOCAL & ACCESO A COLAS (LOCALSTORAGE SOVEREIGN PRIVACY)
   ----------------------------------------------------------------------------- */
function initCupsNodeConnector() {
    const ipInput = document.getElementById("cups-node-ip-input");
    const saveBtn = document.getElementById("save-node-ip-btn");
    const clearBtn = document.getElementById("clear-node-ip-btn");
    const btnJobs = document.getElementById("btn-open-jobs");
    const btnPrinter = document.getElementById("btn-open-printer");
    const statusBadge = document.getElementById("cups-node-status-badge");

    if (!ipInput) return;

    // Cargar IP guardada previamente en el navegador del usuario (sin fuga pública)
    const savedIp = localStorage.getItem("printcore_node_ip") || "";
    if (savedIp) {
        ipInput.value = savedIp;
        updateBadge(savedIp);
    }

    function updateBadge(ip) {
        if (!statusBadge) return;
        if (ip) {
            statusBadge.textContent = `● NODO CONFIGURADO: http://${ip}:631`;
            statusBadge.style.color = "#10B981";
            if (clearBtn) clearBtn.style.display = "inline-flex";
        } else {
            statusBadge.textContent = "○ NODO NO ASIGNADO // ALMACENAMIENTO LOCAL VACÍO";
            statusBadge.style.color = "var(--ink-muted)";
            if (clearBtn) clearBtn.style.display = "none";
        }
    }

    function saveIp() {
        let val = ipInput.value.trim().replace(/^https?:\/\//, "").replace(/\/.*$/, "").replace(/:631.*$/, "");
        if (val) {
            localStorage.setItem("printcore_node_ip", val);
            ipInput.value = val;
            updateBadge(val);
            if (saveBtn) {
                const orig = saveBtn.textContent;
                saveBtn.textContent = "[ GUARDADO ✓ ]";
                saveBtn.style.background = "#10B981";
                saveBtn.style.color = "#FFFFFF";
                setTimeout(() => {
                    saveBtn.textContent = orig;
                    saveBtn.style.background = "";
                    saveBtn.style.color = "";
                }, 1800);
            }
            return val;
        } else {
            localStorage.removeItem("printcore_node_ip");
            updateBadge("");
            return "";
        }
    }

    if (saveBtn) {
        saveBtn.addEventListener("click", saveIp);
    }

    if (clearBtn) {
        clearBtn.addEventListener("click", () => {
            localStorage.removeItem("printcore_node_ip");
            ipInput.value = "";
            updateBadge("");
            ipInput.focus();
        });
    }

    ipInput.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
            saveIp();
        }
    });

    function navigateTo(path) {
        let ip = ipInput.value.trim() || localStorage.getItem("printcore_node_ip");
        if (!ip) {
            ip = prompt("Introduce la IP local o hostname de tu Raspberry Pi (ej: 192.168.1.100 o printserver.local):");
            if (ip) {
                ip = ip.trim().replace(/^https?:\/\//, "").replace(/\/.*$/, "").replace(/:631.*$/, "");
                ipInput.value = ip;
                saveIp();
            } else {
                return;
            }
        } else {
            saveIp();
        }
        window.open(`http://${ip}:631${path}`, "_blank", "noopener,noreferrer");
    }

    if (btnJobs) {
        btnJobs.addEventListener("click", (e) => {
            e.preventDefault();
            navigateTo("/jobs/");
        });
    }

    if (btnPrinter) {
        btnPrinter.addEventListener("click", (e) => {
            e.preventDefault();
            navigateTo("/printers/HP_LaserJet_M14_M17");
        });
    }
}
