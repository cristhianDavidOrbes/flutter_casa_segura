import 'package:flutter/foundation.dart';
import '../data/local/app_db.dart';

import '../services/lan_discovery_service.dart';
import '../services/device_control_service.dart';

class DeviceRepository {
  DeviceRepository._();
  static final DeviceRepository instance = DeviceRepository._();

  final _db = AppDb.instance;

  String _normKey(String? deviceId, String? host, String ip) {
    final k = (deviceId ?? host ?? ip).trim();
    return k.toLowerCase();
  }

  Future<void> forgetAndReset({
    required String deviceId,
    required String ip,
  }) async {
    final ok = await const DeviceControlService().factoryResetByIp(ip);
    // pase o falle la llamada, lo quitamos de la DB local para no duplicar
    await _db.deleteDeviceByDeviceId(deviceId);
    // (Opcional) feedback al usuario si ok == false
  }

  Future<void> touchFromDiscovered(DiscoveredDevice d) async {
    final key = _normKey(d.deviceId, d.host, d.ip);
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.upsertDeviceByDeviceId(
      deviceId: key,
      name: (d.name.isNotEmpty ? d.name : key),
      type: d.type,
      ip: d.ip,
      addedAt: now,
      lastSeenAt: now,
    );

    await _db.touchDeviceSeen(
      key,
      ip: d.ip,
      name: d.name.isNotEmpty ? d.name : null,
      type: d.type,
      whenMs: now,
    );
  }

  Future<List<Device>> listDevices() => _db.fetchAllDevices();

  Future<void> markSeen({
    required String deviceId,
    String? ip,
    String? name,
    String? type,
  }) {
    return _db.touchDeviceSeen(deviceId, ip: ip, name: name, type: type);
  }

  Future<void> forget(String deviceId) => _db.deleteDeviceByDeviceId(deviceId);
}
