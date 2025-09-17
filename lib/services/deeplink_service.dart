// lib/services/deeplink_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:app_links/app_links.dart';
import 'package:get/get.dart';
import '../screens/reset_password_screen.dart';

/// Guarda los deep links ya procesados (por secret) para no repetir navegación.
class DeepLinkGuard {
  static final Set<String> _handled = {};

  /// Devuelve true si es nuevo y lo marca como procesado.
  static bool markIfNew(String key) {
    if (_handled.contains(key)) return false;
    _handled.add(key);
    return true;
  }

  /// Borra el historial (opcional; útil al cerrar sesión).
  static void clear() => _handled.clear();
}

class DeeplinkService {
  DeeplinkService._();
  static final DeeplinkService _instance = DeeplinkService._();
  factory DeeplinkService() => _instance;

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  // Evita chequear el initialLink más de una vez por ejecución.
  bool _initialChecked = false;
  bool _initialized = false;

  // Acepta varios esquemas por compatibilidad.
  static const Set<String> _schemes = {'casasegura', 'casa_segura', 'myapp'};
  static const String _host = 'reset';

  /// Inicializa el listener de deep links. Idempotente.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _appLinks = AppLinks();

      // 1) Procesar el initial link SOLO una vez por ejecución.
      if (!_initialChecked) {
        final Uri? initial = await _appLinks.getInitialLink();
        _initialChecked = true;
        if (initial != null) _handle(initial);
      }

      // 2) Escuchar enlaces que llegan mientras la app está abierta.
      _sub = _appLinks.uriLinkStream.listen(
        _handle,
        onError: (e) => debugPrint('AppLinks error: $e'),
      );
    } catch (e) {
      debugPrint('AppLinks init error: $e');
    }
  }

  void _handle(Uri uri) {
    debugPrint('🔗 DeepLink: $uri');

    // Validaciones básicas
    if (!_schemes.contains(uri.scheme) || uri.host != _host) return;

    final userId = uri.queryParameters['userId'];
    final secret = uri.queryParameters['secret'];
    if (userId == null || secret == null) return;

    // Evitar re-procesar el mismo secret
    final key = 'reset:$secret';
    if (!DeepLinkGuard.markIfNew(key)) {
      debugPrint('🔁 DeepLink repetido ignorado ($key)');
      return;
    }

    // Navegar cuando el árbol de navegación esté listo
    Future.microtask(() {
      if (Get.context == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Get.to(() => ResetPasswordScreen(userId: userId, secret: secret));
        });
      } else {
        Get.to(() => ResetPasswordScreen(userId: userId, secret: secret));
      }
    });
  }

  void dispose() => _sub?.cancel();

  /// Útil si quieres permitir un nuevo reset sin reiniciar la app
  /// (por ejemplo, al cerrar sesión).
  void clearHistory() => DeepLinkGuard.clear();
}
