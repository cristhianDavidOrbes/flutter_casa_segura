# Casa Segura (flutter_casa_segura)

Aplicacion Flutter para un sistema de seguridad domestica con ESP32. La app usa Supabase como backend de autenticacion y esta organizada bajo una estructura de clean architecture (core + features).

## Resumen
- Framework: Flutter (Android / iOS / Web / Desktop).
- Backend de autenticacion: Supabase (email/password con verificacion por correo).
- Integracion prevista: modulos ESP32 (MQTT / HTTP / WebSocket).
- Estado actual: flujo completo de login/registro/reset con Supabase, pantalla principal, descubrimiento LAN y pantallas de provisionamiento.

## Estructura principal
- `lib/main.dart`: punto de entrada; inicializa dotenv, Hive, Supabase y bindings (`AuthBinding`).
- `lib/core/`: configuraciones y utilidades compartidas (p. ej. `core/config/environment.dart`, `core/state/circle_state.dart`, `core/presentation/widgets`).
- `lib/features/auth/`: modulo de autenticacion (domain/data/usecases/controller + paginas de login/register/forgot/reset y `infrastructure/deeplink_service.dart`).
- `lib/features/home/`: pagina principal despues del login.
- `lib/screens/`: pantallas restantes aun por migrar (devices, provisioning, splash).
- `lib/data/local/app_db.dart`: capa local con SQLite (sqflite) para dispositivos/eventos.
- `supabase/schema.sql`: script SQL para preparar tablas/policies en Supabase.

## Configuracion
1. Instalar Flutter (version estable 3.9.x o compatible).
2. Clonar el repo y posicionarse en `flutter_casa_segura`.
3. Crear un archivo `.env` en la raiz con:
   ```env
   SUPABASE_URL=https://xqmydyesafnhomhzewsq.supabase.co
   SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhxbXlkeWVzYWZuaG9taHpld3NxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyNzY0OTgsImV4cCI6MjA3NDg1MjQ5OH0.YFteDpgiU87dwNq2PIaDrm28h5w6nu0T0mLEUjmTrmU
   SUPABASE_RESET_REDIRECT=casasegura://reset
   ```
   (ajusta URL/keys y el esquema de deep link segun tu proyecto).
4. Ejecutar `flutter pub get`.
5. En tu proyecto Supabase, ejecutar el SQL de `supabase/schema.sql` para crear la tablas `profiles` y `devices`, las politicas RLS y los triggers de sincronizacion.
6. Configurar en Supabase el redirect URL `casasegura://reset` en Authentication -> URL Configuration.

## Ejecutar
```sh
flutter run          # android/ios/web/desktop segun dispositivo
```

## Autenticacion
- `AuthBinding` registra `AuthController` con los usecases (`SignInWithEmail`, `SignUpWithEmail`, `SendPasswordReset`, `UpdatePassword`, `SignOut`).
- `AuthController` expone metodos para login, registro, cambio de contrasena y logout; los widgets llaman al controller y muestran mensajes con `AppFailure` en caso de error.
- `DeeplinkService` procesa el enlace de recuperacion (`casasegura://reset#...`) y llama a `SupabaseClient.auth.getSessionFromUrl` antes de navegar a `ResetPasswordScreen`.
- `ForgotPasswordScreen` envia el correo de recuperacion y `ResetPasswordScreen` actualiza la contrasena y cierra sesion.

## Clean architecture (resumen)
- **core/**: piezas compartidas (config, widgets, state, errores).
- **features/auth/**: capas domain/data/presentation, controller con usecases y paginas UI.
- **features/home/**: pagina principal (logout usa `AuthController`).
- Otras pantallas aun viven en `lib/screens/` y pueden migrarse gradualmente.

## Recursos para ESP32
- `lib/services/lan_discovery_service.dart`: deteccion via mDNS.
- `lib/services/provisioning_service.dart`: provisionamiento SoftAP.
- `lib/screens/devices_page.dart` y `lib/screens/provisioning_screen.dart`: UI para estas funciones.

## Siguientes pasos sugeridos
- Migrar las pantallas restantes a la estructura de features.
- Añadir tests unitarios e instrumentados para auth y servicios LAN.
- Integrar MQTT/WebSocket con los modulos ESP32.
- Crear workflows de CI/CD y definir una licencia.


