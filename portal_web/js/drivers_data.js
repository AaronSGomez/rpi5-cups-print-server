/**
 * PRINT//CORE 5 — Base de Conocimiento de Controladores de Impresión en Linux ARM64
 * Compatibilidad, paquetes Debian y comandos de aprovisionamiento
 */

const PRINTER_DRIVERS_DB = [
    {
        id: "hp-m15-m17",
        brand: "HP",
        family: "LaserJet Pro",
        models: ["HP LaserJet Pro M15a", "HP LaserJet Pro M15w", "HP LaserJet Pro M14-M17", "HP LaserJet MFP M28a", "HP LaserJet MFP M28w"],
        driverType: "HPLIP Nativo (hpcups)",
        debianPackages: ["cups", "hplip", "printer-driver-hpcups"],
        ppdUri: "hplip:0/ppd/hplip/HP/hp-laserjet_m14-m17.ppd",
        connectionUri: "hp:/usb/HP_LaserJet_M14-M17?serial=<SERIAL>",
        quirks: [
            "CRÍTICO: Desactivar 'ipp-usb' (systemctl mask ipp-usb) para evitar error EBUSY en Linux.",
            "Requiere udev rule para desactivar autosuspend en bus USB.",
            "ErrorPolicy en CUPS debe ser 'retry-job' para tolerar el reposo profundo."
        ],
        command: "sudo lpadmin -p HP_LaserJet_M14_M17 -E -v 'hp:/usb/HP_LaserJet_M14-M17' -m 'hplip:0/ppd/hplip/HP/hp-laserjet_m14-m17.ppd' -o printer-error-policy=retry-job"
    },
    {
        id: "hp-p1102-1020",
        brand: "HP",
        family: "LaserJet Clásico (Host-based)",
        models: ["HP LaserJet 1018", "HP LaserJet 1020", "HP LaserJet Pro P1102", "HP LaserJet Pro P1102w", "HP LaserJet P1005", "HP LaserJet P1006"],
        driverType: "foo2zjs / foo2xqx con firmware descargado",
        debianPackages: ["cups", "printer-driver-foo2zjs", "printer-driver-foo2zjs-common"],
        ppdUri: "foo2zjs:0/ppd/foo2zjs/HP-LaserJet_Pro_P1102.ppd",
        connectionUri: "usb://HP/LaserJet%20Professional%20P1102",
        quirks: [
            "Requiere descargar el firmware binario de arranque en cada encendido: 'getweb 1020' o 'getweb P1102'.",
            "Udev rule 85-hplj10xx.rules envía el microcódigo arm2hpdl por USB automáticamente al conectar.",
            "Desactivar 'ipp-usb' para evitar colisiones con el driver de carga de firmware."
        ],
        command: "sudo getweb P1102 && sudo lpadmin -p HP_LaserJet_P1102 -E -v 'usb://HP/LaserJet%20P1102' -m 'foo2zjs:0/ppd/foo2zjs/HP-LaserJet_Pro_P1102.ppd' -o printer-error-policy=retry-job"
    },
    {
        id: "brother-brlaser",
        brand: "Brother",
        family: "HL / DCP Láser Monócromo",
        models: ["Brother HL-L2300D", "Brother HL-L2340DW", "Brother HL-L2320D", "Brother DCP-L2520DW", "Brother DCP-L2540DW", "Brother HL-1110", "Brother HL-1210W"],
        driverType: "Brlaser Open-Source (Ligero & Excelente en ARM64)",
        debianPackages: ["cups", "printer-driver-brlaser"],
        ppdUri: "drv:///brlaser.drv/brl2300d.ppd (según modelo)",
        connectionUri: "usb://Brother/HL-L2300D%20series?serial=<SERIAL>",
        quirks: [
            "Excelente soporte nativo en Debian ARM64 sin necesidad de drivers propietarios x86.",
            "Soporta impresión a doble cara (dúplex) por hardware en modelos 'D'.",
            "Consumo de memoria RAM ultrabajo (< 20 MB durante el renderizado)."
        ],
        command: "sudo apt install printer-driver-brlaser && sudo lpadmin -p Brother_HLL2300D -E -v 'usb://Brother/HL-L2300D' -m 'drv:///brlaser.drv/brl2300d.ppd' -o printer-error-policy=retry-job"
    },
    {
        id: "epson-escpr",
        brand: "Epson",
        family: "EcoTank & WorkForce Inkjet",
        models: ["Epson EcoTank L3150", "Epson EcoTank L3250", "Epson EcoTank ET-2700", "Epson EcoTank ET-2850", "Epson WorkForce WF-2830", "Epson Stylus Photo"],
        driverType: "Epson ESC/P-R Driver",
        debianPackages: ["cups", "printer-driver-escpr"],
        ppdUri: "epson-inkjet-printer-escpr:0/ppd/epson-inkjet-printer-escpr/Epson-L3150_Series.ppd",
        connectionUri: "usb://EPSON/L3150%20Series",
        quirks: [
            "Compatible con perfiles de color e inyección de tinta continua.",
            "Si el modelo soporta Wi-Fi, también se puede emparejar por IPP Everywhere driverless.",
            "Monitoreo de niveles de tinta soportado mediante 'escputil'."
        ],
        command: "sudo apt install printer-driver-escpr && sudo lpadmin -p Epson_EcoTank -E -v 'usb://EPSON/L3150' -m everywhere"
    },
    {
        id: "canon-gutenprint",
        brand: "Canon",
        family: "PIXMA Inyección de Tinta",
        models: ["Canon PIXMA TS3350", "Canon PIXMA MG2550", "Canon PIXMA MG3650", "Canon PIXMA G3000 / G3010", "Canon PIXMA iP7200"],
        driverType: "Gutenprint Alta Fidelidad",
        debianPackages: ["cups", "printer-driver-gutenprint"],
        ppdUri: "gutenprint.5.3://canon-pixma-mg3600/expert",
        connectionUri: "usb://Canon/MG3600%20series",
        quirks: [
            "Gutenprint proporciona calibración milimétrica de color y densidad de gota.",
            "Para modelos de oficina i-SENSYS láser, verificar si requieren driver UFRII o emulación PCL6.",
            "Admite impresión sin bordes fotográfica."
        ],
        command: "sudo apt install printer-driver-gutenprint && sudo lpadmin -p Canon_PIXMA -E -v 'usb://Canon/PIXMA' -m 'gutenprint.5.3://canon-pixma-ts3300/expert'"
    },
    {
        id: "samsung-splix",
        brand: "Samsung",
        family: "Xpress & ML Láser Monócromo",
        models: ["Samsung Xpress M2020", "Samsung Xpress M2020W", "Samsung Xpress M2070", "Samsung ML-1640", "Samsung ML-2160", "Samsung ML-1660"],
        driverType: "Splix (Samsung Printer Language SPL)",
        debianPackages: ["cups", "printer-driver-splix"],
        ppdUri: "splix:0/ppd/splix/samsung/ml2020.ppd",
        connectionUri: "usb://Samsung/M2020%20Series",
        quirks: [
            "Motor de rasterizado SPL de bajo consumo de CPU.",
            "El paquete 'printer-driver-splix' de Debian compila directamente en arquitectura ARM64.",
            "Admite modo de ahorro de tóner configurado en opciones PPD."
        ],
        command: "sudo apt install printer-driver-splix && sudo lpadmin -p Samsung_M2020 -E -v 'usb://Samsung/M2020' -m 'splix:0/ppd/splix/samsung/ml2020.ppd'"
    },
    {
        id: "generic-ipp-everywhere",
        brand: "Estándar Universal",
        family: "Cualquier Impresora Moderna (2015+)",
        models: ["Cualquier impresora con certificación Mopria", "Cualquier impresora Apple AirPrint", "HP / Brother / Canon / Xerox / Ricoh / Lexmark modernas"],
        driverType: "IPP Everywhere (Driverless Puro / PWG Raster / URF / PCLm)",
        debianPackages: ["cups", "cups-filters", "cups-ipp-utils"],
        ppdUri: "-m everywhere (Generado dinámicamente por la impresora)",
        connectionUri: "ipp://<HOST_O_IP>:631/ipp/print o USB IPP",
        quirks: [
            "El futuro de la impresión en Linux: no requiere ningún archivo PPD estático en disco.",
            "La impresora reporta directamente a CUPS sus capacidades de papel, resolución y bandejas.",
            "Cero mantenimiento de drivers en actualizaciones del sistema operativo."
        ],
        command: "sudo lpadmin -p Impresora_Universal -E -v 'ipp://192.168.1.50/ipp/print' -m everywhere -o printer-is-shared=true"
    }
];

if (typeof module !== 'undefined' && module.exports) {
    module.exports = { PRINTER_DRIVERS_DB };
}
