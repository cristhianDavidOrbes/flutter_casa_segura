# Casa Segura

Aplicacion Flutter para monitoreo y control de dispositivos ESP32 orientados a seguridad domestica. La app combina autenticacion con Supabase, provisionamiento por SoftAP, descubrimiento LAN via mDNS y paneles en tiempo real para ver telemetria y actuar sobre los equipos.

## Vision general
- Flutter 3.9.x (Material 3, GetX, Rive) con soporte Android, iOS, web y desktop.
- Supabase provee autenticacion email/password, almacenamiento de dispositivos, lecturas en tiempo real (`live_signals`) y cola de comandos (`actuator_commands`).
- Provisionamiento inicial via Wi-Fi SoftAP usando `wifi_iot` y `permission_handler` para conectar el telefono al AP del ESP32 y enviarle SSID/clave junto con tickets generados desde Supabase.
- Descubrimiento LAN mediante mDNS (`LanDiscoveryService`) con canal nativo Android para adquirir `MulticastLock` y escanear `_casa._tcp.local`.
- UI principal (`HomePage`) que mezcla datos locales SQLite (familia, historial) con presencia en vivo, tarjetas de dispositivos y accesos rapidos a detalle y provisionamiento.
- Persistencia local combinada: SQLite (`AppDb`) para familia, dispositivos, eventos e historicos; Hive (`AiCommentStore`) para comentarios generados por IA asociados a eventos.
- Pantalla de detalle (`DeviceDetailPage`) que consulta HTTP directo, consume streams MJPEG, suscribe senales Supabase y permite enviar comandos a actuadores.

## Arquitectura y carpetas
- `lib/main.dart`: inicializa dotenv (`.env`), Hive, Supabase, registra `AuthBinding` y lanza `SplashScreen` que redirige a login o home.
- `lib/core/`: configuracion comun (`core/config/environment.dart`), estado global (`core/state/circle_state.dart`), widgets compartidos (por ejemplo `ThemeToggleButton`, `DeviceCard`), errores.
- `lib/features/auth/`: implementacion clean architecture para autenticacion (datasource Supabase, repositorio, usecases, controlador GetX y pantallas login/registro/forgot/reset). Incluye `DeeplinkService` para manejar enlaces `casasegura://reset` y HTTPS.
- `lib/features/home/`: UI posterior al login, integra paneles, carrusel de dispositivos y bottom nav. Reutiliza servicios de descubrimiento y provisioning.
- `lib/screens/`: pantallas aun en proceso de migracion (devices list, detalle, provisioning, splash) agrupadas por funcionalidades.
- `lib/services/`: logica de red/IoT (mDNS, SoftAP provisioning, device control HTTP, consumo Supabase en tiempo real).
- `lib/data/`: almacenamiento local. `data/local/app_db.dart` define tablas SQLite para familia, dispositivos, eventos e interacciones; `data/hive/` contiene el modelo `AiComment` y su store.
- `lib/repositories/device_repository.dart`: capa de acceso a `devices` en Supabase (listado, actualizacion de presencia, olvido con factory reset opcional).
- `supabase/schema2.sql`: definicion completa de perfiles, devices, live_signals, actuators, actuator_commands, politicas RLS y RPC de onboarding. `schema.sql` conserva la version reducida (solo perfiles y dispositivos).
- `android/app/src/main/kotlin/.../MainActivity.kt`: canal `lan_discovery` para adquirir o liberar `MulticastLock`. `AndroidManifest.xml` declara permisos de red, ubicacion y `NEARBY_WIFI_DEVICES`.

## Dependencias clave
- `supabase_flutter` para autenticacion, realtime y RPC.
- `wifi_iot` y `permission_handler` para gestion Wi-Fi en Android.
- `multicast_dns` para descubrir equipos en la LAN.
- `sqflite` y `path_provider` para base local; `hive` y `hive_flutter` para cache de comentarios.
- `app_links` para escuchar deep links y app links verificados.
- `rive` para animaciones en splash y pantallas de autenticacion.

## Requisitos previos
1. Flutter SDK 3.9.x (o superior compatible) y toolchain para las plataformas objetivo.
2. Cuenta Supabase con proyecto activo y permisos para crear tablas y politicas.
3. Android: minimo API 21; para provisioning se recomienda probar en dispositivo fisico con Wi-Fi.
4. iOS, web y desktop pueden requerir permisos adicionales que aun no estan implementados.

