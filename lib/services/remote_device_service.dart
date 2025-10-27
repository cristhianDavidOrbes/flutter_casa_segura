import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
    return _pollingStream<List<RemoteLiveSignal>>(
      () async =>
          List<RemoteLiveSignal>.unmodifiable(await fetchLiveSignals(deviceId)),
      interval: const Duration(seconds: 8),
      maxInterval: const Duration(seconds: 60),
      fallback: const <RemoteLiveSignal>[],
      label: 'live_signals/$deviceId',
    );
  }

  Stream<List<RemoteActuator>> watchActuators(String deviceId) {
    return _pollingStream<List<RemoteActuator>>(
      () async =>
          List<RemoteActuator>.unmodifiable(await fetchActuators(deviceId)),
      interval: const Duration(seconds: 12),
      maxInterval: const Duration(seconds: 60),
      fallback: const <RemoteActuator>[],
      label: 'actuators/$deviceId',
    );
  }

  Future<List<RemoteActuator>> fetchActuators(String deviceId) async {
    final response = await _safeRequest(
      () => _client.from('actuators').select().eq('device_id', deviceId),
      debugLabel: 'actuators/$deviceId',
    );
    return (response as List<dynamic>)
        .map((row) => RemoteActuator.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<RemoteLiveSignal>> fetchLiveSignals(String deviceId) async {
    final response = await _safeRequest(
      () => _client.from('live_signals').select().eq('device_id', deviceId),
      debugLabel: 'live_signals/$deviceId',
    );
    return (response as List<dynamic>)
        .map((row) => RemoteLiveSignal.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<RemoteCommandHandle> enqueueCommand({
    required String actuatorId,
    required Map<String, dynamic> command,
  }) async {
    final response = await _safeRequest(
      () => _client
          .from('actuator_commands')
          .insert({'actuator_id': actuatorId, 'command': command})
          .select('id, actuator_id')
          .limit(1),
      debugLabel: 'enqueue_command/$actuatorId',
    );

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
    throw StateError(
      'El restablecimiento remoto esta deshabilitado temporalmente. '
      'Usa la opcion de olvido local desde la misma red del dispositivo.',
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
    return _pollingStream<DeviceRemoteFlags?>(
      () => fetchRemoteFlags(deviceId),
      interval: const Duration(seconds: 12),
      maxInterval: const Duration(seconds: 90),
      label: 'remote_flags/$deviceId',
    );
  }

  Future<DeviceRemoteFlags?> fetchRemoteFlags(String deviceId) async {
    final response = await _safeRequest(
      () => _client
          .from('device_remote_flags')
          .select()
          .eq('device_id', deviceId)
          .maybeSingle(),
      debugLabel: 'remote_flags/$deviceId',
    );
    if (response == null) return null;
    return DeviceRemoteFlags.fromMap(_normalizeMap(response));
  }

  Future<RemoteDevicePresence?> fetchDevicePresence(String deviceId) async {
    final response = await _safeRequest(
      () => _client
          .from('devices')
          .select('id, name, type, ip, last_seen_at')
          .eq('id', deviceId)
          .maybeSingle(),
      debugLabel: 'devices/$deviceId',
    );
    if (response == null) return null;
    return RemoteDevicePresence.fromMap(_normalizeMap(response));
  }

  Future<void> ensureRemoteFlags(String deviceId) async {
    await _safeRequest(
      () => _client
          .from('device_remote_flags')
          .upsert({'device_id': deviceId}, onConflict: 'device_id')
          .select('device_id'),
      debugLabel: 'remote_flags/upsert_$deviceId',
    );
  }

  Future<void> requestRemotePing(String deviceId) async {
    await ensureRemoteFlags(deviceId);
    final now = _utcNowIso();
    await _safeRequest(
      () => _client
          .from('device_remote_flags')
          .upsert({
            'device_id': deviceId,
            'ping_requested': true,
            'ping_requested_at': now,
            'ping_status': 'pending',
          }, onConflict: 'device_id')
          .select('device_id'),
      debugLabel: 'remote_flags/ping_$deviceId',
    );
  }

  Future<void> requestRemoteForget(String deviceId) async {
    debugPrint(
      'requestRemoteForget($deviceId) ignorado: la operacion remota esta deshabilitada.',
    );
    throw StateError(
      'El olvido remoto esta deshabilitado temporalmente. '
      'Conectate a la red local del dispositivo y usa la opcion de olvido local.',
    );
  }

  Future<String?> fetchCommandStatus(int commandId) async {
    final response = await _safeRequest(
      () => _client
          .from('actuator_commands')
          .select('status')
          .eq('id', commandId)
          .maybeSingle(),
      debugLabel: 'actuator_commands/$commandId',
    );

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
    return _pollingStream<RemoteDevicePresence?>(
      () => fetchDevicePresence(deviceId),
      interval: const Duration(seconds: 15),
      maxInterval: const Duration(seconds: 120),
      label: 'device_presence/$deviceId',
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

  Stream<T> _pollingStream<T>(
    Future<T> Function() fetch, {
    required Duration interval,
    Duration? maxInterval,
    Duration initialDelay = Duration.zero,
    T? fallback,
    String? label,
  }) {
    Timer? timer;
    bool disposed = false;
    bool fetching = false;
    int consecutiveErrors = 0;
    Duration currentInterval = interval;
    final Duration upperInterval = maxInterval != null && maxInterval > interval
        ? maxInterval
        : interval;

    late StreamController<T> controller;
    late void Function(Duration delay) scheduleNext;

    Future<void> emitValue() async {
      if (disposed || fetching) return;
      fetching = true;
      try {
        final value = await fetch();
        consecutiveErrors = 0;
        currentInterval = interval;
        if (!disposed) {
          controller.add(value);
        }
      } catch (error, stackTrace) {
        consecutiveErrors += 1;
        final bool transient = _isTransientSupabaseError(error);
        if (transient) {
          currentInterval = _computeBackoffInterval(
            base: interval,
            maxInterval: upperInterval,
            attempt: consecutiveErrors,
          );
          final tag = label != null ? ' [$label]' : '';
          debugPrint(
            'Supabase polling$tag error '
            '(reintentando en ${currentInterval.inSeconds}s): $error',
          );
          if (fallback != null && !disposed) {
            controller.add(fallback);
          }
        } else {
          final tag = label != null ? ' [$label]' : '';
          debugPrint(
            'Supabase polling$tag error sin reintento automatico: $error',
          );
          debugPrint('$stackTrace');
          currentInterval = upperInterval;
          consecutiveErrors = 0;
          if (fallback != null && !disposed) {
            controller.add(fallback);
          } else if (!disposed) {
            controller.addError(error, stackTrace);
          }
        }
      } finally {
        fetching = false;
        if (!disposed) {
          scheduleNext(currentInterval);
        }
      }
    }

    scheduleNext = (Duration delay) {
      timer?.cancel();
      if (disposed) return;
      timer = Timer(delay, () async {
        await emitValue();
      });
    };

    controller = StreamController<T>(
      onListen: () {
        Future<void>(() async {
          if (initialDelay == Duration.zero) {
            await emitValue();
          } else {
            scheduleNext(initialDelay);
          }
        });
      },
      onCancel: () {
        disposed = true;
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }

  Duration _computeBackoffInterval({
    required Duration base,
    required Duration maxInterval,
    required int attempt,
  }) {
    final int factor = math.pow(2, attempt - 1).toInt();
    final Duration candidate = Duration(seconds: base.inSeconds * factor);
    if (candidate > maxInterval) return maxInterval;
    if (candidate < base) return base;
    return candidate;
  }

  static const Duration _baseRetryDelay = Duration(milliseconds: 250);
  static const Duration _maxRetryDelay = Duration(seconds: 3);

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
