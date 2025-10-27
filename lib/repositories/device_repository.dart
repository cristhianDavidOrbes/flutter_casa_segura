import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_control_service.dart';
import '../data/local/app_db.dart';

class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.name,
    required this.type,
    this.ip,
    required this.addedAt,
    this.lastSeenAt,
  });

  final String id; // UUID generado en Supabase
  final String name;
  final String type;
  final String? ip;
  final DateTime addedAt;
  final DateTime? lastSeenAt;

  bool get isOnline {
    if (lastSeenAt == null) return false;
    final diff = DateTime.now().difference(lastSeenAt!);
    return diff <= const Duration(minutes: 2);
  }

  static DeviceRecord fromMap(Map<String, dynamic> map) {
    return DeviceRecord(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      type: map['type'] as String? ?? 'unknown',
      ip: map['ip'] as String?,
      addedAt: DateTime.parse(map['added_at'] as String),
      lastSeenAt: map['last_seen_at'] != null
          ? DateTime.parse(map['last_seen_at'] as String)
          : null,
    );
  }
}

class DeviceRepository {
  DeviceRepository._();
  static final DeviceRepository instance = DeviceRepository._();

  final SupabaseClient _client = Supabase.instance.client;
  static const Duration _baseRetryDelay = Duration(milliseconds: 250);
  static const Duration _maxRetryDelay = Duration(seconds: 3);

  String get _userId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No hay usuario autenticado');
    }
    return userId;
  }

  Future<List<DeviceRecord>> listDevices() async {
    final userId = _userId;
    final response = await _safeRequest(
      () => _client
          .from('devices')
          .select('id, name, type, ip, added_at, last_seen_at')
          .eq('user_id', userId)
          .order('added_at', ascending: true),
      debugLabel: 'devices/list',
    );

    return (response as List<dynamic>)
        .map((item) => DeviceRecord.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> updatePresence(
    String deviceId, {
    String? ip,
    DateTime? seenAt,
  }) async {
    final userId = _userId;
    final now = (seenAt ?? DateTime.now()).toUtc().toIso8601String();
    await _safeRequest(
      () => _client
          .from('devices')
          .update({
            'last_seen_at': now,
            if (ip != null && ip.isNotEmpty) 'ip': ip,
          })
          .match({'user_id': userId, 'id': deviceId}),
      debugLabel: 'devices/update_presence/$deviceId',
    );
    final ms = (seenAt ?? DateTime.now()).millisecondsSinceEpoch;
    await AppDb.instance.touchDeviceSeen(deviceId, ip: ip, whenMs: ms);
  }

  Future<void> forget(String deviceId) async {
    final userId = _userId;
    await _safeRequest(
      () => _client.from('devices').delete().match({
        'user_id': userId,
        'id': deviceId,
      }),
      debugLabel: 'devices/forget/$deviceId',
    );
    await AppDb.instance.deleteDeviceByDeviceId(deviceId);
  }

  Future<void> updateType(String deviceId, String type) async {
    final userId = _userId;
    final normalized = type.trim().toLowerCase();
    try {
      await _safeRequest(
        () => _client.from('devices').update({'type': normalized}).match({
          'user_id': userId,
          'id': deviceId,
        }),
        debugLabel: 'devices/update_type/$deviceId',
      );
    } catch (e) {
      debugPrint('Error actualizando tipo de $deviceId: $e');
    }
    await AppDb.instance.touchDeviceSeen(deviceId, type: normalized);
  }

  Future<void> forgetAndReset({
    required String deviceId,
    required String? ip,
  }) async {
    final localIp = ip?.trim();
    if (localIp == null || localIp.isEmpty) {
      throw StateError(
        'Necesitas estar en la misma red local del dispositivo para olvidarlo.',
      );
    }

    bool localReset = false;
    try {
      localReset = await const DeviceControlService().factoryResetByIp(localIp);
    } catch (e) {
      debugPrint('Error enviando factory reset: $e');
    }

    if (!localReset) {
      throw StateError(
        'No se pudo contactar al dispositivo en la red local. Verifica la conexion e intentalo de nuevo.',
      );
    }

    await forget(deviceId);
  }

  Duration _computeRetryDelay(int attempt) {
    final int raw =
        _baseRetryDelay.inMilliseconds * math.pow(2, attempt - 1).toInt();
    final int millis = raw
        .clamp(_baseRetryDelay.inMilliseconds, _maxRetryDelay.inMilliseconds)
        .toInt();
    return Duration(milliseconds: millis);
  }

  Future<T> _safeRequest<T>(
    Future<T> Function() action, {
    String? debugLabel,
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        final bool transient = _isTransientSupabaseError(error);
        if (!transient || attempt == maxAttempts) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        final delay = _computeRetryDelay(attempt);
        final tag = debugLabel != null ? ' [$debugLabel]' : '';
        debugPrint(
          'Supabase request$tag fallo (intento $attempt/$maxAttempts): $error. '
          'Reintentando en ${delay.inMilliseconds}ms.',
        );
        await Future.delayed(delay);
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('Supabase request failed'),
      lastStack ?? StackTrace.current,
    );
  }

  bool _isTransientSupabaseError(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is HandshakeException) return true;
    if (error is http.ClientException) return true;
    if (error is PostgrestException) return true;

    final message = error.toString().toLowerCase();
    if (message.contains('broken pipe')) return true;
    if (message.contains('connection reset')) return true;
    if (message.contains('connection terminated during handshake')) return true;
    if (message.contains('connection closed')) return true;
    return false;
  }
}