## Configuracion rapida
1. Clona el repo y entra en `flutter_casa_segura`.
2. Crea un archivo `.env` con las variables requeridas:
   ```env
   SUPABASE_URL=https://TU_PROYECTO.supabase.co
   SUPABASE_ANON_KEY=tu_key_publica
   SUPABASE_RESET_REDIRECT=casasegura://reset
   SUPABASE_EMAIL_REDIRECT=https://tu-dominio/reset
   # Opcional: usa credenciales existentes de un dispositivo Supabase
   DEVICE_FALLBACK_ID=b6b30a93-98eb-4f3e-9455-aa545f4b31f5
   DEVICE_FALLBACK_KEY=patata
   ```
   Ajusta los valores segun la configuracion de tu instancia Supabase y URLs permitidas.
3. Instala dependencias:
   ```sh
   flutter pub get
   ```
4. (Opcional) Define credenciales de dispositivo fijas en el `.env` si quieres reutilizar un hardware ya registrado y evitar generar tickets nuevos:
   ```env
   DEVICE_FALLBACK_ID=b6b30a93-98eb-4f3e-9455-aa545f4b31f5
   DEVICE_FALLBACK_KEY=patata
   ```
   Si dejas esos campos vacÃ­os, la app llamarÃ¡ a la RPC `generate_device` y crearÃ¡ un registro nuevo en `public.devices`.
5. Conecta un dispositivo o emulador y ejecuta:
   ```sh
   flutter run
   ```

## Configuracion de Supabase
1. Ejecuta `supabase/schema2.sql` en el SQL editor para crear extensiones, tablas, politicas y RPCs necesarios (onboarding, live signals, actuators, cola de comandos). Usa `schema.sql` si solo necesitas perfiles y devices basico.
2. En Authentication > Providers habilita Email con verificacion.
3. En Authentication > URL Configuration agrega los redirects declarados (`casasegura://reset`, `https://tu-dominio/reset`, etc.).
4. Desde el firmware ESP32 consume la RPC `generate_device` para obtener `device_key`, usa `device_next_command` y `device_command_done` para sincronizar comandos y envia la cabecera `x-device-key` con ese secreto.

### Provisionamiento paso a paso
1. Si el firmware ya tenÃ­a credenciales guardadas, envÃ­a `1` por el monitor serie para ejecutar `enterSoftApNow()` y volver al modo SoftAP.
2. Desde la app:
   - Busca el AP `CASA-ESP_xxxx`.
   - ConÃ©ctate y abre la pantalla de provisionamiento.
   - Introduce los datos Wi-Fi del hogar y un alias **Ãºnico** para el dispositivo. Un alias repetido reutiliza el ticket cacheado.
3. La app llamarÃ¡ a `generate_device` (crea/actualiza la fila en `public.devices`). SÃ³lo si la llamada falla usarÃ¡ `DEVICE_FALLBACK_ID/KEY`.
4. El endpoint `/provision` recibe un JSON con `device_id`, `device_key`, `supabase_url` y `supabase_key` que el ESP32-CAM guarda en `Preferences`.
5. Reinicia el dispositivo; en los logs deberÃ­as ver `[DEBUG] deviceKey=...` y, si todo estÃ¡ correcto, las peticiones HTTP a Supabase devolverÃ¡n 200/204 en lugar de 403.

Si quieres registrar un hardware nuevo en Supabase, asegÃºrate de **eliminar** `DEVICE_FALLBACK_ID/KEY` del `.env` (o dejar los valores vacÃ­os) antes de provisionar. De ese modo `generate_device` insertarÃ¡ el registro en la tabla `devices` y la polÃ­tica RLS permitirÃ¡ la conexiÃ³n.

