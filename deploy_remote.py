# -*- coding: utf-8 -*-
"""
=============================================================================
SERVIDOR DE IMPRESIÓN — HERRAMIENTA OFICIAL DE DESPLIEGUE REMOTO (PI 5)
deploy_remote.py
=============================================================================
Herramienta de automatización remota vía SSH para desplegar y verificar el
servidor de impresión CUPS/Avahi/Samba en la Raspberry Pi 5.
"""

import os
import sys
import argparse
import paramiko
from dotenv import load_dotenv

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(ROOT_DIR, ".env"))

RPI_HOST = os.getenv("RPI_HOST", "192.168.1.XXX")
RPI_PORT = int(os.getenv("RPI_PORT", "22"))
RPI_USER = os.getenv("RPI_USER", "tu_usuario")
RPI_PASSWORD = os.getenv("RPI_PASSWORD", "")
PRINTER_QUEUE_NAME = os.getenv("PRINTER_QUEUE_NAME", "HP_LaserJet_M14_M17")
CUPS_PORT = int(os.getenv("CUPS_PORT", "631"))


def get_ssh_session():
    """Establece sesión SSH y cliente SFTP."""
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"[*] Conectando vía SSH a {RPI_USER}@{RPI_HOST}:{RPI_PORT}...")
    client.connect(
        hostname=RPI_HOST,
        port=RPI_PORT,
        username=RPI_USER,
        password=RPI_PASSWORD,
        timeout=10,
    )
    sftp = client.open_sftp()
    print("✅ Conexión SSH establecida con éxito.")
    return client, sftp


def execute_stream_command(client, command, sudo=False):
    """Ejecuta un comando remoto y transmite la salida en vivo sin eco de contraseña."""
    if sudo and RPI_USER != "root":
        cmd = f"sudo -S -p '' bash -c {command!r}"
        stdin, stdout, stderr = client.exec_command(cmd, get_pty=False)
        if RPI_PASSWORD:
            stdin.write(RPI_PASSWORD + "\n")
            stdin.flush()
    else:
        cmd = command
        stdin, stdout, stderr = client.exec_command(cmd, get_pty=False)

    for line in iter(stdout.readline, ""):
        print(line, end="")

    err = stderr.read().decode("utf-8", errors="replace")
    err_filtered = "\n".join(
        l for l in err.splitlines() 
        if l.strip() and not l.strip().startswith("[sudo]") and RPI_PASSWORD not in l
    )
    if err_filtered:
        print(err_filtered)

    exit_status = stdout.channel.recv_exit_status()
    return exit_status


def deploy_server():
    """Copia setup_cups_server.sh y lo ejecuta remotamente con sudo."""
    print("\n" + "=" * 70)
    print("🚀 DESPLIEGUE REMOTO: SERVIDOR DE IMPRESIÓN RASPBERRY PI 5")
    print("=" * 70)

    client, sftp = get_ssh_session()
    try:
        local_script = os.path.join(ROOT_DIR, "setup_cups_server.sh")
        remote_dir = f"/home/{RPI_USER}/server_print"
        remote_script = f"{remote_dir}/setup_cups_server.sh"

        print(f"[*] Creando directorio remoto '{remote_dir}'...")
        try:
            sftp.mkdir(remote_dir)
        except Exception:
            pass

        print(f"[*] Subiendo script '{local_script}' a '{remote_script}'...")
        sftp.put(local_script, remote_script)
        sftp.chmod(remote_script, 0o755)
        print("✅ Script subido con permisos de ejecución.")

        print("\n[*] Ejecutando instalador en Raspberry Pi 5...")
        run_cmd = f"PRINTER_QUEUE_NAME='{PRINTER_QUEUE_NAME}' bash '{remote_script}'"
        code = execute_stream_command(client, run_cmd, sudo=True)

        if code == 0:
            print("\n✅ Despliegue completado satisfactoriamente.")
        else:
            print(f"\n❌ El script finalizó con código de error: {code}")

    finally:
        sftp.close()
        client.close()


def check_status():
    """Inspecciona el estado de los servicios, dispositivos USB y colas CUPS."""
    print("\n" + "=" * 70)
    print("🔍 DIAGNÓSTICO DEL SERVIDOR DE IMPRESIÓN")
    print("=" * 70)

    client, _ = get_ssh_session()
    try:
        print("\n--- 1. DISPOSITIVOS USB DETECTADOS ---")
        execute_stream_command(client, "lsusb | grep -iE 'hp|laserjet|print' || lsusb")

        print("\n--- 2. ESTADO DE SERVICIOS SYSTEMD ---")
        execute_stream_command(client, "systemctl is-active cups avahi-daemon smbd")

        print("\n--- 3. ESTADO DE COLAS CUPS (lpstat) ---")
        execute_stream_command(client, "lpstat -p -d -r")

        print("\n--- 4. PUERTOS EN ESCUCHA (IPP 631 / SMB 445 / mDNS 5353) ---")
        execute_stream_command(client, "sudo ss -tlunp | grep -E '631|445|5353' || true", sudo=True)

        print("\n--- 5. PANELES WEB DE GESTIÓN (CUPS) ---")
        print(f"   🌐 Monitor de Trabajos en Cola: http://{RPI_HOST}:{CUPS_PORT}/jobs/")
        print(f"   🖨️ Estado de la Impresora:     http://{RPI_HOST}:{CUPS_PORT}/printers/{PRINTER_QUEUE_NAME}")

    finally:
        client.close()


