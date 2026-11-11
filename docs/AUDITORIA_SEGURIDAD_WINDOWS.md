# 🛡️ Auditoría de Seguridad y Guía de Instalación en Windows 10 / 11 (SmartScreen)

Este documento explica **por qué Windows muestra una advertencia de seguridad** al abrir el instalador `INSTALAR_PRINT_SERVER_PI5.exe`, detalla **línea por línea todo lo que ejecuta** el software en tu equipo y ofrece una **guía paso a paso** para instalarlo de forma segura o auditar/compilar el código fuente tú mismo.

---

## 1. ¿Por qué Windows no confía automáticamente en el instalador?

Al descargar `INSTALAR_PRINT_SERVER_PI5.exe` desde internet o GitHub Pages, Windows 10 y Windows 11 muestran la pantalla azul de **Windows Defender SmartScreen** (*"Windows protegió su PC"* / *"Editor desconocido"*).

Esto ocurre por dos motivos técnicos legítimos y transparentes:
1. **Sin certificado comercial de firma de código (Authenticode / EV / Trusted Signing):** Este es un proyecto abierto y gratuito. Obtener un certificado de firma reconocido automáticamente por Microsoft requiere contratar un servicio comercial de pago y verificación empresarial. Un certificado autofirmado gratuito solo funciona en el equipo donde se instala manualmente en el almacén raíz de confianza, pero no evita el aviso en ordenadores de otros usuarios.
2. **Baja reputación inicial en SmartScreen:** Microsoft SmartScreen bloquea por defecto cualquier `.exe` recién compilado hasta que miles de equipos lo ejecutan a lo largo del tiempo.

> [!NOTE]
> **¿Se puede "hacer que Windows confíe" sin certificado de pago?**  
> No de forma automática para cualquier usuario que lo descargue desde la web. Por transparencia y buenas prácticas de seguridad, este proyecto **no intenta ocultar ni evadir** los avisos de Windows; en su lugar, publica todo el código fuente en C# y detalla aquí cada acción que realiza el instalador.

---

## 2. Qué ejecuta exactamente en tu PC (Auditoría Completa)

Todo el comportamiento está contenido en dos archivos fuente públicos en la raíz del repositorio:
- [`Instalador_Print_Server_Pi5.cs`](../Instalador_Print_Server_Pi5.cs)
- [`Print_Server_Pi5.cs`](../Print_Server_Pi5.cs)

### A. Acciones de `INSTALAR_PRINT_SERVER_PI5.exe`
1. **Elevación a Administrador (UAC):** Solicita permisos elevados (`Verb = "runas"`) únicamente para poder copiar archivos en `C:\Program Files`, registrar la impresora en el Spooler de Windows y escribir la entrada de inicio.
2. **Configuración de IP local:** Lee `ip_servidor.txt` si existe junto al ejecutable; si no, te pide por consola la IP local de tu Raspberry Pi y comprueba por TCP el puerto `631` (CUPS).
3. **Despliegue de archivos:** Detiene cualquier instancia previa de `Print_Server_Pi5.exe`, crea la carpeta `C:\Program Files\Print_Server_Pi5\` (o `%LocalAppData%\Print_Server_Pi5\` como respaldo) y extrae en ella sus dos recursos incrustados:
   - `Print_Server_Pi5.exe` (el monitor de bandeja)
   - `pirata.ico` (el icono de la aplicación)
   - También guarda `ip_servidor.txt` y genera un script `DESINSTALAR.bat`.
4. **Alta de impresora IPP:** Ejecuta un comando PowerShell local (`Add-Printer` / `printui.dll`) para registrar la impresora `HP LaserJet M14-M17 (Red Hogar)` apuntando a `http://<IP_RASPBERRY>:631/printers/HP_LaserJet_M14_M17` con controladores nativos de Windows/HP.
5. **Acceso directo en Menú Inicio:** Crea `Print_Server_Pi5.lnk` en `%ProgramData%\Microsoft\Windows\Start Menu\Programs\`.
6. **Inicio automático y arranque en bandeja:** Registra la clave `Print_Server_Pi5` en `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` (vista de 64 bits) con `--startup` e inicia `Print_Server_Pi5.exe` en la sesión gráfica del usuario.

### B. Acciones de `Print_Server_Pi5.exe` (segundo plano)
- **Red exclusivamente local:** Cada 3 segundos consulta por HTTP local `http://<IP_RASPBERRY>:631/printers/HP_LaserJet_M14_M17` y `http://<IP_RASPBERRY>:631/jobs?which_jobs=all` para mostrar el estado en el icono junto al reloj y emitir notificaciones Toast en Windows cuando un documento se imprime o se atasca.
- **Acciones bajo demanda:** Solo si pulsas *Desbloquear y Reanudar Impresora* o *Cancelar trabajos atascados*, envía una petición POST local al servidor CUPS (`OP=start-printer` u `OP=purge-jobs`).
- **Sin telemetría ni conexiones externas:** No contacta con ningún servidor fuera de tu red local, no abre puertos de escucha y no recopila datos.