## Provisionamiento y flujo IoT
- `ProvisioningScreen` guia al usuario: detecta AP `CASA-ESP_xxxx`, conecta el telefono, escanea redes vecinas y envia credenciales, nombre y ticket al endpoint del dispositivo (`/provision`). Maneja permisos, validacion de respuesta y limpieza de estado.
- `LanDiscoveryService` detecta dispositivos via mDNS. Emite stream con metadata (`name`, `type`, `deviceId`, `host`, `ip`) mientras se ejecuta; el canal nativo gestiona `MulticastLock` para que el escaneo funcione en Android.
- `DeviceDetailPage` intenta ping directo (`/ping`, `/info`), lee datos JSON (`/sensors`, `/status`, `/data`), reproduce streams MJPEG, y sincroniza con Supabase (`live_signals`, `actuators`) para mostrar telemetria y permitir toggles tipo servo mediante `RemoteDeviceService.enqueueCommand`. Fuera de la LAN cae automaticamente al snapshot Supabase y reporta el ultimo latido sin considerar error fatal.
- `DeviceRepository` sincroniza `devices` en Supabase, actualiza `last_seen_at` y expone `forgetAndReset`, que primero intenta `/factory_reset` por IP local y, si falla, asegura un actuador `system`, encola la orden remota y marca la tabla `device_remote_flags` para que el firmware entre en SoftAP aun si no está en la misma LAN.

## Persistencia local
- `AppDb` (Sqflite) define tablas `family_members`, `devices`, `persons_of_interest`, `events` y helpers de joins para la UI de Home. Incluye metodos para CRUD, estadisticas y limpieza.
- `AiCommentStore` (Hive) guarda comentarios generados por IA con indices por dispositivo y evento. Se inicia en `main.dart` tras registrar `AiCommentAdapter`.

## Deep links y autenticacion
- `AuthBinding` registra `AuthController` y los casos de uso (`SignInWithEmail`, `SignUpWithEmail`, `SendPasswordReset`, `ResendEmailConfirmation`, `UpdatePassword`, `SignOut`).
- `DeeplinkService` usa `app_links` para procesar `casasegura://reset` y `https://redirrecion-home.vercel.app/reset`. Al recibir tipo `recovery` abre `ResetPasswordScreen` y para `signup` refresca la sesion y vuelve al login con feedback.
- Las pantallas de auth emplean `ThemeToggleButton`, animaciones Rive (`assets/rive/registro.riv`) y `CircleStateNotifier` para transiciones.

## Ejecucion y pruebas
- Ejecutar: `flutter run` (elige plataforma).
- Analisis: `flutter analyze` (usa `analysis_options.yaml` basado en Flutter lints 5.x).
- Pruebas: `flutter test` (por ahora solo `test/widget_test.dart`; se recomienda ampliar cobertura).

## Siguientes pasos sugeridos
- Migrar el resto de pantallas de `lib/screens/` a modulos `features/*` y abstraer servicios compartidos.
- Implementar soporte equivalente en iOS (multicast, wifi) o condicionar funciones cuando no esten disponibles.
- Anadir pruebas unitarias para servicios Supabase/provisioning y pruebas de integracion para el flujo completo de onboarding.
- Incorporar MQTT o WebSocket como canal alterno en `RemoteDeviceService` si el firmware lo expone.
- Configurar pipeline CI/CD (lint, pruebas, build) y definir licencia del proyecto.

## Recursos visuales
- `flutter_01.png`: captura del dashboard actual.
- Animaciones Rive en `assets/rive/` (`cargando.riv`, `camara.riv`, `registro.riv`) usadas en splash y pantallas de autenticacion.

---
Consulta los comentarios en `lib/services/provisioning_service.dart`, `lib/services/lan_discovery_service.dart` y `lib/services/remote_device_service.dart` para detalles sobre endpoints esperados, tiempos de espera y supuestos implementados en la app.

## PrÃ³ximos ajustes solicitados (para la siguiente sesiÃ³n)

- **Estado en tiempo real en `DeviceDetailPage`:**  
  . Dejar de depender del `lastSeenAt` recibido al navegar. El indicador conectado/desconectado debe alimentarse con eventos en vivo (mDNS, Supabase) mientras la pantalla estÃ¡ abierta.  
  . Acelerar el botÃ³n **Ping** (timeout < 2â€¯s) y mostrar mensaje claro cuando falle.

- **Streaming de cÃ¡mara:**  
  . Revisar `_MjpegView` para reducir el retardo inicial (obtener un snapshot inmediato y luego enganchar el stream MJPEG).  
  . Ajustar la lÃ³gica de reconexiÃ³n con backoff suave y limpiar recursos al salir.