def print_test_page():
    """Envía un trabajo de prueba directo a la cola CUPS."""
    print("\n" + "=" * 70)
    print(f"🖨️ ENVIANDO PÁGINA DE PRUEBA A LA COLA: {PRINTER_QUEUE_NAME}")
    print("=" * 70)

    client, _ = get_ssh_session()
    try:
        test_cmd = (
            f"echo -e '*** PRUEBA DE IMPRESION ***\\nServidor: Raspberry Pi 5\\nCola: {PRINTER_QUEUE_NAME}\\nFecha: $(date)\\nEstado: OK' "
            f"| lp -d {PRINTER_QUEUE_NAME}"
        )
        execute_stream_command(client, test_cmd)
        print("\n[*] Estado de trabajos activos:")
        execute_stream_command(client, f"lpstat -o {PRINTER_QUEUE_NAME}")
    finally:
        client.close()


def list_jobs():
    """Muestra trabajos activos y completados en la cola CUPS."""
    print("\n" + "=" * 70)
    print(f"📋 COLA DE TRABAJOS DE IMPRESIÓN — {PRINTER_QUEUE_NAME}")
    print(f"🌐 Monitor Web en Vivo: http://{RPI_HOST}:{CUPS_PORT}/jobs/")
    print("=" * 70)

    client, _ = get_ssh_session()
    try:
        print("\n--- 1. TRABAJOS ACTIVOS (EN PROCESO / PENDIENTES) ---")
        execute_stream_command(client, "lpstat -o || echo 'No hay trabajos pendientes.'")

        print("\n--- 2. ÚLTIMOS TRABAJOS COMPLETADOS ---")
        execute_stream_command(client, "lpstat -W completed | tail -n 10 || true")
    finally:
        client.close()


def clear_jobs():
    """Cancela todos los trabajos pendientes y purga la cola."""
    print("\n" + "=" * 70)
    print(f"🧹 CANCELANDO TODOS LOS TRABAJOS Y PURGANDO LA COLA: {PRINTER_QUEUE_NAME}")
    print("=" * 70)

    client, _ = get_ssh_session()
    try:
        cmd = f"sudo cancel -a -x && sudo cupsenable {PRINTER_QUEUE_NAME} && sudo cupsaccept {PRINTER_QUEUE_NAME}"
        execute_stream_command(client, cmd, sudo=True)
        print("\n[*] Estado de la cola tras el vaciado:")
        execute_stream_command(client, f"lpstat -p {PRINTER_QUEUE_NAME} -o")
    finally:
        client.close()


def unstick_queue():
    """Reactiva la cola si entró en pausa por standby/sleep."""
    print("\n" + "=" * 70)
    print(f"🔄 REACTIVANDO COLA DE IMPRESIÓN (DESBLOQUEO SLEEP): {PRINTER_QUEUE_NAME}")
    print("=" * 70)

    client, _ = get_ssh_session()
    try:
        cmd = f"sudo cupsenable {PRINTER_QUEUE_NAME} && sudo cupsaccept {PRINTER_QUEUE_NAME}"
        execute_stream_command(client, cmd, sudo=True)
        print("\n[*] Estado actual de la cola:")
        execute_stream_command(client, f"lpstat -p {PRINTER_QUEUE_NAME}")
    finally:
        client.close()


def run_diagnostics():
    """Ejecuta un diagnóstico profundo de la impresora, PPDs y CUPS."""
    print("\n" + "=" * 70)
    print("🔍 DIAGNÓSTICO PROFUNDO DE HARDWARE Y CONTROLADORES HP")
    print("=" * 70)

    client, _ = get_ssh_session()
    try:
        commands = [
            ("URI detectada por hp-probe", "hp-probe -b usb"),
            ("PPD actual de la cola", "grep -E '^\\*ModelName|^\\*NickName' /etc/cups/ppd/HP_LaserJet_M14_M17.ppd 2>/dev/null || true"),
            ("Seccion hp_laserjet_m14-m17 en models.dat", "sed -n '62127,62160p' /usr/share/hplip/data/models/models.dat"),
            ("Seccion alternativa hp_laserjet_m14-m17", "sed -n '62217,62250p' /usr/share/hplip/data/models/models.dat"),
            ("Archivos PPD relacionados con LaserJet M en /usr/share/ppd", "find /usr/share/ppd -name '*laserjet*' 2>/dev/null || true"),
            ("Últimos errores en /var/log/cups/error_log", "sudo tail -n 30 /var/log/cups/error_log"),
            ("Trabajos en cola de impresión", "lpstat -o -W all || true"),
        ]
        for title, cmd in commands:
            print(f"\n--- {title} ---")
            execute_stream_command(client, cmd, sudo=("sudo" in cmd))
    finally:
        client.close()


