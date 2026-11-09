# 📱 Guía Oficial de Impresión Móvil — Servidor Privado Raspberry Pi 5

Guía paso a paso para imprimir documentos, fotos y correos desde teléfonos móviles y tablets (**Android** e **iOS / iPadOS**) conectados a la red Wi-Fi del hogar utilizando el servidor privado de impresión CUPS alojado en la **Raspberry Pi 5**.

---

## 📑 Índice de Contenidos
1. [Requisitos Previos de Red](#1-requisitos-previos-de-red)
2. [Impresión en Android (Zero-Config Nativo / Mopria)](#2-impresión-en-android-zero-config-nativo--mopria)
3. [Conexión Manual por IP en Android (Si el router tiene Aislamiento Wi-Fi)](#3-conexión-manual-por-ip-en-android-si-el-router-tiene-aislamiento-wi-fi)
4. [Impresión en iPhone y iPad (Apple AirPrint Nativo)](#4-impresión-en-iphone-y-ipad-apple-airprint-nativo)
5. [Cómo Imprimir desde las Apps más Populares](#5-cómo-imprimir-desde-las-apps-más-populares)
6. [Resolución de Problemas Móviles Frecuentes](#6-resolución-de-problemas-móviles-frecuentes)

---

## 1. Requisitos Previos de Red

Para que el móvil se comunique con el servidor:
- **Estar conectado a la misma red Wi-Fi** que la Raspberry Pi (habitualmente la red Wi-Fi de tu router de casa).
- *Nota sobre bandas 2.4 GHz y 5 GHz*: Puedes estar conectado tanto a la banda 2.4 GHz como a la de 5 GHz; siempre que pertenezcan al mismo router local compartirán el direccionamiento (`192.168.1.x`).
- **Datos móviles (4G/5G)**: No interfieren, pero el móvil debe tener el Wi-Fi activado y conectado a la red local.

---

## 2. Impresión en Android (Zero-Config Nativo / Mopria)

Todos los dispositivos Android modernos (Android 9, 10, 11, 12, 13, 14 y 15 en marcas como Samsung, Xiaomi, Google Pixel, Motorola, Realme, Oppo, etc.) incorporan de fábrica soporte para impresión IPP mediante el **Servicio de Impresión Predeterminado** o **Mopria Print Service**.

### Paso a paso para activar el servicio:
1. Abre los **Ajustes** de tu teléfono Android.
2. Navega a:
   - **Samsung**: *Conexiones > Más ajustes de conexión > Imprimir*.
   - **Xiaomi / Redmi / POCO**: *Conexión y compartir > Impresión*.
   - **Google Pixel / Motorola / Android Puro**: *Dispositivos conectados > Preferencias de conexión > Impresión*.
3. Comprueba que el **Servicio de impresión predeterminado** (o **Mopria Print Service**) esté en **Activado**.
4. Pulsa sobre él: el teléfono buscará automáticamente en la red y mostrará:
   ```text
   HP_LaserJet_M14_M17 @ tu_usuario
   ```
   o bien el nombre del servicio mDNS detectado.
5. ¡Listo! Ya puedes imprimir desde cualquier aplicación.

---

## 3. Conexión Manual por IP en Android (Si el router tiene Aislamiento Wi-Fi)

> [!NOTE]
> **¿Por qué ocurre esto?**  
> Algunos routers de fibra de operadoras (Movistar, Vodafone, Orange, Digi, etc.) tienen habilitada por seguridad una opción llamada **AP Isolation (Aislamiento de Punto de Acceso)** o filtrado de tráfico multidifusión (*Multicast / IGMP snooping*). Esto impide que los paquetes mDNS (`.local`) viajen entre el móvil y la Raspberry Pi.

Si tu teléfono no detecta la impresora automáticamente, vincúlala por IP directa en 30 segundos:

1. Ve a **Ajustes > Impresión > Servicio de impresión predeterminado**.
2. Pulsa en los **tres puntos verticales (Menú)** en la esquina superior derecha.
3. Selecciona **"Agregar impresora"** (o "Añadir impresora mediante dirección IP").
4. Elige la opción **"Por dirección IP / Nombre de host"**.
5. Introduce los datos de tu servidor local:
   * **Dirección IP del servidor:** `192.168.1.XXX`
   * *(Si la aplicación solicita la ruta IPP completa o puerto)*:  
     `http://192.168.1.XXX:631/printers/HP_LaserJet_M14_M17`  
     o `ipp://192.168.1.XXX:631/printers/HP_LaserJet_M14_M17`
6. Pulsa **Guardar** o **Aceptar**.
7. La impresora quedará memorizada de forma permanente, funcionando de manera directa e inmune al aislamiento de Wi-Fi del router.

---

## 4. Impresión en iPhone y iPad (Apple AirPrint Nativo)

Los dispositivos Apple (iOS / iPadOS) no necesitan ninguna aplicación de terceros ni configuración previa gracias al demonio **Avahi** corriendo en la Raspberry Pi 5:

1. Conecta tu iPhone o iPad al Wi-Fi de la vivienda.
2. Abre cualquier documento, foto, página web o correo.
3. Pulsa el botón **Compartir** (icono de cuadrado con flecha hacia arriba).
4. Desliza hacia abajo y pulsa en **Imprimir**.
5. En el campo **Impresora**, selecciónala: aparecerá como `HP_LaserJet_M14_M17`.
6. Ajusta el número de copias o rango de páginas y pulsa **Imprimir** en la esquina superior derecha.

---

## 5. Cómo Imprimir desde las Apps más Populares

```mermaid
flowchart LR
    App["Cualquier App Móvil\n(WhatsApp, Gmail, Chrome, PDF)"] --> Menu["Menú Compartir o ⋮ (3 puntos)"]
    Menu --> Print["Opción Imprimir"]
    Print --> Destino["Seleccionar Impresora:\nHP_LaserJet_M14_M17"]
    Destino --> Send["🖨️ Imprimir Página"]
```

### 📄 Documentos PDF (Adobe Acrobat, Google Drive, WhatsApp)
* **WhatsApp**: Pulsa sobre el archivo PDF recibido > Menú (3 puntos arriba a la derecha) > **Imprimir** (o Compartir > Imprimir).
* **Google Drive / Lector de PDF**: Abre el archivo > Menú (3 puntos) > **Imprimir** > Elige `HP_LaserJet_M14_M17`.

### 🌐 Páginas Web (Google Chrome, Safari, Firefox)
* **Chrome (Android)**: Pulsa los 3 puntos arriba a la derecha > **Compartir...** > Selecciona el icono **Imprimir** > Ajusta si deseas imprimir todo o páginas específicas.
* **Safari (iOS)**: Pulsa Compartir > **Imprimir**.

### ✉️ Correos Electrónicos (Gmail, Outlook)
* **Gmail**: Abre el correo > Pulsa los 3 puntos al lado del remitente del mensaje > **Imprimir todo** o **Imprimir**.

### 🖼️ Fotos y Galería
* Abre la fotografía en tu app de Galería > Pulsa **Compartir** o los 3 puntos > **Imprimir** > Ajusta el tamaño de papel (A4) y pulsa el botón de imprimir.

---

## 6. Resolución de Problemas Móviles Frecuentes

### ❓ La impresora aparece como "No disponible" o con círculo de carga infinito
1. **Comprueba el Wi-Fi**: Verifica que tu móvil no se haya desconectado del Wi-Fi ni haya saltado a datos móviles.
2. **Ahorro de batería agresivo de Android**:  
   En capas de personalización como MIUI/HyperOS (Xiaomi) o OneUI (Samsung), el sistema puede suspender el servicio de impresión en segundo plano.  
   *Solución:* Ve a *Ajustes > Aplicaciones > Servicio de impresión predeterminado > Batería* y elige **Sin restricciones**.
3. **Reactivar la cola del servidor**: Si la impresora se apagó físicamente de su botón frontal, puedes reanudarla desde cualquier PC con:
   ```bash
   python deploy_remote.py --unstick
   ```
   o esperar a que el servidor la reintente automáticamente gracias a la política `printer-error-policy=retry-job`.

---

## 📊 Ficha Rápida de Parámetros de Red

| Parámetro | Valor para Móviles |
| :--- | :--- |
| **Nombre de Cola** | `HP_LaserJet_M14_M17` |
| **IP del Servidor** | `192.168.1.XXX` |
| **Puerto IPP** | `631` |
| **URL IPP Directa** | `http://192.168.1.XXX:631/printers/HP_LaserJet_M14_M17` |
| **Protocolo de difusión** | mDNS / DNS-SD (Avahi Daemon) |
| **Formato de impresión** | PCLmS / URF / PDF Raster |
