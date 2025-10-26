import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_seguridad_en_casa/features/security/application/notification_service.dart';
import 'package:flutter_seguridad_en_casa/features/security/presentation/pages/notifications_page.dart';
import 'package:flutter_seguridad_en_casa/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase background init error: $e');
  }
}

class PushNotificationService {
  PushNotificationService();

  static PushNotificationService get to => Get.find<PushNotificationService>();

  bool _initialized = false;
  String? _cachedToken;
  FirebaseMessaging? _messaging;

  Future<void> init() async {
    if (_initialized) return;

    await _ensureFirebaseInitialized();
    debugPrint(
      'PushNotificationService: Firebase apps available -> ${Firebase.apps.map((app) => app.name).toList()}',
    );
    final messaging = _ensureMessaging();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _requestPermissions(messaging);

    final token = await messaging.getToken();
    if (token != null) {
      await _registerToken(token);
    }

    messaging.onTokenRefresh.listen(_registerToken);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    _initialized = true;
  }

  Future<void> syncTokenWithUser() async {
    if (!_initialized) {
      try {
        await init();
      } catch (e, st) {
        debugPrint(
          'PushNotificationService sync retry failed: $e\n$st',
        );
        return;
      }
    }
    if (!_initialized) return;
    final messaging = _ensureMessaging();
    final token = await messaging.getToken();
    if (token != null) {
      await _registerToken(token, force: true);
    }
  }

  Future<void> removeToken() async {
    if (!_initialized) return;
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final messaging = _ensureMessaging();
      final token = await messaging.getToken();
      if (token == null) return;

      await client.from('user_push_tokens').delete().match({
        'user_id': userId,
        'token': token,
      });
      _cachedToken = null;
    } catch (e) {
      debugPrint('Push token delete error: $e');
    }
  }

  Future<void> _ensureFirebaseInitialized() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('PushNotificationService: Firebase.initializeApp executed');
      } else {
        debugPrint(
          'PushNotificationService: Firebase already initialized as ${Firebase.apps.map((app) => app.name).join(', ')}',
        );
      }
    } catch (e, st) {
      debugPrint('Firebase init error: $e\n$st');
    }
  }

  Future<void> _requestPermissions(FirebaseMessaging messaging) async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          announcement: true,
          provisional: false,
        );
      } else {
        await messaging.requestPermission();
      }
    } catch (e) {
      debugPrint('Push permission error: $e');
    }
  }

  Future<void> _registerToken(String token, {bool force = false}) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      if (!force && _cachedToken == token) return;

      await client.from('user_push_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toIso8601String(),
      });
      _cachedToken = token;
    } catch (e) {
      debugPrint('Push token sync error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (message.notification != null) {
      NotificationService.instance.showRemoteMessage(message);
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final route = message.data['route'];
    if (route == 'notifications') {
      Get.to(() => const NotificationsPage());
    } else {
      Get.to(() => const NotificationsPage());
    }
  }

  FirebaseMessaging _ensureMessaging() {
    _messaging ??= FirebaseMessaging.instance;
    return _messaging!;
  }
}
