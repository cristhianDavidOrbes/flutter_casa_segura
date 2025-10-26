import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/features/security/domain/security_event.dart';
import 'package:flutter_seguridad_en_casa/features/security/presentation/pages/notifications_page.dart';

enum DetectionSeverity { green, yellow, red }

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty || payload == 'notifications') {
          Get.to(() => const NotificationsPage());
        }
      },
    );

    const securityChannel = AndroidNotificationChannel(
      'security_alerts',
      'Alertas de seguridad',
      description: 'Notificaciones relacionadas a seguridad del hogar',
      importance: Importance.high,
    );

    const stageChannel = AndroidNotificationChannel(
      'security_stage_alerts',
      'Pre-alertas de seguridad',
      description: 'Avisos tempranos ante detecciones persistentes',
      importance: Importance.high,
    );

    const pushChannel = AndroidNotificationChannel(
      'push_alerts',
      'Alertas push',
      description: 'Notificaciones remotas enviadas desde la nube',
      importance: Importance.high,
    );

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(securityChannel);
    await androidImplementation?.createNotificationChannel(stageChannel);
    await androidImplementation?.createNotificationChannel(pushChannel);

    _initialized = true;
  }

  Future<void> showDetectionStage({
    required String deviceName,
    required DetectionSeverity severity,
    required String message,
  }) async {
    if (!_initialized) return;

    const emojiMap = {
      DetectionSeverity.green: '🟢',
      DetectionSeverity.yellow: '🟡',
      DetectionSeverity.red: '🔴',
    };
    const colorMap = {
      DetectionSeverity.green: Colors.green,
      DetectionSeverity.yellow: Colors.amber,
      DetectionSeverity.red: Colors.red,
    };

    final emoji = emojiMap[severity] ?? '🟢';
    final color = colorMap[severity] ?? Colors.green;

    final androidDetails = AndroidNotificationDetails(
      'security_stage_alerts',
      'Pre-alertas de seguridad',
      channelDescription: 'Avisos tempranos ante detecciones persistentes',
      importance: Importance.high,
      priority: Priority.high,
      color: color,
      styleInformation: BigTextStyleInformation(
        message,
        contentTitle: '$emoji $deviceName',
      ),
    );

    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '$emoji $deviceName',
      message,
      details,
      payload: 'notifications',
    );
  }

  Future<void> showSecurityAlert(SecurityEvent event) async {
    if (!_initialized) return;

    final androidDetails = AndroidNotificationDetails(
      'security_alerts',
      'Alertas de seguridad',
      channelDescription:
          'Notificaciones relacionadas a la vigilancia inteligente',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      styleInformation: BigTextStyleInformation(
        event.description,
        contentTitle: event.label,
        summaryText: event.deviceName,
      ),
    );

    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      event.label,
      event.description,
      details,
      payload: 'notifications',
    );
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    if (!_initialized) return;
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      'push_alerts',
      'Alertas push',
      channelDescription: 'Notificaciones remotas enviadas desde la nube',
      importance: Importance.high,
      priority: Priority.high,
    );

    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title ?? 'Casa Segura',
      notification.body ?? '',
      details,
      payload: message.data['route'] ?? 'notifications',
    );
  }
}