## Notas de integraciÃ³n recientes (oct-2025)
- Nueva RPC device_upsert_actuator (security definer) para que los dispositivos aseguren su actuador sin chocar con las politicas RLS. Ejecuta schema2.sql en tu proyecto Supabase antes de flashear el firmware actualizado.
- ESP8266: se ampliaron los buffers persistidos (supaAnon -> 256 chars) para evitar que el anon key se trunque tras reinicios.
- Nuevo firmware detector (mic + ultrasonido) en dispositivos/detector_softap_provision.ino con provisiÃ³n Supabase.
- Detector: imprime en Serial `[SENS] sound_do=... sound_evt=... ultra_cm=... ultra_ok=...` y envÃ­a heartbeat cada 1 s; Home Page replica esos datos en la tarjeta y detalle.
- Detector: ahora expone `/apmode`, `/factory` y `/factory_reset` tambiÃ©n en modo STA y procesa la transiciÃ³n a SoftAP despuÃ©s de responder HTTP, habilitando el botÃ³n "Olvidar" de la app. Reflashea los detectores para tomar el cambio.
- Pendiente por mejorar: detectar ping/reinicio remoto cuando el equipo solo tiene IP privada; hoy se muestra el error pero falta UX para casos fuera de la LAN.
- Detector y cámara registran un actuador `system` y atienden `device_next_command`; el botón Olvidar encola `factory_reset` en Supabase cuando la IP local no está disponible.
- DeviceDetailPage ahora cae a los datos de `live_signals` en Supabase cuando el equipo está fuera de la red local. El botón Ping crea una solicitud remota, espera el ACK y muestra el último latido registrado. El botón Olvidar detecta `forget_status='done'` antes de eliminar el registro local.
- La tabla `device_remote_flags` coordina acciones remotas (ping, olvido). La app marca los flags y el firmware (ESP32) consulta la RPC `device_take_remote_flags` cada 10s. Al recibir `forget_requested`, el firmware invoca `device_mark_remote_forget_done()` y reinicia el micro (`ESP.restart()`), limpiando credenciales y volviendo a SoftAP sin intervención manual.
- Nueva RPC `device_current_state` devuelve en un JSON compacto las señales activas de `live_signals`; la app la usa como fallback cuando el acceso HTTP directo falla. Ejecuta `schema2.sql` en tu instancia Supabase tras actualizar.
- Los dispositivos activos del Home se eligen desde la pantalla *Dispositivos* (interruptor "Usar en Inicio"); la IA solo consume esos equipos.
- **Siguiente tarea**: depurar el actory_reset remoto cuando el dispositivo sigue en línea pero no enciende el SoftAP. Revisar que ctuator_commands pase de pending->taken, que el firmware imprima [SUPA] factory_reset recibido y que se ejecute enterSoftApNow(). Documentar hallazgos aquí antes de nuevos cambios.
- DeviceDetailPage: la pantalla ahora detecta el tipo del equipo y muestra solo los controles relevantes (detector -> sonido/distancia, servo -> toggle, camara -> stream o snapshot). Actualiza la app para ver la vista adaptativa.
- HomePage: las tarjetas de camara y detector comparten altura fija; la miniatura MJPEG queda centrada y el indicador "Hace ..." permanece visible al pie. Distancia y Sonido se apilan en columna para evitar desbordes.
- SplashScreen: la animacion del splash se reemplazo por un video (`assets/carga.mp4`) reproducido en loop dentro de un contenedor redondeado con borde translúcido.



- El firmware de referencia para los servos (SoftAP + Supabase) se guarda ahora en irmware/servo_softap/servo_softap_provision.ino. Edita y versiona ese archivo aquÃ­ cada vez que ajustes el comportamiento del dispositivo.
- Si durante la provisiÃ³n el monitor serie del ESP muestra HTTP 401 Invalid API key, revisa SUPABASE_URL y SUPABASE_ANON_KEY en .env, reprovisiona el equipo y confirma en la tabla ctuators que existe una fila kind = 'servo' para ese device_id.
- El sketch imprime trazas [SUPA] ... cuando intenta registrar el actuador. Guarda en este README cualquier cÃ³digo de error que aparezca antes de continuar con nuevas tareas.

AsegÃºrate de documentar cualquier decisiÃ³n adicional en este README cuando continÃºes con la implementaciÃ³n.
