import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:app_links/app_links.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_seguridad_en_casa/core/state/circle_state.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/login_screen.dart';
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

  static const Set<String> _customSchemes = {
    'casasegura',
    'casa_segura',
    'myapp',
  };
  static const String _customHost = 'reset';
  static const String _httpsHost = 'redirrecion-home.vercel.app';
  static const String _httpsPathPrefix = '/reset';
  static const Set<String> _supportedTypes = {'recovery', 'signup'};

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

    final bool isCustomScheme =
        _customSchemes.contains(uri.scheme) && uri.host == _customHost;
    final bool isHttpsLink =
        uri.scheme == 'https' &&
        uri.host == _httpsHost &&
        (uri.path == _httpsPathPrefix ||
            uri.path.startsWith('$_httpsPathPrefix/'));

    if (!isCustomScheme && !isHttpsLink) {
      debugPrint('~~ DeepLink ignorado: $uri');
      return;
    }

    final params = _paramsFromUri(uri);
    final inferredType = _inferType(uri, params);

    if (inferredType == null) {
      final originalType = (params['type'] ?? '').toLowerCase();
      debugPrint('~~ DeepLink ignorado, type=$originalType');
      return;
    }

    final guardKey = _buildGuardKey(inferredType, params, uri);
    if (!DeepLinkGuard.markIfNew(guardKey)) {
      debugPrint('~~ DeepLink repetido ignorado ($guardKey)');
      return;
    }

    Future.microtask(() => _process(inferredType, uri));
  }

  String _buildGuardKey(String type, Map<String, String> params, Uri uri) {
    final refreshToken = params['refresh_token'] ?? '';
    if (refreshToken.isNotEmpty) return '$type:$refreshToken';

    final String? accessToken = params['access_token'] ?? params['token'];
    if (accessToken != null && accessToken.isNotEmpty) {
      return '$type:$accessToken';
    }

    return '$type:${uri.toString()}';
  }

  String? _inferType(Uri uri, Map<String, String> params) {
    final rawType = (params['type'] ?? '').toLowerCase();
    if (_supportedTypes.contains(rawType)) return rawType;

    final bool hasRecoveryTokens =
        params.containsKey('code') ||
        params.containsKey('access_token') ||
        params.containsKey('refresh_token') ||
        params.containsKey('token');

    final bool looksLikeResetTarget =
        (uri.scheme == 'https' &&
            uri.host == _httpsHost &&
            uri.path.toLowerCase().contains('reset')) ||
        (_customSchemes.contains(uri.scheme) && uri.host == _customHost);

    if (rawType.isEmpty && hasRecoveryTokens && looksLikeResetTarget) {
      return 'recovery';
    }

    return null;
  }

  Future<void> _process(String type, Uri uri) async {
    try {
      await _supabase.auth.getSessionFromUrl(uri);
    } catch (e) {
      debugPrint('~~ Error procesando deep link Supabase: ${e.toString()}');
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (type) {
        case 'recovery':
          _openResetPassword();
          break;
        case 'signup':
          _handleSignupCompletion();
          break;
      }
    });
  }

  void _openResetPassword() {
    Get.to(() => const ResetPasswordScreen());
  }

  void _handleSignupCompletion() {
    if (Get.isRegistered<AuthController>()) {
      Get.find<AuthController>().refreshCurrentUser();
    }

    final CircleStateNotifier circle = Get.isRegistered<CircleStateNotifier>()
        ? Get.find<CircleStateNotifier>()
        : Get.put<CircleStateNotifier>(CircleStateNotifier(), permanent: true);
    circle.moveToBottom();

    Get.offAll(() => LoginScreen(circleNotifier: circle));

    Future.delayed(const Duration(milliseconds: 350), () {
      if (!Get.isSnackbarOpen) {
        Get.snackbar(
          'Cuenta verificada',
          'Inicia sesion con tus credenciales.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      }
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
          params[Uri.decodeComponent(pieces[0])] = Uri.decodeComponent(
            pieces[1],
          );
        }
      }
    }
    return params;
  }

  void dispose() => _sub?.cancel();

  void clearHistory() => DeepLinkGuard.clear();
}
