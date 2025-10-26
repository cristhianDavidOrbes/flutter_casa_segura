# Casa Segura – Ecosistema de seguridad doméstica

Aplicación Flutter que combina cámaras y sensores IoT con IA (Gemini 2.5 Flash Lite), almacenamiento local (Hive/SQLite) y sincronización en Supabase para ofrecer monitoreo inteligente, chat asistido y alertas en tiempo real.

---

## Requisitos previos
- Flutter 3.22.x (Dart 3.9) con `flutter` y `dart` en el PATH.
- Supabase CLI 1.135 o superior para aplicar el esquema `supabase/schema2.sql`.
- Cuenta de Supabase (proyecto + anon key) y acceso al panel.
- Proyecto de Firebase con Cloud Messaging habilitado.
- API key de Gemini con acceso al modelo `gemini-2.5-flash-lite`.
- Opcional: placas ESP32 (modo SoftAP) y red local para probar la provisión de dispositivos.

---

## Configuración rápida
1. **Instalar dependencias**
   ```bash
   flutter pub get
   ```

2. **Variables de entorno**
   - Copia `.env` o crea uno nuevo con:
     ```
     SUPABASE_URL=https://<tu-proyecto>.supabase.co
     SUPABASE_ANON_KEY=<anon-key>
     SUPABASE_RESET_REDIRECT=casasegura://reset
     SUPABASE_EMAIL_REDIRECT=https://tudominio/reset
     GEMINI_API_KEY=<clave-gemini>
     ```
   - La app ejecuta `Environment.ensureLoaded()` al iniciar; si faltan valores se lanza un `StateError`.

3. **Configurar Supabase**
   ```bash
   supabase db reset --file supabase/schema2.sql
   ```
   El esquema incluye:
   - Dispositivos, señales en vivo, actuadores y banderas remotas.
   - `security_events` con columnas para ID de familiar e indicadores de horario.
   - `user_push_tokens` con políticas RLS para upsert/borrado seguro.
   - Funciones RPC utilizadas por los dispositivos y la app.

4. **Configurar Firebase Cloud Messaging**
   - Ejecuta `flutterfire configure` (requiere `dart pub global activate flutterfire_cli`).
   - Copia `android/app/google-services.json` y `ios/Runner/GoogleService-Info.plist`.
   - Verifica que `Firebase.initializeApp()` se complete antes de registrar tokens (lo maneja `PushNotificationService`).

5. **Assets y adaptadores locales**
   - Asegúrate de que los assets `.riv` y videos listados en `pubspec.yaml` estén presentes.
   - Hive registra manualmente los adapters (`AiCommentAdapter`, `SecurityEventAdapter`, `SecurityChatMessageAdapter`) en `main.dart`.

---

## Localización y traducciones

- Las cadenas viven en `lib/core/localization/app_translations.dart` dentro de los mapas `es` y `en` usados por GetX (`GetMaterialApp.translations`).
- **Edita siempre el archivo en UTF-8** (sin BOM). En VS Code agrega `"files.encoding": "utf8"` y `"files.autoGuessEncoding": false`. Evita copiar texto desde Word u otros editores que usen Windows-1252.
- Si un carácter se ve como `Ã` o `�`, vuelve a guardar el archivo en UTF-8 y reescribe la cadena correcta (por ejemplo `Configuración`).
- Para añadir un idioma duplica el mapa, traduce las cadenas y registra el locale (`supportedLocales` y `fallbackLocale`) en `main.dart`.
- Después de modificar textos ejecuta `flutter run` y cambia el idioma desde **Configuración → Idioma** para validar que los textos se muestren correctamente.

---

## Ejecución y validaciones
- **Iniciar la app**
  ```bash
  flutter run
  ```
- **Analizador**
  ```bash
  flutter analyze
  ```
- **Pruebas manuales**
  - Revisar la pantalla Home y confirmar la carga de familiares, dispositivos y notificaciones.
  - Disparar `SecurityMonitorService.instance.start()` (ya se invoca en `HomePage.initState`).
  - Comprobar que los eventos se persisten en Hive y se replican a Supabase con los campos de familia.
  - Verificar que `PushNotificationService.syncTokenWithUser()` inserta/actualiza registros en `user_push_tokens`.

---

## Flujo de provisión de dispositivos
1. `ProvisioningService` busca redes SoftAP con prefijo `CASA-ESP_`.
2. Tras conectar, envía credenciales Wi-Fi y claves de Supabase/Gemini.
3. El firmware debe ejecutar `upsert_live_signal`, `device_take_remote_flags` y confirmar comandos.
4. `LanDiscoveryService` (mDNS/Multicast) mantiene estado de dispositivos en Home.

Consulta los sketches en `dispositivos/` para ejemplos ESP32.

---

## Estado del proyecto y pendientes

### Monitoreo e IA
- [x] Motor de detección con ML Kit y confirmación de rostros/objetos.
- [x] Descripción mediante Gemini Vision y análisis de coincidencia con familiares.
- [x] Persistencia local (Hive/SQLite) y sincronización condicional con Supabase.

### Interfaz
- [x] Home con accesos rápidos, carrusel de dispositivos y familia.
- [x] Chat IA especializado en seguridad.
- [x] Lista/detalle de notificaciones con imagen y contexto de familia.
- [x] Selector global de idioma (es/en/hi) usando GetX + GetStorage.
- [ ] Localización completa en pantallas de provisión/dispositivos.

### Integraciones
- [x] Registro de tokens FCM en `user_push_tokens`.
- [x] Deep links para recuperación de contraseña / verificación (App Links + Supabase auth).
- [ ] Ajustes avanzados (sensibilidad, frecuencia por dispositivo) y reportes semanales.
- [ ] Cobertura de pruebas unitarias/integración.

---

## Buenas prácticas y notas
- Mantén los archivos `.env` y claves fuera del control de versiones públicos.
- Los nuevos campos en `SecurityEvent` (`familyMemberId`, `familyMemberName`, `familyScheduleMatched`) requieren limpiar cajas Hive antiguas si existen entradas previas sin esos campos.
- Para ambientes de prueba puedes ejecutar `supabase start` y apuntar la app al servicio local (actualiza `.env` y certificados si aplica).
- Verifica permisos de cámara, ubicación y Wi-Fi en Android antes de usar provisión y detección.

---

## Recursos adicionales
- [Google ML Kit – Face & Object Detection](https://developers.google.com/ml-kit/vision)
- [Supabase Docs](https://supabase.com/docs)
- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)
- [Gemini API](https://ai.google.dev/)
