import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_control_service.dart';
import '../services/lan_discovery_service.dart';

class DeviceRecord {
  const DeviceRecord({
    required this.deviceKey,
    required this.name,
    required this.type,
    this.ip,
    required this.addedAt,
    this.lastSeenAt,
  });

  final String deviceKey;
  final String name;
  final String type;
  final String? ip;
  final DateTime addedAt;
  final DateTime? lastSeenAt;

  static DeviceRecord fromMap(Map<String, dynamic> map) {
    return DeviceRecord(
      deviceKey: map['device_key'] as String,
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

  String get _userId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No hay usuario autenticado');
    }
    return userId;
  }

  String normalizeKey(String value) {
    final k = value.toLowerCase().trim();
    return k.endsWith('.local') ? k.substring(0, k.length - 6) : k;
  }

  Future<void> syncDiscovered(List<DiscoveredDevice> devices) async {
    if (devices.isEmpty) return;
    final userId = _userId;
    final now = DateTime.now().toUtc();

    final payload = <Map<String, dynamic>>[];
    for (final device in devices) {
      final key = normalizeKey(
        device.name.isNotEmpty ? device.name : device.id,
      );
      payload.add({
        'user_id': userId,
        'device_key': key,
        'name': device.name.isNotEmpty ? device.name : key,
        'type': device.type,
        'ip': device.ip,
        'added_at': now.toIso8601String(),
        'last_seen_at': now.toIso8601String(),
      });
    }

    await _client
        .from('devices')
        .upsert(payload, onConflict: 'user_id,device_key')
        .select();
  }

  Future<List<DeviceRecord>> listDevices() async {
    final userId = _userId;
    final response = await _client
        .from('devices')
        .select()
        .eq('user_id', userId)
        .order('added_at', ascending: true);

    return (response as List<dynamic>)
        .map((item) => DeviceRecord.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateLastSeen(String deviceKey, {String? ip}) async {
    final userId = _userId;
    final now = DateTime.now().toUtc();
    await _client.from('devices').update({
      'last_seen_at': now.toIso8601String(),
      if (ip != null && ip.isNotEmpty) 'ip': ip,
    }).match({'user_id': userId, 'device_key': deviceKey});
  }

  Future<void> forget(String deviceKey) async {
    final userId = _userId;
    await _client
        .from('devices')
        .delete()
        .match({'user_id': userId, 'device_key': deviceKey});
  }

  Future<void> forgetAndReset({
    required String deviceKey,
    required String? ip,
  }) async {
    try {
      if (ip != null && ip.isNotEmpty) {
        await const DeviceControlService().factoryResetByIp(ip);
      }
    } catch (e) {
      debugPrint('Error enviando factory reset: $e');
    }
    await forget(deviceKey);
  }
}
