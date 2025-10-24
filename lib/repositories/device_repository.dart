import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_control_service.dart';
import '../services/remote_device_service.dart';
import '../data/local/app_db.dart';

enum ForgetOutcome { local, remoteConfirmed, remoteQueued }

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
  final RemoteDeviceService _remoteService = RemoteDeviceService();

  String get _userId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No hay usuario autenticado');
    }
    return userId;
  }

  Future<List<DeviceRecord>> listDevices() async {
    final userId = _userId;
    final response = await _client
        .from('devices')
        .select('id, name, type, ip, added_at, last_seen_at')
        .eq('user_id', userId)
        .order('added_at', ascending: true);

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
    await _client
        .from('devices')
        .update({
          'last_seen_at': now,
          if (ip != null && ip.isNotEmpty) 'ip': ip,
        })
        .match({'user_id': userId, 'id': deviceId});
    final ms = (seenAt ?? DateTime.now()).millisecondsSinceEpoch;
    await AppDb.instance.touchDeviceSeen(deviceId, ip: ip, whenMs: ms);
  }

  Future<void> forget(String deviceId) async {
    final userId = _userId;
    await _client.from('devices').delete().match({
      'user_id': userId,
      'id': deviceId,
    });
    await AppDb.instance.deleteDeviceByDeviceId(deviceId);
  }

  Future<void> updateType(String deviceId, String type) async {
    final userId = _userId;
    final normalized = type.trim().toLowerCase();
    try {
      await _client.from('devices').update({'type': normalized}).match({
        'user_id': userId,
        'id': deviceId,
      });
    } catch (e) {
      debugPrint('Error actualizando tipo de $deviceId: $e');
    }
    await AppDb.instance.touchDeviceSeen(deviceId, type: normalized);
  }

  Future<ForgetOutcome> forgetAndReset({
    required String deviceId,
    required String? ip,
  }) async {
    bool localReset = false;
    try {
      if (ip != null && ip.isNotEmpty) {
        localReset = await const DeviceControlService().factoryResetByIp(ip);
      }
    } catch (e) {
      debugPrint('Error enviando factory reset: $e');
    }

    if (localReset) {
      await forget(deviceId);
      return ForgetOutcome.local;
    }

    await _remoteService.ensureRemoteFlags(deviceId);
    await _remoteService.requestRemoteForget(deviceId);
    return ForgetOutcome.remoteQueued;
  }

  Future<void> finalizeRemoteForget(String deviceId) async {
    await forget(deviceId);
  }
}
