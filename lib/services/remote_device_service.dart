import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/device_remote_flags.dart';

class RemoteLiveSignal {
  const RemoteLiveSignal({
    required this.id,
    required this.name,
    required this.kind,
    required this.updatedAt,
    this.valueNumeric,
    this.valueText,
    this.extra = const {},
  });

  final String id;
  final String name;
  final String kind;
  final DateTime updatedAt;
  final double? valueNumeric;
  final String? valueText;
  final Map<String, dynamic> extra;

  String? get snapshotPath {
    final raw = extra['snapshot'];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  factory RemoteLiveSignal.fromMap(Map<String, dynamic> map) {
    final extraMap = map['extra'];
    return RemoteLiveSignal(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      kind: map['kind'] as String? ?? 'other',
      updatedAt: DateTime.parse(map['updated_at'] as String),
      valueNumeric: map['value_numeric'] != null
          ? (map['value_numeric'] as num).toDouble()
          : null,
      valueText: map['value_text'] as String?,
      extra: extraMap is Map<String, dynamic>
          ? extraMap
          : extraMap is Map
          ? extraMap.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{},
    );
  }
}

class RemoteActuator {
  const RemoteActuator({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.kind,
    this.meta = const {},
  });

  final String id;
  final String deviceId;
  final String name;
  final String kind;
  final Map<String, dynamic> meta;

  factory RemoteActuator.fromMap(Map<String, dynamic> map) {
    final metaRaw = map['meta'];
    return RemoteActuator(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      name: map['name'] as String? ?? '',
      kind: map['kind'] as String? ?? 'other',
      meta: metaRaw is Map<String, dynamic>
          ? metaRaw
          : metaRaw is Map
          ? metaRaw.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{},
    );
  }