---

## 3. Verificación de Integridad (SHA-256)

Antes de ejecutar el archivo descargado, puedes comprobar en PowerShell que el binario coincide exactamente con la compilación oficial del repositorio:

```powershell
Get-FileHash "$env:USERPROFILE\Downloads\INSTALAR_PRINT_SERVER_PI5.exe" -Algorithm SHA256
```

Hashes SHA-256 oficiales de la compilación actual:
- **`INSTALAR_PRINT_SERVER_PI5.exe`**: `B15AA1969CE57D25BA80D4C441503746FC0015A60AD8E618F5775F9F365A7E0E`
- **`Print_Server_Pi5.exe`**: `ABF51F2A76BCF888CC636BB47A1B0D3E5021F51A9B0E3F3A6D8E553C222684F6`

---

## 4. Guía Paso a Paso para Instalarlo en Windows 10 / 11

1. **Descarga el instalador** desde el portal web (**DESCARGAR INSTALADOR (.EXE)**) o desde [`Cliente_Windows_ClickAndPlay/INSTALAR_PRINT_SERVER_PI5.exe`](../Cliente_Windows_ClickAndPlay/INSTALAR_PRINT_SERVER_PI5.exe).
2. Haz **doble clic** sobre `INSTALAR_PRINT_SERVER_PI5.exe`.
3. Cuando aparezca la ventana azul **"Windows protegió su PC"** (Microsoft Defender SmartScreen):
   - Haz clic en el enlace **`Más información`** (debajo del texto principal).
   - Pulsa el botón **`Ejecutar de todas formas`** que aparecerá abajo.
4. Cuando aparezca el aviso de **Control de cuentas de usuario (UAC)** indicando *"Editor desconocido"*:
   - Pulsa **`Sí`** para permitir instalar la impresora y el servicio en `C:\Program Files\Print_Server_Pi5\`.
5. En la consola negra que se abre:
   - Escribe la **IP local de tu Raspberry Pi** (por ejemplo `192.168.1.100`) y pulsa **Enter**.
6. Al finalizar verás la confirmación verde y aparecerá el **icono de bandera pirata** junto al reloj de Windows (si no se ve a primera vista, abre la flecha `^` de iconos ocultos en la barra de tareas).

---

## 5. Alternativas 100% Sin Ejecutables Descargados

Si prefieres no ejecutar `.exe` precompilados descargados de internet:

### Opción A: Scripts en texto plano (`.bat` y `.ps1`)
En la carpeta [`Cliente_Windows_ClickAndPlay/Scripts_Ejecucion_Manual/`](../Cliente_Windows_ClickAndPlay/Scripts_Ejecucion_Manual/) puedes abrir con el Bloc de notas y revisar cada script antes de ejecutar [`INSTALAR_IMPRESORA.bat`](../Cliente_Windows_ClickAndPlay/Scripts_Ejecucion_Manual/INSTALAR_IMPRESORA.bat).

### Opción B: Compilar tú mismo el código fuente C# con Windows
Windows 10/11 incluye el compilador oficial de .NET (`csc.exe`), por lo que puedes generar tus propios ejecutables localmente desde PowerShell en la raíz del repositorio:

```powershell
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /target:winexe /platform:anycpu /optimize+ /win32icon:pirata.ico /out:Cliente_Windows_ClickAndPlay\Print_Server_Pi5.exe Print_Server_Pi5.cs
& $csc /target:exe /platform:anycpu /optimize+ /win32icon:pirata.ico /resource:Cliente_Windows_ClickAndPlay\Print_Server_Pi5.exe,Print_Server_Pi5.exe /resource:pirata.ico,pirata.ico /out:Cliente_Windows_ClickAndPlay\INSTALAR_PRINT_SERVER_PI5.exe Instalador_Print_Server_Pi5.cs
```

---

## 6. Cómo Desinstalarlo Completamente

Si en cualquier momento deseas retirar la impresora, el acceso directo y el servicio de inicio automático, ejecuta como Administrador:

```text
C:\Program Files\Print_Server_Pi5\DESINSTALAR.bat
```
