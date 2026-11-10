#!/usr/bin/env bash
# =============================================================================
# SERVIDOR DE IMPRESIÓN CENTRALIZADO — RASPBERRY PI 5 (ARM64 / DEBIAN)
# Script de Despliegue Automatizado e Idempotente para HP LaserJet M14-M17
# =============================================================================
# Soporte: CUPS, HPLIP (Plugin propietario), Avahi (mDNS / AirPrint / Mopria), Samba
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 0. VARIABLES Y CONSTANTES
# -----------------------------------------------------------------------------
PRINTER_QUEUE_NAME="${PRINTER_QUEUE_NAME:-HP_LaserJet_M14_M17}"
PRINTER_DESCRIPTION="${PRINTER_DESCRIPTION:-HP LaserJet Pro M14-M17 USB}"
PRINTER_LOCATION="${PRINTER_LOCATION:-Raspberry Pi 5 Server}"
CUPS_PORT=631
SAMBA_WORKGROUP="${SAMBA_WORKGROUP:-WORKGROUP}"

# Detección del usuario real que invoca sudo
REAL_USER="${SUDO_USER:-$USER}"
if [ "$REAL_USER" = "root" ]; then
    REAL_USER="tu_usuario" # Fallback por defecto en Pi 5
fi

# Colores para salida estructurada
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

echo -e "${CYAN}${BOLD}"
echo "====================================================================="
echo "   DESPLIEGUE SERVIDOR DE IMPRESIÓN — RASPBERRY PI 5 (ARM64)"
echo "   Impresora: HP LaserJet M14-M17 (HPLIP / IPP Everywhere / SMB)"
echo "====================================================================="
echo -e "${NC}"

# -----------------------------------------------------------------------------
# 1. VERIFICACIÓN DE PRIVILEGIOS
# -----------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log_error "Este script debe ejecutarse con privilegios root (sudo)."
    exit 1
fi

log_info "Usuario administrador asignado: ${BOLD}${REAL_USER}${NC}"
log_info "Cola de impresión objetivo:   ${BOLD}${PRINTER_QUEUE_NAME}${NC}"

# -----------------------------------------------------------------------------
# 2. INSTALACIÓN DE PAQUETES DEL SISTEMA
# -----------------------------------------------------------------------------
log_info "Actualizando índices de paquetes e instalando dependencias..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -y