  bool matchesKind(String maybeKind) =>
      kind.toLowerCase() == maybeKind.toLowerCase();
}

class RemoteDevicePresence {
  const RemoteDevicePresence({
    required this.id,
    required this.name,
    required this.type,
    this.ip,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final String type;
  final String? ip;
  final DateTime? lastSeenAt;

  factory RemoteDevicePresence.fromMap(Map<String, dynamic> map) {
    return RemoteDevicePresence(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      type: map['type'] as String? ?? 'unknown',
      ip: map['ip'] as String?,
      lastSeenAt: map['last_seen_at'] != null
          ? DateTime.tryParse(map['last_seen_at'] as String)
          : null,
    );
  }
}

class RemoteCommandHandle {
  const RemoteCommandHandle({required this.id, required this.actuatorId});

  final int id;
  final String actuatorId;
}

class RemoteDeviceService {
  RemoteDeviceService() : _client = Supabase.instance.client;

  final SupabaseClient _client;

  Stream<List<RemoteLiveSignal>> watchLiveSignals(String deviceId) {
    return _retryingStream<List<RemoteLiveSignal>>(
      () => _client
          .from('live_signals')
          .stream(primaryKey: ['id'])
          .eq('device_id', deviceId)
          .map(
            (rows) => rows.map((row) => RemoteLiveSignal.fromMap(row)).toList(),
          ),
    );
  }

  Stream<List<RemoteActuator>> watchActuators(String deviceId) {
    return _retryingStream<List<RemoteActuator>>(
      () => _client
          .from('actuators')
          .stream(primaryKey: ['id'])
          .eq('device_id', deviceId)
          .map(
            (rows) => rows.map((row) => RemoteActuator.fromMap(row)).toList(),
          ),
    );
  }

  Future<List<RemoteActuator>> fetchActuators(String deviceId) async {
    final response = await _client
        .from('actuators')
        .select()
        .eq('device_id', deviceId);
    return (response as List<dynamic>)
        .map((row) => RemoteActuator.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<RemoteLiveSignal>> fetchLiveSignals(String deviceId) async {
    final response = await _client
        .from('live_signals')
        .select()
        .eq('device_id', deviceId);
    return (response as List<dynamic>)
        .map((row) => RemoteLiveSignal.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<RemoteCommandHandle> enqueueCommand({
    required String actuatorId,
    required Map<String, dynamic> command,
  }) async {
    final response = await _client
        .from('actuator_commands')
        .insert({'actuator_id': actuatorId, 'command': command})
        .select('id, actuator_id')
        .limit(1);

    final rows = response as List<dynamic>;
    if (rows.isEmpty) {
      throw StateError('No se pudo registrar el comando remoto');
    }
    final raw = rows.first as Map<String, dynamic>;

    final idValue = raw['id'];
    if (idValue is! num) {
      throw StateError('Comando remoto sin identificador valido');
    }

    return RemoteCommandHandle(
      id: idValue.toInt(),
      actuatorId: raw['actuator_id'] as String,
    );
  }

  Future<RemoteCommandHandle> enqueueFactoryReset(String deviceId) async {
    var actuators = await fetchActuators(deviceId);
    RemoteActuator? target = _pickSystemActuator(actuators);
    if (target == null) {
      await _ensureSystemActuator(deviceId);
      actuators = await fetchActuators(deviceId);
      target = _pickSystemActuator(actuators);
    }
    target ??= actuators.isNotEmpty ? actuators.first : null;
    if (target == null) {
      throw StateError(
        'No se encontraron actuadores para el dispositivo $deviceId',
      );
    }

    return enqueueCommand(
      actuatorId: target.id,
      command: {
        'action': 'factory_reset',
        'payload': const {},
        'origin': 'app_forget',
        'issued_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> fetchCurrentState(String deviceId) async {
    final response = await _client.rpc(
      'device_current_state',
      params: {'_device_id': deviceId},
    );

    if (response == null) return const {};

    if (response is Map<String, dynamic>) {
      return response;
    }

    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }

    if (response is String && response.isNotEmpty) {
      final decoded = jsonDecode(response);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }

    throw StateError(
      'Respuesta inesperada al obtener el estado remoto del dispositivo',
    );
  }

  Stream<DeviceRemoteFlags?> watchRemoteFlags(String deviceId) {
    return _retryingStream<DeviceRemoteFlags?>(
      () => _client
          .from('device_remote_flags')
          .stream(primaryKey: ['device_id'])
          .eq('device_id', deviceId)
          .map((rows) {
            if (rows.isEmpty) return null;
            final row = rows.first;
            final map = _normalizeMap(row);
            return DeviceRemoteFlags.fromMap(map);
          }),
    );
  }

  Future<DeviceRemoteFlags?> fetchRemoteFlags(String deviceId) async {
    final response = await _client
        .from('device_remote_flags')
        .select()
        .eq('device_id', deviceId)
        .maybeSingle();
    if (response == null) return null;
    return DeviceRemoteFlags.fromMap(_normalizeMap(response));
  }

  Future<void> ensureRemoteFlags(String deviceId) async {
    await _client
        .from('device_remote_flags')
        .upsert({'device_id': deviceId}, onConflict: 'device_id')
        .select('device_id');
  }

  Future<void> requestRemotePing(String deviceId) async {
    await ensureRemoteFlags(deviceId);
    final now = _utcNowIso();
    await _client
        .from('device_remote_flags')
        .upsert({
          'device_id': deviceId,
          'ping_requested': true,
          'ping_requested_at': now,
          'ping_status': 'pending',
        }, onConflict: 'device_id')
        .select('device_id');
  }

  Future<void> requestRemoteForget(String deviceId) async {
    await ensureRemoteFlags(deviceId);
    final now = _utcNowIso();
    await _client
        .from('device_remote_flags')
        .upsert({
          'device_id': deviceId,
          'forget_requested': true,
          'forget_requested_at': now,
          'forget_status': 'pending',
        }, onConflict: 'device_id')
        .select('device_id');
  }

  RemoteActuator? _pickSystemActuator(List<RemoteActuator> actuators) {
    for (final actuator in actuators) {
      final kindLower = actuator.kind.toLowerCase();
      if (kindLower == 'system') return actuator;
      final meta = actuator.meta;
      final metaKind = meta['kind']?.toString().toLowerCase();
      if (metaKind == 'system') return actuator;
      final role = meta['role']?.toString().toLowerCase();
      if (role == 'factory-reset') return actuator;
    }
    return null;
  }

  Future<void> _ensureSystemActuator(String deviceId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _client.from('actuators').upsert({
        'device_id': deviceId,
        'name': 'system',
        'kind': 'system',
        'meta': {'role': 'factory-reset', 'ensured_at': now},
      }, onConflict: 'device_id,name');
    } catch (_) {
      // Es posible que ya exista; ignoramos el error.
    }
  }

  Future<String?> fetchCommandStatus(int commandId) async {
    final response = await _client
        .from('actuator_commands')
        .select('status')
        .eq('id', commandId)
        .maybeSingle();

    if (response == null) return null;
    final status = response['status'];
    return status is String ? status : status?.toString();
  }

  Future<bool> waitForCommandAcknowledgement(
    int commandId, {
    Duration timeout = const Duration(seconds: 12),
    Duration pollInterval = const Duration(milliseconds: 400),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final status = await fetchCommandStatus(commandId);
      if (status == null) {
        return true;
      }
      final normalized = status.toLowerCase();
      if (normalized == 'pending') {
        await Future.delayed(pollInterval);
        continue;
      }
      if (normalized == 'taken' || normalized == 'done') {
        return true;
      }
      if (normalized == 'error') {
        return false;
      }
      return true;
    }

    return false;
  }

  Stream<RemoteDevicePresence?> watchDevicePresence(String deviceId) {
    return _retryingStream<RemoteDevicePresence?>(
      () => _client
          .from('devices')
          .stream(primaryKey: ['id'])
          .eq('id', deviceId)
          .map((rows) {
            if (rows.isEmpty) return null;
            final dynamic row = rows.first;
            final Map<String, dynamic> map = row is Map<String, dynamic>
                ? row
                : Map<String, dynamic>.from(row as Map);
            return RemoteDevicePresence.fromMap(map);
          }),
    );
  }

  Map<String, dynamic> _normalizeMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return Map<String, dynamic>.from(value as Map);
  }

  String _utcNowIso() => DateTime.now().toUtc().toIso8601String();

  Stream<T> _retryingStream<T>(
    Stream<T> Function() sourceBuilder, {
    Duration retryDelay = const Duration(seconds: 5),
  }) {
    StreamSubscription<T>? subscription;
    bool disposed = false;

    late StreamController<T> controller;

    late void Function() start;

    void scheduleRestart() {
      if (disposed) return;
      Future.delayed(retryDelay, () {
        if (!disposed) start();
      });
    }

    start = () {
      if (disposed) return;
      try {
        subscription = sourceBuilder().listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) async {
            debugPrint(
              'Stream Supabase con error, reintentando en ${retryDelay.inSeconds}s: $error',
            );
            await subscription?.cancel();
            subscription = null;
            scheduleRestart();
          },
          onDone: () {
            debugPrint(
              'Stream Supabase finalizado, reintentando en ${retryDelay.inSeconds}s.',
            );
            subscription = null;
            scheduleRestart();
          },
          cancelOnError: false,
        );
      } catch (error) {
        debugPrint(
          'Fallo al iniciar stream de Supabase, reintentando en ${retryDelay.inSeconds}s: $error',
        );
        subscription = null;
        scheduleRestart();
      }
    };

    controller = StreamController<T>(
      onListen: start,
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        disposed = true;
        final sub = subscription;
        subscription = null;
        await sub?.cancel();
      },
    );

    return controller.stream;
  }
}
