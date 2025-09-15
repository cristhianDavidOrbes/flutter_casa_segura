# Casa Segura (flutter_casa_segura)

Aplicación Flutter para un sistema de seguridad doméstica que se integrará con módulos ESP32. El proyecto actualmente implementa autenticación (Appwrite), UI básica de login/registro, y pantallas principales para la app. Esta documentación describe la estructura actual, cómo ejecutar el proyecto y pautas de integración con los ESP32.

## Resumen
- Framework: Flutter (soporta Android / iOS / Web / Desktop).
- Backend de autenticación: Appwrite (email/password y OAuth).
- Integración hardware prevista: módulos ESP32 (MQTT / HTTP / WebSocket).
- Estado actual: UI de login/registro, home con cierre de sesión y servicios Appwrite básicos.

## Estructura principal
- [lib/main.dart](lib/main.dart) — punto de entrada; define [`MyApp`](lib/main.dart).  
- [lib/screens/login_screen.dart](lib/screens/login_screen.dart) — pantalla de login; componente [`LoginScreen`](lib/screens/login_screen.dart).  
- [lib/screens/register_screen.dart](lib/screens/register_screen.dart) — pantalla de registro; componente [`RegisterScreen`](lib/screens/register_screen.dart).  
- [lib/screens/home_page.dart](lib/screens/home_page.dart) — pantalla principal después del login; componente [`HomePage`](lib/screens/home_page.dart).  
- [lib/services/appwrite_service.dart](lib/services/appwrite_service.dart) — cliente simple para Appwrite: [`AppwriteService`](lib/services/appwrite_service.dart).  
- [lib/config/environment.dart](lib/config/environment.dart) — configuración pública del proyecto Appwrite: [`Environment`](lib/config/environment.dart).  
- [lib/circle_state.dart](lib/circle_state.dart) — estado/animaciones reutilizables: [`CircleStateNotifier`](lib/circle_state.dart).  
- [lib/widgets/background.dart](lib/widgets/background.dart) — widget de fondo animado: [`Background`](lib/widgets/background.dart).

## Qué hace hoy la app
- Registro de usuarios contra Appwrite (email/password). Ver [`RegisterScreen`](lib/screens/register_screen.dart).
- Login con email/password y OAuth (Google/GitHub) usando flujo de callback web (FlutterWebAuth2). Ver [`LoginScreen`](lib/screens/login_screen.dart).
- Sesión de usuario con Appwrite y cierre de sesión (en [`HomePage`](lib/screens/home_page.dart)).
- Servicio de ejemplo para encapsular llamadas a Appwrite: [`AppwriteService`](lib/services/appwrite_service.dart).
- Variables de entorno del cliente Appwrite en [`Environment`](lib/config/environment.dart).

## Configuración necesaria
1. Instalar Flutter (compatible con la versión usada en el proyecto).
2. Dependencias del proyecto: ejecutar
   ```sh
   flutter pub get
   ```
3. Configurar Appwrite:
   - Ajustar `lib/config/environment.dart` con tu endpoint y projectId si es distinto. Actualmente usa:
     - projectId en [`Environment`](lib/config/environment.dart).
     - endpoint en [`Environment`](lib/config/environment.dart).
   - Asegurar que en Appwrite estén habilitados: Accounts, OAuth providers (Google/GitHub) y CORS/redirecciones necesarias para FlutterWebAuth2.

## Ejecutar la app
- Modo debug en dispositivo/emulador:
  ```sh
  flutter run
  ```
- Web:
  ```sh
  flutter run -d chrome
  ```
- Desktop (si tienes las toolchains):
  ```sh
  flutter run -d windows   # o macos / linux
  ```

## Autenticación
- Email/password: implementado en [`LoginScreen`](lib/screens/login_screen.dart) y [`RegisterScreen`](lib/screens/register_screen.dart) usando Appwrite SDK.
- OAuth: el flujo abre el navegador y recibe fragmento con `userId` y `secret`, luego crea la sesión con Appwrite (ver implementación en [`LoginScreen`](lib/screens/login_screen.dart)).

## Integración con ESP32 (guía rápida)
Objetivo: recibir eventos (sensores, alarmas) y enviar comandos a los ESP32 desde la app.

Opciones recomendadas:
1. MQTT (recomendado para telemetría y control en tiempo real)
   - Correr un broker (ej. Mosquitto) en red local o en la nube.
   - ESP32 se conecta al broker y publica/suscribe a topics (ej. casa/puerta, casa/motion).
   - La app Flutter puede usar paquetes MQTT (p.ej. mqtt_client) para suscribirse/ publicar a topics.
   - Seguridad: usar autenticación en el broker y TLS si es público.

2. HTTP/REST
   - ESP32 expone endpoints REST y la app hace peticiones HTTP.
   - Adecuado para comandos puntuales pero menos eficiente para datos en tiempo real.

3. WebSocket
   - Para comunicación bidireccional en tiempo real sin broker externo.

Sugerencias:
- Definir mensajes JSON estándar (p. ej. { "deviceId": "...", "type": "motion", "value": true }).
- Autenticación: usar tokens firmados si los módulos se exponen públicamente.
- Para telemetría histórica y control de reglas, considerar integrar Appwrite Databases o una función/servicio backend que reciba eventos desde los ESP32 y notifique a la app (webhooks o push).

## Buenas prácticas y próximos pasos
- Mover valores sensibles a variables de entorno (no subir secretos).
- Añadir manejo de errores más robusto en los servicios (retry, logs).
- Implementar tests unitarios y widget tests (hay un ejemplo en `test/widget_test.dart`).
- Añadir soporte y documentación para flujos ESP32 concretos (ejemplos de firmware y topics MQTT).
- Considerar usar Appwrite Functions para procesar eventos entrantes desde ESP32 y almacenar registros.

## Recursos en el repo
- Código principal: [lib/main.dart](lib/main.dart) (`MyApp`)  
- Login: [lib/screens/login_screen.dart](lib/screens/login_screen.dart) (`LoginScreen`)  
- Registro: [lib/screens/register_screen.dart](lib/screens/register_screen.dart) (`RegisterScreen`)  
- Home: [lib/screens/home_page.dart](lib/screens/home_page.dart) (`HomePage`)  
- Servicio Appwrite: [lib/services/appwrite_service.dart](lib/services/appwrite_service.dart) (`AppwriteService`)  
- Config: [lib/config/environment.dart](lib/config/environment.dart) (`Environment`)  

## Licencia
- Proyecto inicial sin licencia especificada. Añadir LICENSE si procede.