def fix_printer_ppd():
    """Corrige el bloqueo ipp-usb y asigna el PPD oficial hplip hp-laserjet_m14-m17.ppd."""
    print("\n" + "=" * 70)
    print("🔧 APLICANDO FIX DEFINITIVO: DESACTIVAR IPP-USB Y ASIGNAR PPD OFICIAL")
    print("=" * 70)

    client, _ = get_ssh_session()
    try:
        cmd = (
            # 1. Detener y deshabilitar ipp-usb para liberar el puerto USB
            "sudo systemctl stop ipp-usb || true; "
            "sudo systemctl disable ipp-usb || true; "
            "sudo systemctl mask ipp-usb || true; "
            # 2. Limpiar colas previas duplicadas o con drivers erroneos
            "sudo /usr/sbin/lpadmin -x HP_LaserJet_M14-M17 2>/dev/null || true; "
            "sudo /usr/sbin/lpadmin -x HP_LaserJet_M14_M17 2>/dev/null || true; "
            # 3. Crear cola con el PPD oficial y URI de HPLIP
            "sudo /usr/sbin/lpadmin -p HP_LaserJet_M14_M17 -E "
            "-v 'hp:/usb/HP_LaserJet_M14-M17?serial=SERIAL_USB' "
            "-m 'hplip:0/ppd/hplip/HP/hp-laserjet_m14-m17.ppd' "
            "-L 'Servidor Raspberry Pi 5' -D 'HP LaserJet Pro M14-M17' && "
            "sudo /usr/sbin/lpadmin -p HP_LaserJet_M14_M17 -o printer-error-policy=retry-job && "
            "sudo /usr/sbin/lpadmin -p HP_LaserJet_M14_M17 -o printer-is-shared=true && "
            "sudo /usr/sbin/lpadmin -d HP_LaserJet_M14_M17 && "
            "sudo cupsenable HP_LaserJet_M14_M17 && "
            "sudo cupsaccept HP_LaserJet_M14_M17"
        )
        print("[*] Configurando cola oficial con PPD hp-laserjet_m14-m17.ppd...")
        execute_stream_command(client, cmd, sudo=True)

        print("\n[*] Estado de colas actualizado:")
        execute_stream_command(client, "lpstat -p -d -v")

        print("\n[*] Probando canal HPLIP hacia el dispositivo...")
        execute_stream_command(client, "sudo hp-testpage -d hp:/usb/HP_LaserJet_M14-M17?serial=SERIAL_USB || true", sudo=True)

        print("\n[*] Trabajos en cola tras el envío:")
        execute_stream_command(client, "lpstat -o")

    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description="Gestor y Despliegue Remoto del Servidor de Impresión RPi 5")
    parser.add_argument("--deploy", action="store_true", help="Despliega e instala CUPS, HPLIP, Avahi y Samba")
    parser.add_argument("--status", action="store_true", help="Comprueba la salud del servidor y estado de colas")
    parser.add_argument("--test-page", action="store_true", help="Imprime una página de prueba desde la Raspberry Pi")
    parser.add_argument("--jobs", action="store_true", help="Lista los trabajos activos y completados en la cola")
    parser.add_argument("--clear-jobs", action="store_true", help="Cancela todos los trabajos pendientes y purga la cola")
    parser.add_argument("--unstick", action="store_true", help="Reanuda la cola tras un bloqueo por suspensión/sleep")
    parser.add_argument("--diag", action="store_true", help="Diagnóstico profundo de PPDs, errores y cola")
    parser.add_argument("--fix-ppd", action="store_true", help="Reconfigura la cola con el PPD exacto vía hp-setup")

    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(0)

    args = parser.parse_args()

    if args.deploy:
        deploy_server()
    elif args.status:
        check_status()
    elif args.test_page:
        print_test_page()
    elif args.jobs:
        list_jobs()
    elif args.clear_jobs:
        clear_jobs()
    elif args.unstick:
        unstick_queue()
    elif args.diag:
        run_diagnostics()
    elif args.fix_ppd:
        fix_printer_ppd()


if __name__ == "__main__":
    main()