REQUIRED_PACKAGES=(
    cups
    cups-client
    cups-bsd
    cups-filters
    printer-driver-cups-pdf
    printer-driver-hpcups
    printer-driver-foo2zjs
    hplip
    hplip-data
    avahi-daemon
    avahi-utils
    samba
    smbclient
    libnss-mdns
    usbutils
    wget
    curl
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        log_success "Paquete ya instalado: $pkg"
    else
        log_info "Instalando paquete: $pkg..."
        apt-get install -y --no-install-recommends "$pkg"
    fi
done

# -----------------------------------------------------------------------------
# 3. ASIGNACIÓN DE GRUPOS DE ADMINISTRACIÓN DE IMPRESIÓN
# -----------------------------------------------------------------------------
log_info "Configurando membresía en grupos lpadmin y lp para '${REAL_USER}'..."
usermod -aG lpadmin,lp "$REAL_USER"
log_success "Usuario '${REAL_USER}' añadido a lpadmin y lp."

# -----------------------------------------------------------------------------
# 4. CONFIGURACIÓN IDEMPOTENTE DE CUPS (/etc/cups/cupsd.conf)
# -----------------------------------------------------------------------------
log_info "Configurando servidor CUPS (/etc/cups/cupsd.conf)..."

CUPSD_CONF="/etc/cups/cupsd.conf"
CUPSD_BACKUP="/etc/cups/cupsd.conf.orig"

if [ ! -f "$CUPSD_BACKUP" ]; then
    cp "$CUPSD_CONF" "$CUPSD_BACKUP"
    log_info "Copia de respaldo creada en: $CUPSD_BACKUP"
fi

# Generamos una configuración limpia, segura y abierta a la red local
cat << 'EOF' > "$CUPSD_CONF"
# Configuración CUPS generada automáticamente por setup_cups_server.sh
LogLevel warn
PageLogFormat
MaxLogSize 10m
ErrorPolicy retry-job

# Escucha en el puerto estándar 631 en todas las interfaces
Port 631
Listen /run/cups/cups.sock

# Delegamos la difusión mDNS a Avahi (evita anuncios IPPS con TLS autofirmado que bloquean Android/Mopria)
Browsing On
BrowseLocalProtocols none

# Compartir impresoras por defecto
DefaultShared Yes

# Acepta peticiones dirigidas a cualquier hostname o IP local
ServerAlias *

# Política de autenticación sin forzar cifrado TLS en red local
DefaultAuthType Basic
DefaultEncryption Never

# Tamaño de papel estándar europeo e Interfaz Web de administración
DefaultPaperSize A4
WebInterface Yes

<Location />
  Order allow,deny
  Allow @LOCAL
  Allow 127.0.0.1
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
</Location>

<Location /admin>
  Order allow,deny
  Allow @LOCAL
  Allow 127.0.0.1
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
</Location>

<Location /admin/conf>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow @LOCAL
  Allow 127.0.0.1
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
</Location>

<Location /admin/log>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow @LOCAL
  Allow 127.0.0.1
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
</Location>

<Policy default>
  JobPrivateAccess default
  JobPrivateValues default
  SubscriptionPrivateAccess default
  SubscriptionPrivateValues default

  <Limit Create-Job Print-Job Print-URI Validate-Job>
    Order deny,allow
  </Limit>

  <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Current-Job Suspend-Current-Job Resume-Job Cancel-My-Jobs Close-Job CUPS-Move-Job CUPS-Get-Document>
    Require user @OWNER @SYSTEM
    Order deny,allow
  </Limit>

  <Limit CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Get-Devices>
    AuthType Default
    Require user @SYSTEM
    Order deny,allow
  </Limit>

  <Limit Pause-Printer Resume-Printer Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs Deactivate-Printer Activate-Printer Restart-Printer Shutdown-Printer Startup-Printer Promote-Job Schedule-Job-After Cancel-Jobs CUPS-Accept-Jobs CUPS-Reject-Jobs>
    AuthType Default
    Require user @SYSTEM
    Order deny,allow
  </Limit>

  <Limit Cancel-Job CUPS-Authenticate-Job>
    Require user @OWNER @SYSTEM
    Order deny,allow
  </Limit>

  <Limit All>
    Order deny,allow
  </Limit>
</Policy>
EOF

log_success "Archivo /etc/cups/cupsd.conf configurado correctamente."

# -----------------------------------------------------------------------------
# 5. MITIGACIÓN DE SLEEP Y BLOQUEO USB (UDEV + DESACTIVACIÓN IPP-USB)
# -----------------------------------------------------------------------------
log_info "Desactivando ipp-usb para evitar bloqueo exclusivo del bus USB (EBUSY)..."
systemctl stop ipp-usb 2>/dev/null || true
systemctl disable ipp-usb 2>/dev/null || true
systemctl mask ipp-usb 2>/dev/null || true

log_info "Configurando regla udev para desactivar autosuspend USB en HP (Vendor 03f0)..."

UDEV_RULE_FILE="/etc/udev/rules.d/99-hp-no-autosuspend.rules"
cat << 'EOF' > "$UDEV_RULE_FILE"
# Desactivar autosuspensión USB para impresoras HP (Vendor ID: 03f0)
# Evita que la HP LaserJet M14-M17 pase a deep sleep y deje la cola 'Stopped'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="03f0", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="03f0", ATTR{power/autosuspend}="-1"
ACTION=="change", SUBSYSTEM=="usb", ATTR{idVendor}=="03f0", ATTR{power/control}="on"
ACTION=="change", SUBSYSTEM=="usb", ATTR{idVendor}=="03f0", ATTR{power/autosuspend}="-1"
EOF

udevadm control --reload-rules || true
udevadm trigger --subsystem-match=usb || true
log_success "Regla udev aplicada para prevenir desconexión por standby."

# -----------------------------------------------------------------------------
# 6. INSTALACIÓN DEL PLUGIN PROPIETARIO HPLIP (NO INTERACTIVO)
# -----------------------------------------------------------------------------
log_info "Verificando estado del plugin binario de HP..."

# Intentar instalar plugin en modo no interactivo
if which hp-plugin &>/dev/null; then
    log_info "Ejecutando hp-plugin en modo no interactivo..."
    # hp-plugin -i -q descarga e instala automáticamente
    hp-plugin -i -q || hp-plugin -i -n || log_warn "hp-plugin no completó automáticamente. Si la impresora requiere plugin binario, puede ejecutarse 'hp-plugin -i' interactivamente."
else
    log_warn "Comando hp-plugin no encontrado. Continuando..."
fi

# -----------------------------------------------------------------------------
# 7. CONFIGURACIÓN DE SAMBA (/etc/samba/smb.conf)
# -----------------------------------------------------------------------------
log_info "Configurando Samba para compartición nativa Windows..."

mkdir -p /var/spool/samba
chmod 1777 /var/spool/samba
mkdir -p /var/lib/samba/printers
chmod 0755 /var/lib/samba/printers

SMB_CONF="/etc/samba/smb.conf"
SMB_BACKUP="/etc/samba/smb.conf.orig"

if [ ! -f "$SMB_BACKUP" ] && [ -f "$SMB_CONF" ]; then
    cp "$SMB_CONF" "$SMB_BACKUP"
    log_info "Copia de respaldo de smb.conf creada."
fi

# Verificamos si ya existe la directiva de impresión CUPS en smb.conf
if ! grep -q "printing = cups" "$SMB_CONF" 2>/dev/null; then
    log_info "Inyectando configuración CUPS/Samba en $SMB_CONF..."
    cat << EOF >> "$SMB_CONF"

# --- CONFIGURACIÓN SERVIDOR IMPRESIÓN CUPS (Automático) ---
[global]
   workgroup = ${SAMBA_WORKGROUP}
   server string = Servidor de Impresion RPi5
   security = user
   map to guest = Bad User
   load printers = yes
   printing = cups
   printcap name = cups

[printers]
   comment = All Printers
   browseable = yes
   path = /var/spool/samba
   printable = yes
   guest ok = yes
   read only = yes
   create mask = 0700

[print$]
   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = yes
   read only = yes
   guest ok = yes
# ---------------------------------------------------------
EOF
    log_success "Sección [printers] y [print$] agregadas a smb.conf."
else
    log_success "Samba ya cuenta con directivas CUPS configuradas."
fi

# -----------------------------------------------------------------------------
# 8. CONFIGURACIÓN DE AVAHI (mDNS / DNS-SD / ZERO-CONFIG AIRPRINT & MOPRIA)
# -----------------------------------------------------------------------------
log_info "Configurando Avahi Daemon (/etc/avahi/avahi-daemon.conf)..."

AVAHI_CONF="/etc/avahi/avahi-daemon.conf"
if [ -f "$AVAHI_CONF" ]; then
    sed -i 's/^#*use-ipv4=.*/use-ipv4=yes/' "$AVAHI_CONF"
    sed -i 's/^#*use-ipv6=.*/use-ipv6=yes/' "$AVAHI_CONF"
    sed -i 's/^#*enable-dbus=.*/enable-dbus=yes/' "$AVAHI_CONF"
    # Restringir Avahi a la interfaz cableada eth0 para evitar colisiones con Wi-Fi (wlan0) o puentes Docker
    sed -i '/^allow-interfaces=/d' "$AVAHI_CONF"
    sed -i '/^\[server\]/a allow-interfaces=eth0' "$AVAHI_CONF"
fi

# Generación de servicio Avahi nativo para AirPrint (iOS) y Mopria (Android) sin IPPS/TLS conflictivo
PRIMARY_IP=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || hostname -I | awk '{print $1}')
AVAHI_SERVICE_FILE="/etc/avahi/services/${PRINTER_QUEUE_NAME}.service"
log_info "Creando servicio Avahi AirPrint/Mopria en ${AVAHI_SERVICE_FILE} con IP objetivo ${PRIMARY_IP}..."

