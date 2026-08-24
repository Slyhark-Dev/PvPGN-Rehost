# Player vs Player Gaming Network - PRO (Edición Personalizada)

<img width="1024" height="74" alt="banner" src="https://github.com/user-attachments/assets/1c17d201-e737-425e-8d70-7a573a4d3be4" />

PvPGN es un software de servidor multiplataforma gratuito y de código abierto que admite los clientes de juego Battle.net y Westwood Online. PvPGN-PRO es una bifurcación del proyecto oficial PvPGN, cuyo desarrollo se detuvo en 2011, mantenida por HarpyWar, con el objetivo de proporcionar mantenimiento continuo y funciones adicionales. Esta edición fue modificada a partir de **PvPGN 1.99.7.2.0-PRO**.

![License](https://img.shields.io/badge/license-GNU%20GPL%20version%202-blue)
![C++](https://img.shields.io/badge/powered%20by-C%2B%2B-brightgreen)
![Lua](https://img.shields.io/badge/powered%20by-Lua-red)
![MSVC](https://img.shields.io/badge/compiled%20with-Microsoft%20Visual%20C%2B%2B-yellow)
![Clang](https://img.shields.io/badge/compiled%20with-LLVM%2FClang-lightgrey)
![GCC](https://img.shields.io/badge/compiled%20with-GCC-yellowgreen)
![Build](https://img.shields.io/badge/build-PASSING-brightgreen)
![Python](https://img.shields.io/badge/powered%20by-Python-3776AB)
![JSON](https://img.shields.io/badge/config-JSON-lightgrey)

## Características y modificaciones personalizadas

* **Base del servidor:** Construido sobre PvPGN v1.99.7.2.0-PRO.
* **Compatibilidad forzada:** Configurado y fijado específicamente para WarCraft 3: The Frozen Throne versión **1.27b**.
* **Corrección del auto-update:** El sistema de actualización automática fue corregido y está habilitado por defecto.
* **Sistema de rehost:** Sistema de rehost integrado, similar al de rubattlenet (requiere un archivo complementario externo).
* **Comunicación IPC:** Implementación de comunicación entre procesos (IPC) para conectar el servidor en C++ con Lua y PvPGN.
* **Despliegue rápido:** Binarios listos para usar. No se necesita compilar el código fuente.

## Instalación

Esta versión personalizada no requiere compilación desde el código fuente. Simplemente descarga la versión, extrae el contenido en el directorio que prefieras, y ejecuta el servidor.

## Sistema de rehost y subida de mapas

El comando `/rehost` y `/upload` permiten a los jugadores recrear una partida o subir un mapa nuevo directamente desde el chat del juego, sin salir del cliente de WarCraft 3.

Esta funcionalidad se apoya en una capa adicional compuesta por dos programas propios que trabajan junto a PvPGN:

* **MapServer:** proceso en C++ que recibe las órdenes desde PvPGN y coordina la comunicación con los clientes conectados.
* **MapClient:** proceso complementario que el jugador ejecuta junto a WarCraft 3. Se encarga de analizar el mapa localmente (usando StormLib y los algoritmos de detección de slots, tamaño y checksums) y de generar el archivo de configuración necesario para el rehost.

El flujo, tanto para `/rehost` como para `/upload`, es el siguiente:

1. El jugador escribe el comando en el chat del juego.
2. PvPGN, mediante un script de Lua, envía la orden al MapServer a través de IPC.
3. El MapServer localiza al MapClient del jugador (identificado por su nombre de usuario) y le reenvía la orden.
4. El MapClient analiza el mapa o procesa la subida, y devuelve el resultado (información de slots, o el archivo del mapa) al MapServer.
5. El MapServer entrega ese resultado de vuelta a PvPGN, que lo aplica y notifica al jugador en el chat.

Todo este intercambio ocurre en segundo plano, en cuestión de segundos, sin que el jugador necesite hacer nada manualmente ni salir del cliente.

**Requerimientos:** [MapServer y MapClient](https://github.com/Slyhark-Dev/Editor-launcherPvPGN)

### Mapa de puertos IPC :

| Puerto | Canal | Sentido | Contenido |
|---|---|---|---|
| 7776 | Comandos | MapServer ↔ MapClient | Registro del cliente, envío de órdenes, verificación de actividad |
| 7775 | Archivo de configuración | MapClient → MapServer | Transferencia del archivo de configuración generado tras analizar el mapa |
| 7774 | Subida de mapa | MapClient → MapServer | Envío del archivo del mapa durante una subida |
| 7773 | Lectura de replay | ReplayAnalyzer → MapServer | Envío de flag winner and losser mediante un replay con sistema w3mmd |
| 7772 | Acreditación de user | PvPGN → MapServer | Órdenes y consultas internas (registro de usuario, órdenes de rehost/upload, consulta de información de mapa) |

Esta comunicación reemplazó a un esquema anterior basado en archivos de texto compartidos, que dependía de lecturas periódicas de disco. El esquema actual usa conexiones directas por sockets, lo que elimina esa dependencia y hace la coordinación más inmediata y confiable.

**Nota:** el uso de esta funcionalidad requiere que el jugador tenga el MapClient en ejecución. Si un jugador intenta usar `/rehost` sin tenerlo activo, el sistema se lo notifica en el chat.

## Sistema W3MMD por replay (score, stats y partidas oficiales)

Ademas del rehost/upload, hay un sistema separado que lee las partidas ya jugadas y grabadas por el bot (GHost One), extrae el resultado, y aplica score/stats de forma automatica, igual que el ladder o la daga nativa, pero para partidas custom.

Funciona asi:

1. GHost One graba la partida como replay (.w3g) al terminar.
2. Un script en Python vigila la carpeta de replays (sin polling, se activa por evento al aparecer el archivo nuevo).
3. El script abre el replay y extrae los datos: jugadores, slots, y el ganador.
4. La deteccion del ganador usa tres metodos, en orden:
   - Eventos nativos de salida del cliente WC3 (validos en mapas oficiales/melee).
   - Datos W3MMD embebidos en el mapa (`FlagP winner/loser`), para mapas custom que lo soporten.
   - Formato DotA Stats (`kdr.x Global Winner`), para mapas tipo DotA Allstars.
5. Si el mapa es custom y no tiene ninguno de esos sistemas, no se manda nada — se descarta con aviso, en vez de inventar un resultado.
6. El resultado se envia por IPC directo a PvPGN, que aplica el calculo de EXP/rating igual que en una partida oficial.

Esto permite usar el mismo sistema de score y estadisticas tanto en partidas oficiales (ladder/daga) como en partidas custom hosteadas por el bot, siempre que el mapa tenga soporte W3MMD o DotA Stats.

**Extraccion de datos de partidas creadas con GHost One:** el sistema fue probado y validado con [GHost One 1.7.266](https://foros.3dgames.com.ar/threads/669419-guia-ghost-one-1-7-266) sin modificaciones. Puede usarse con cualquier otra version de bot, pero para asegurar el 100% de compatibilidad con otros bots puede requerirse un ajuste menor en el parser de replay.

## Corrección del sistema de actualización de versión

Se corrigió y ajustó la validación de versión de cliente (`versioncheck.conf`) para aceptar correctamente la versión de WarCraft 3: The Frozen Throne 1.27b utilizada por la comunidad, resolviendo problemas que impedían el ingreso de clientes con esa versión.

## En desarrollo

Estas áreas siguen en evolución activa y podrán ampliarse en futuras versiones:

* Mejoras adicionales sobre el sistema de emparejamiento (matchmaking) para partidas anónimas.
* Ampliación del análisis posterior a la partida mediante la lectura de repeticiones (replays).

## Seguimiento (Tracking)

Por defecto, el seguimiento está habilitado y se usa únicamente para enviar datos informativos (por ejemplo, descripción del servidor, página principal, tiempo de actividad, cantidad de usuarios) a servidores de seguimiento. Para desactivarlo, configura `track = 0` en `conf/bnetd.conf`.

## Clientes compatibles

* **WarCraft 2: Battle.net Edition:** 2.02a, 2.02b
* **WarCraft 3: Reign of Chaos \*:** 1.27b
* **WarCraft 3: The Frozen Throne \*:** 1.27b
* **StarCraft:** 1.08, 1.08b, 1.09, 1.09b, 1.10, 1.11, 1.11b, 1.12, 1.12b, 1.13, 1.13b, 1.13c, 1.13d, 1.13e, 1.13f, 1.14, 1.15, 1.15.1, 1.15.2, 1.15.3, 1.16, 1.16.1, 1.17.0, 1.18.0
* **StarCraft: Brood War:** 1.08, 1.08b, 1.09, 1.09b, 1.10, 1.11, 1.11b, 1.12, 1.12b, 1.13, 1.13b, 1.13c, 1.13d, 1.13e, 1.13f, 1.14, 1.15, 1.15.1, 1.15.2, 1.15.3, 1.16, 1.16.1, 1.17.0, 1.18.0
* **Diablo:** 1.09, 1.09b
* **Diablo 2:** 1.10, 1.11, 1.11b, 1.12a, 1.13c, 1.14a, 1.14b, 1.14c, 1.14d
* **Diablo 2: Lord of Destruction:** 1.10, 1.11, 1.11b, 1.12a, 1.13c, 1.14a, 1.14b, 1.14c, 1.14d
* **Westwood Chat Client:** 4.221
* **Command & Conquer:** Win95 1.04a (usando Westwood Chat)
* **Command & Conquer: Red Alert:** Win95 2.00 (usando Westwood Chat), Win95 3.03
* **Command & Conquer: Red Alert 2:** 1.006
* **Command & Conquer: Tiberian Sun:** 2.03 ST-10
* **Command & Conquer: Tiberian Sun Firestorm:** 2.03 ST-10
* **Command & Conquer: Yuri's Revenge:** 1.001
* **Command & Conquer: Renegade:** 1.037
* **Nox:** 1.02b
* **Nox Quest:** 1.02b
* **Dune 2000:** 1.06
* **Emperor: Battle for Dune:** 1.09

*\* Los clientes de WarCraft 3 no pueden conectarse a servidores PvPGN sin una modificación del lado del cliente, mediante herramientas como W3L, para desactivar la verificación de firma del servidor.*

## Hospedaje en LAN o VPS

Si tu proveedor de VPS no asigna una IP pública directa, o si hospedas desde tu casa detrás de un NAT, necesitas configurar la traducción de rutas en `address_translation.conf`. La dirección pública se envía como dirección del servidor de rutas a los clientes del juego al buscar partidas.

Cómo descargar el proyecto

Este repositorio usa Git LFS para los archivos grandes (parches .mpq de WarCraft 3). Por eso es importante descargarlo de la forma correcta.

✅ Método correcto: clonar con Git
Instalá Git si no lo tenés: https://git-scm.com/downloads
Abrí una terminal (Git Bash, PowerShell o CMD)
Navegá a la carpeta donde querés guardar el proyecto, por ejemplo:
bash
cd Desktop
Cloná el repositorio:
bash
git clone https://github.com/Slyhark-Dev/PvPGN-Rehost.git

Ejemplo de cómo se ve en consola:

C:\Users\TuUsuario> cd Desktop
C:\Users\TuUsuario\Desktop> git clone https://github.com/Slyhark-Dev/PvPGN-Rehost.git
Cloning into 'PvPGN-Rehost'...
remote: Enumerating objects: 350, done.
remote: Counting objects: 100% (350/350), done.
remote: Compressing objects: 100% (280/280), done.
Receiving objects: 100% (350/350), 4.20 MiB | 2.15 MiB/s, done.
Filtering content: 100% (10/10), 385.30 MiB | 8.40 MiB/s, done.
C:\Users\TuUsuario\Desktop>

Cuando termine, vas a tener la carpeta PvPGN-Rehost con todo el contenido completo, incluyendo los archivos .mpq en su tamaño real.

❌ Método que NO funciona: botón "Download ZIP"

El botón verde Code → Download ZIP de GitHub no incluye el contenido real de los archivos LFS. Los .mpq van a aparecer con solo 1 KB de tamaño (rotos e inutilizables). Esta es una limitación de GitHub, no un error del repositorio.

Si ya descargaste el ZIP y los archivos de la carpeta files/ pesan casi nada, es por este motivo. Solución: borrá esa copia y usá git clone en su lugar.

## Soporte y licencia

Crea un issue si tienes preguntas o sugerencias sobre esta versión personalizada.

Este programa es software libre distribuido bajo la GNU General Public License versión 2.
