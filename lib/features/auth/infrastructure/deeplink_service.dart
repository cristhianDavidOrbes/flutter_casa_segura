// lib/services/deeplink_service.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:app_links/app_links.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/reset_password_screen.dart';

class DeepLinkGuard {
  static final Set<String> _handled = {};

  static bool markIfNew(String key) {
    if (_handled.contains(key)) return false;
    _handled.add(key);
    return true;
  }

  static void clear() => _handled.clear();
}

class DeeplinkService {
  DeeplinkService._();
  static final DeeplinkService _instance = DeeplinkService._();
  factory DeeplinkService() => _instance;

  late final AppLinks _appLinks;
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<Uri>? _sub;

  bool _initialChecked = false;
  bool _initialized = false;

  static const Set<String> _schemes = {'casasegura', 'casa_segura', 'myapp'};
  static const String _host = 'reset';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _appLinks = AppLinks();

      if (!_initialChecked) {
        final Uri? initial = await _appLinks.getInitialLink();
        _initialChecked = true;
        if (initial != null) _handle(initial);
      }

      _sub = _appLinks.uriLinkStream.listen(
        _handle,
        onError: (e) => debugPrint('AppLinks error: $e'),
      );
    } catch (e) {
      debugPrint('AppLinks init error: $e');
    }
  }

  void _handle(Uri uri) {
    debugPrint('~- DeepLink: $uri');

    if (!_schemes.contains(uri.scheme) || uri.host != _host) return;

    final params = _paramsFromUri(uri);
    final type = (params['type'] ?? '').toLowerCase();
    if (type != 'recovery') {
      debugPrint('~~ DeepLink ignorado, type=$type');
      return;
    }

    final refreshToken = params['refresh_token'] ?? '';
    final accessToken = params['access_token'] ?? params['token'];
    final guardKey = refreshToken.isNotEmpty
        ? 'reset:$refreshToken'
        : accessToken != null
            ? 'reset:$accessToken'
            : 'reset:${uri.toString()}';

    if (!DeepLinkGuard.markIfNew(guardKey)) {
      debugPrint('~~ DeepLink repetido ignorado ($guardKey)');
      return;
    }

    Future.microtask(() async {
      try {
        await _supabase.auth.getSessionFromUrl(uri);
      } catch (e) {
        debugPrint('~~ Error procesando deep link Supabase: ${e.toString()}');
        return;
      }

      void openReset() {
        Get.to(() => const ResetPasswordScreen());
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => openReset());
    });
  }

  Map<String, String> _paramsFromUri(Uri uri) {
    final params = <String, String>{};
    params.addAll(uri.queryParameters);
    if (uri.fragment.isNotEmpty) {
      for (final part in uri.fragment.split('&')) {
        if (part.isEmpty) continue;
        final pieces = part.split('=');
        if (pieces.length == 2) {
          params[Uri.decodeComponent(pieces[0])] =
              Uri.decodeComponent(pieces[1]);
        }
      }
    }
    return params;
  }

  void dispose() => _sub?.cancel();

  void clearHistory() => DeepLinkGuard.clear();
}