cat << EOF > "$AVAHI_SERVICE_FILE"
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">${PRINTER_DESCRIPTION}</name>
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/${PRINTER_QUEUE_NAME}</txt-record>
    <txt-record>ty=${PRINTER_DESCRIPTION}</txt-record>
    <txt-record>note=${PRINTER_LOCATION}</txt-record>
    <txt-record>product=(${PRINTER_DESCRIPTION})</txt-record>
    <txt-record>mopria-certified=1.3</txt-record>
    <txt-record>pdl=application/pdf,application/postscript,image/jpeg,image/png,image/pwg-raster,image/urf</txt-record>
    <txt-record>URF=V1.4,CP1,W8,PQ3-4,RS300,FN3</txt-record>
    <txt-record>UUID=085f58f9-1214-31d8-5218-13596711784b</txt-record>
    <txt-record>priority=0</txt-record>
    <txt-record>adminurl=http://${PRIMARY_IP}:631/printers/${PRINTER_QUEUE_NAME}</txt-record>
  </service>
</service-group>
EOF

# -----------------------------------------------------------------------------
# 9. CONFIGURACIÓN DE FIREWALL (UFW) PARA ACCESO LOCAL
# -----------------------------------------------------------------------------
log_info "Verificando reglas de firewall local (UFW)..."
if which ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    log_info "Apertura de puertos CUPS, Samba y mDNS en UFW para subredes locales..."
    ufw allow from 192.168.0.0/16 to any port 631 proto tcp comment "CUPS IPP LAN" || true
    ufw allow from 10.0.0.0/8 to any port 631 proto tcp comment "CUPS IPP LAN" || true
    ufw allow from 192.168.0.0/16 to any port 445 proto tcp comment "Samba SMB LAN" || true
    ufw allow from 192.168.0.0/16 to any port 139 proto tcp comment "Samba NetBIOS LAN" || true
    ufw allow proto udp to any port 5353 comment "Avahi mDNS Broadcast" || true
    ufw reload || true
    log_success "Reglas UFW aplicadas correctamente."
