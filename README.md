# Guia rapida de pendientes

> Este bloque se mantiene en espanol para evitar inconsistencias con las traducciones de la app.

Antes de continuar con mas desarrollo revisa y ejecuta estos pasos en orden (incluye estado actual y referencias rapidas):

1. **Realtime**  
   - Estado: OK. Los `watch*` ahora delegan en `_pollingStream` con peticiones REST en `lib/services/remote_device_service.dart:130-240`, evitando Realtime de Supabase.
   - Mantener: si se introducen nuevos flujos, replicar el patron de polling con backoff.
2. **Actuadores remotos**  
   - Estado: PENDIENTE. Aunque la app bloquea `factory_reset` remoto (`lib/services/remote_device_service.dart:202-215`), el firmware sigue registrando el actuador `system_control` (`dispositivos/camara_computacion_ubicua.ino:627-668`). Falta decidir si se elimina ese registro o se documenta la excepcion.
   - Mantener: olvido de dispositivos solo via red local (`lib/services/device_control_service.dart:11`).
3. **Capturas de camara**  
   - Estado: OK. Los ESP32-CAM usan `SNAPSHOT_INTERVAL_MS = 4000` (`dispositivos/camara_computacion_ubicua.ino:40`), dentro del intervalo seguro.
   - Mantener: subir a 5000 ms si se agregan mas camaras a la misma red.
4. **Monitor adaptativo**  
   - Estado: OK. `SecurityMonitorService` alterna 5 s en primer plano y 18 s en segundo plano (`lib/features/security/application/security_monitor_service.dart:42-76`).
   - Mantener: si cambian los requisitos de background, ajustar ambos temporizadores en conjunto.
5. **Traducciones**  
   - Estado: OK. Las cadenas viven en `lib/core/localization/app_translations.dart` (es/en). No se detectaron strings sueltos nuevos.
   - Mantener: cuando se agreguen textos, crear la clave en ambos idiomas y confirmar que no haya mezcla de idiomas en la UI.

Notas:
- Documenta cualquier cambio temporal en este bloque para que otros colaboradores sepan que revertir cuando se restablezca Realtime.
- Si introduces nuevas cadenas traducibles, actualiza los archivos de localizacion antes de commitear para evitar strings "huerfanos".