else
    log_info "UFW no está activo o no está instalado. Omitiendo apertura específica."
fi

# -----------------------------------------------------------------------------
# 10. REINICIO Y ACTIVACIÓN DE SERVICIOS SYSTEMD
# -----------------------------------------------------------------------------
log_info "Recargando y habilitando servicios: cups, avahi-daemon, smbd..."

systemctl daemon-reload
systemctl enable cups avahi-daemon smbd
systemctl restart cups avahi-daemon smbd

sleep 2

# -----------------------------------------------------------------------------
# 10. DETECCIÓN AUTOMÁTICA Y CREACIÓN DE LA COLA CUPS
# -----------------------------------------------------------------------------
log_info "Detectando impresora USB HP LaserJet..."

DETECTED_URI=""
# 1. Intentar por hp-probe
if which hp-probe &>/dev/null; then
    DETECTED_URI=$(hp-probe -b usb 2>/dev/null | grep -E "hp:/usb/" | awk '{print $1}' | head -n 1 || true)
fi

# 2. Fallback por lpinfo
if [ -z "$DETECTED_URI" ]; then
    DETECTED_URI=$(lpinfo -v 2>/dev/null | grep -E "(hp:/usb/|usb://HP)" | awk '{print $2}' | head -n 1 || true)
fi

if [ -n "$DETECTED_URI" ]; then
    log_success "Impresora HP detectada en URI: ${BOLD}${DETECTED_URI}${NC}"

    # Buscar mejor PPD disponible en el sistema (preferencia absoluta para hp-laserjet_m14-m17)
    BEST_PPD=""
    if /usr/sbin/lpinfo -m 2>/dev/null | grep -iE "hplip.*hp-laserjet_m14-m17\.ppd" &>/dev/null; then
        BEST_PPD=$(/usr/sbin/lpinfo -m 2>/dev/null | grep -iE "hplip.*hp-laserjet_m14-m17\.ppd" | head -n 1 | awk '{print $1}')
    elif /usr/sbin/lpinfo -m 2>/dev/null | grep -iE "foo2zjs.*HP-LaserJet_Pro_M12" &>/dev/null; then
        BEST_PPD=$(/usr/sbin/lpinfo -m 2>/dev/null | grep -iE "foo2zjs.*HP-LaserJet_Pro_M12" | head -n 1 | awk '{print $1}')
    fi

    if [ -z "$BEST_PPD" ]; then
        BEST_PPD="hplip:0/ppd/hplip/HP/hp-laserjet_m14-m17.ppd"
    fi

    log_info "Configurando cola CUPS '${PRINTER_QUEUE_NAME}' con PPD: ${BEST_PPD}..."
    /usr/sbin/lpadmin -p "$PRINTER_QUEUE_NAME" -E -v "$DETECTED_URI" -m "$BEST_PPD" -L "$PRINTER_LOCATION" -D "$PRINTER_DESCRIPTION"

    # Configuración crítica: evitar que la cola se detenga por sleep
    /usr/sbin/lpadmin -p "$PRINTER_QUEUE_NAME" -o printer-error-policy=retry-job
    /usr/sbin/lpadmin -p "$PRINTER_QUEUE_NAME" -o printer-is-shared=true
    /usr/sbin/lpadmin -p "$PRINTER_QUEUE_NAME" -o PageSize=A4
    /usr/sbin/lpadmin -p "$PRINTER_QUEUE_NAME" -o media=A4
    /usr/sbin/lpadmin -p "$PRINTER_QUEUE_NAME" -o fit-to-page-default=true
    /usr/sbin/lpadmin -p "$PRINTER_QUEUE_NAME" -o print-scaling-default=fill
    /usr/sbin/lpadmin -d "$PRINTER_QUEUE_NAME"

    cupsenable "$PRINTER_QUEUE_NAME"
    cupsaccept "$PRINTER_QUEUE_NAME"

    log_success "Cola '${PRINTER_QUEUE_NAME}' creada, compartida y activada con política de reintento automático."
else
    log_warn "No se detectó la impresora USB conectada en este momento."
    log_warn "Asegúrese de conectar el cable USB y encienda la impresora."
    log_warn "Luego ejecute manualmente: sudo lpadmin -p ${PRINTER_QUEUE_NAME} -E -v <URI_USB> -m everywhere"
fi

# -----------------------------------------------------------------------------
# 11. SCRIPT DE RECUPERACIÓN / WATCHDOG CONTRA SLEEP CONGELADO (OPCIONAL)
# -----------------------------------------------------------------------------
WATCHDOG_PATH="/usr/local/bin/cups_unstick_queue.sh"
cat << 'EOF' > "$WATCHDOG_PATH"
#!/usr/bin/env bash
# Desbloquea colas CUPS si alguna impresora HP entra en estado 'Paused' o 'Stopped'
for q in $(lpstat -p | grep "disabled" | awk '{print $2}'); do
    cupsenable "$q" 2>/dev/null || true
    cupsaccept "$q" 2>/dev/null || true
done
EOF
chmod +x "$WATCHDOG_PATH"

# -----------------------------------------------------------------------------
# 12. RESUMEN Y DIAGNÓSTICO FINAL
# -----------------------------------------------------------------------------
IP_ADDR=$(hostname -I | awk '{print $1}')
HOSTNAME_MDNS="$(hostname).local"

echo -e "\n${GREEN}${BOLD}====================================================================="
echo "   ¡DESPLIEGUE COMPLETADO CON ÉXITO!"
echo "=====================================================================${NC}"
echo -e "Dirección IP local:       ${BOLD}http://${IP_ADDR}:${CUPS_PORT}${NC}"
echo -e "Nombre mDNS:              ${BOLD}http://${HOSTNAME_MDNS}:${CUPS_PORT}${NC}"
echo -e "URL IPP para clientes:    ${BOLD}http://${IP_ADDR}:${CUPS_PORT}/printers/${PRINTER_QUEUE_NAME}${NC}"
echo -e "Ruta SMB para Windows:    ${BOLD}\\\\${IP_ADDR}\\${PRINTER_QUEUE_NAME}${NC}"
echo ""
echo "Estado de colas CUPS en el servidor:"
lpstat -p -d || true
echo ""
echo -e "${YELLOW}Prueba rápida de impresión desde la Raspberry Pi:${NC}"
echo "  echo 'Prueba Raspberry Pi 5' | lp -d ${PRINTER_QUEUE_NAME}"
echo "====================================================================="
