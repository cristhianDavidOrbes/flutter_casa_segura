// lib/features/home/presentation/pages/home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/device_card.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/core/state/circle_state.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/login_screen.dart';

import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/screens/devices_page.dart';
import 'package:flutter_seguridad_en_casa/screens/provisioning_screen.dart';
import 'package:flutter_seguridad_en_casa/screens/device_detail_page.dart';
import 'package:flutter_seguridad_en_casa/services/lan_discovery_service.dart';
import 'package:flutter_seguridad_en_casa/repositories/device_repository.dart';
import 'package:flutter_seguridad_en_casa/services/remote_device_service.dart';

class _ServoSnapshot {
  const _ServoSnapshot({this.on, this.pos});

  final bool? on;
  final int? pos;
}

enum _DeviceKind { servo, camera, detector }

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.circleNotifier});
  final CircleStateNotifier circleNotifier;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthController _auth = Get.find<AuthController>();
  final RemoteDeviceService _remoteService = RemoteDeviceService();

  static const Duration _presenceWindow = Duration(minutes: 2);

  // ---- Estado / datos locales ----
  List<FamilyMember> _family = const [];
  List<Device> _devices = const [];
  List<Device> _activeDevices = const [];
  bool _loading = true;

  /// IDs que están “online” según mDNS (refrescado periódico).
  /// Se intentará mapear por `device_id`, luego por `host`, y por IP.
  final Set<String> _onlineKeys = <String>{};
  Timer? _lanTimer;

  final Map<String, StreamSubscription<List<RemoteLiveSignal>>>
  _servoSignalSubs = {};
  final Map<String, StreamSubscription<List<RemoteActuator>>>
  _servoActuatorSubs = {};
  final Map<String, _ServoSnapshot> _servoSnapshots = {};
  final Map<String, RemoteActuator> _servoActuators = {};
  final Set<String> _servoBusy = <String>{};
  final Map<String, StreamSubscription<List<RemoteLiveSignal>>>
  _detectorSignalSubs = {};
  final Map<String, Map<String, dynamic>> _detectorLiveData = {};
  final Map<String, Timer> _detectorPollTimers = {};

  final _pageCtrl = PageController(viewportFraction: 0.55);
  double _page = 0;

  Device? _deviceById(String deviceId) {
    final lower = deviceId.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (final device in _devices) {
      if (device.deviceId.trim().toLowerCase() == lower) {
        return device;
      }
    }
    return null;
  }

  String? _deviceIp(String deviceId) => _deviceById(deviceId)?.ip?.trim();

  Set<String> _hostKeysFor(String deviceId, {String? host}) {
    final keys = <String>{};
    final base = deviceId.trim().toLowerCase();
    if (base.isNotEmpty) {
      keys.add('host:$base');
      keys.add('host:${base}.local');
    }
    final extra = host?.trim().toLowerCase();
    if (extra != null && extra.isNotEmpty) {
      keys.add('host:$extra');
    }
    return keys;
  }

  bool _markDeviceOnline(
    String deviceId, {
    String? host,
    String? ip,
    DateTime? when,
  }) {
    final lowerId = deviceId.trim().toLowerCase();
    if (lowerId.isEmpty) return false;

    _onlineKeys.add('id:$lowerId');
    _onlineKeys.addAll(_hostKeysFor(deviceId, host: host));

    final effectiveIp = (ip?.trim().isNotEmpty ?? false)
        ? ip!.trim()
        : _deviceIp(deviceId);
    if (effectiveIp != null && effectiveIp.isNotEmpty) {
      _onlineKeys.add('ip:$effectiveIp');
    }

    if (when != null) {
      return _updateDeviceLastSeenInMemory(deviceId, when, ip: effectiveIp);
    }
    return false;
  }

  void _markDeviceOffline(String deviceId, {String? host, String? ip}) {
    final lowerId = deviceId.trim().toLowerCase();
    if (lowerId.isEmpty) return;

    _onlineKeys.remove('id:$lowerId');
    for (final value in _hostKeysFor(deviceId, host: host)) {
      _onlineKeys.remove(value);
    }

    final effectiveIp = (ip?.trim().isNotEmpty ?? false)
        ? ip!.trim()
        : _deviceIp(deviceId);
    if (effectiveIp != null && effectiveIp.isNotEmpty) {
      _onlineKeys.remove('ip:$effectiveIp');
    }
  }

  AuthUser? get _user => _auth.currentUser.value;

  @override
  void initState() {
    super.initState();
    _pageCtrl.addListener(() => setState(() => _page = _pageCtrl.page ?? 0));
    _refresh();
    _startLanPolling();
  }

  @override
  void dispose() {
    _lanTimer?.cancel();
    _pageCtrl.dispose();
    for (final sub in _servoSignalSubs.values) {
      sub.cancel();
    }
    for (final sub in _servoActuatorSubs.values) {
      sub.cancel();
    }
    for (final sub in _detectorSignalSubs.values) {
      sub.cancel();
    }
    for (final timer in _detectorPollTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  // ============== CARGA DE DATOS ==============

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final db = AppDb.instance;

      // 1) Familia desde SQLite local
      final famRows = await (await db.database).query(FamilyMember.tableName);

      // 2) Dispositivos registrados (DB local). Esto asegura que
      //    SIEMPRE mostramos los registrados —aunque estén desconectados—.
      final devsLocal = await db.fetchAllDevices();

      final active = devsLocal.where((d) => d.homeActive).toList();

      setState(() {
        _family = famRows.map(FamilyMember.fromMap).toList();
        _devices = devsLocal;
        _activeDevices = active;
      });

      _syncServoStreams(active);
      _syncDetectorStreams(active);

      unawaited(_syncTrackedDevices(devsLocal));
      unawaited(_refreshLanOnlineOnce());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncTrackedDevices(List<Device> currentLocal) async {
    try {
      final repo = DeviceRepository.instance;
      final remote = await repo.listDevices();
      final actuatorChanged = await _warmActuators(remote);
      final db = AppDb.instance;
      bool updated = actuatorChanged;
      final tracked = currentLocal
          .map((d) => d.deviceId.trim().toLowerCase())
          .toSet();
      final remoteIds = remote.map((r) => r.id.trim().toLowerCase()).toSet();
      for (final record in remote) {
        final lowerId = record.id.trim().toLowerCase();
        final result = await db.upsertDeviceByDeviceId(
          deviceId: record.id,
          name: record.name,
          type: record.type,
          ip: record.ip,
          addedAt: record.addedAt.millisecondsSinceEpoch,
          lastSeenAt: record.lastSeenAt?.millisecondsSinceEpoch,
        );
        if (!updated) {
          updated = result != 0 || !tracked.contains(lowerId);
        }
      }
      if (currentLocal.isNotEmpty) {
        final toRemove = currentLocal.where(
          (local) => !remoteIds.contains(local.deviceId.trim().toLowerCase()),
        );
        for (final item in toRemove) {
          await db.deleteDeviceByDeviceId(item.deviceId);
          updated = true;
        }
        if (toRemove.isNotEmpty && mounted) {
          setState(() {
            _devices = _devices
                .where(
                  (d) => remoteIds.contains(d.deviceId.trim().toLowerCase()),
                )
                .toList();
            _activeDevices =
                _devices.where((d) => d.homeActive).toList();
          });
          _syncServoStreams(_activeDevices);
          _syncDetectorStreams(_activeDevices);
        }
      }
      if (!updated && !actuatorChanged && remote.isEmpty) {
        return;
      }
      if (!updated && !actuatorChanged) return;
      final refreshed = await db.fetchAllDevices();
      if (!mounted) return;
      setState(() {
        _devices = refreshed
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _activeDevices = _devices.where((d) => d.homeActive).toList();
      });
      _syncServoStreams(_activeDevices);
      _syncDetectorStreams(_activeDevices);
    } catch (e) {
      debugPrint('Error sincronizando dispositivos AI: $e');
    }
  }

  void _startLanPolling() {
    // Hace un barrido por la red local cada 7s para actualizar estado online
    _lanTimer?.cancel();
    _lanTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      _refreshLanOnlineOnce();
    });
  }

  Future<void> _refreshLanOnlineOnce() async {
    try {
      final discovery = LanDiscoveryService();
      final found = await discovery.discover(
        timeout: const Duration(seconds: 4),
      );

      final keys = <String>{};
      final trackedSet = _devices
          .map((d) => d.deviceId.trim().toLowerCase())
          .toSet();
      if (trackedSet.isNotEmpty) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final db = AppDb.instance;
        for (final d in found) {
          final devId = d.deviceId?.trim().toLowerCase();
          if (devId != null && trackedSet.contains(devId)) {
            unawaited(
              db.touchDeviceSeen(
                d.deviceId!,
                ip: d.ip,
                name: d.name.isNotEmpty ? d.name : null,
                type: d.type,
                whenMs: nowMs,
              ),
            );
          }
        }
      }

      for (final d in found) {
        if (d.deviceId != null && d.deviceId!.trim().isNotEmpty) {
          keys.add('id:${d.deviceId!.trim().toLowerCase()}');
        }
        if (d.host != null && d.host!.trim().isNotEmpty) {
          keys.add('host:${d.host!.trim().toLowerCase()}');
        }
        if (d.ip.trim().isNotEmpty) {
          keys.add('ip:${d.ip.trim()}');
        }
      }

      if (!mounted) return;
      setState(() {
        _onlineKeys
          ..clear()
          ..addAll(keys);
      });
    } catch (_) {
      // Silencioso: si falla el mDNS, no queremos romper la Home
    }
  }

  bool _isOnline(Device d) {
    // Regla: si coincide cualquier clave, lo damos por "online"
    final deviceId = d.deviceId.trim().toLowerCase();
    final hostKeys = _hostKeysFor(d.deviceId);
    final nameHost = d.name.trim().toLowerCase();
    if (nameHost.isNotEmpty) {
      hostKeys.add('host:$nameHost');
    }
    final ip = (d.ip ?? '').trim();

    if (deviceId.isNotEmpty && _onlineKeys.contains('id:$deviceId')) {
      return true;
    }
    for (final key in hostKeys) {
      if (_onlineKeys.contains(key)) return true;
    }
    if (ip.isNotEmpty && _onlineKeys.contains('ip:$ip')) {
      return true;
    }

    // Fallback con lastSeenAt; si es reciente mantenemos estado conectado.
    if (d.lastSeenAt != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(d.lastSeenAt!);
      if (DateTime.now().difference(dt) <= _presenceWindow) {
        return true;
      }
    }
    return false;
  }

  void _syncServoStreams(List<Device> devices) {
    final servoIds = devices
        .where(_shouldWatchServo)
        .map((device) => device.deviceId)
        .toSet();

    final removed = <String>[];
    for (final id in List<String>.from(_servoSignalSubs.keys)) {
      if (!servoIds.contains(id)) {
        _servoSignalSubs.remove(id)?.cancel();
        _servoActuatorSubs.remove(id)?.cancel();
        removed.add(id);
      }
    }

    if (removed.isNotEmpty && mounted) {
      setState(() {
        for (final id in removed) {
          _servoSnapshots.remove(id);
          _servoActuators.remove(id);
          _servoBusy.remove(id);
        }
      });
    }

    bool addedDefault = false;
    for (final id in servoIds) {
      unawaited(_ensureServoActuator(id));
      if (!_servoSnapshots.containsKey(id)) {
        _servoSnapshots[id] = const _ServoSnapshot(on: false, pos: null);
        addedDefault = true;
      }

      _servoSignalSubs[id] ??= _remoteService
          .watchLiveSignals(id)
          .listen(
            (signals) => _handleServoSignals(id, signals),
            onError: (error) => debugPrint('Live signals error ($id): $error'),
          );

      _servoActuatorSubs[id] ??= _remoteService
          .watchActuators(id)
          .listen(
            (actuators) => _handleServoActuators(id, actuators),
            onError: (error) => debugPrint('Actuators error ($id): $error'),
          );
    }

    if (addedDefault && mounted) {
      setState(() {});
    }
  }

  void _syncDetectorStreams(List<Device> devices) {
    final detectorIds = devices
        .where((device) => _deviceKind(device) == _DeviceKind.detector)
        .map((device) => device.deviceId)
        .toSet();

    for (final id in List<String>.from(_detectorSignalSubs.keys)) {
      if (!detectorIds.contains(id)) {
        _detectorSignalSubs.remove(id)?.cancel();
        _detectorLiveData.remove(id);
        _detectorPollTimers.remove(id)?.cancel();
      }
    }

    bool changed = false;
    for (final id in detectorIds) {
      if (_detectorSignalSubs.containsKey(id)) continue;
      _detectorSignalSubs[id] = _remoteService
          .watchLiveSignals(id)
          .listen(
            (signals) => _handleDetectorSignals(id, signals),
            onError: (error) =>
                debugPrint('Detector signals error ($id): $error'),
          );
      _ensureDetectorPolling(id);
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  void _handleServoSignals(String deviceId, List<RemoteLiveSignal> signals) {
    final snapshot = _extractSnapshotFromSignals(signals);
    final latest = _latestUpdatedAt(signals);
    if (snapshot != null || latest != null) {
      _mergeServoSnapshot(deviceId, snapshot, updatedAt: latest);
    }
  }

  void _handleServoActuators(String deviceId, List<RemoteActuator> actuators) {
    RemoteActuator? match;
    for (final actuator in actuators) {
      final kind = actuator.kind.toLowerCase();
      final metaKind = actuator.meta['kind']?.toString().toLowerCase() ?? '';
      if (kind.contains('servo') || metaKind.contains('servo')) {
        match = actuator;
        break;
      }
    }

    if (mounted) {
      final resolved = match;
      setState(() {
        if (resolved != null) {
          _servoActuators[deviceId] = resolved;
        } else {
          _servoActuators.remove(deviceId);
        }
      });
    }

    if (match != null) {
      final onValue = _parseOnValue(match.meta['on'] ?? match.meta['state']);
      final posValue = _parsePosValue(
        match.meta['pos'] ?? match.meta['position'],
      );
      if (onValue != null || posValue != null) {
        _mergeServoSnapshot(
          deviceId,
          _ServoSnapshot(on: onValue, pos: posValue),
        );
      }
    }
  }

  void _handleDetectorSignals(String deviceId, List<RemoteLiveSignal> signals) {
    final data = _extractDetectorData(signals);
    final latest = _latestUpdatedAt(signals);
    final isFresh = latest != null && _isTimestampFresh(latest);
    final hostHint = data != null ? data['host']?.toString() : null;
    final ipHint = data != null ? data['ip']?.toString() : null;

    if (!mounted) {
      if (data != null) {
        _detectorLiveData[deviceId] = data;
      } else {
        _detectorLiveData.remove(deviceId);
      }
      if (isFresh && latest != null) {
        _markDeviceOnline(deviceId, host: hostHint, ip: ipHint, when: latest);
      } else {
        _markDeviceOffline(deviceId, host: hostHint, ip: ipHint);
      }
      return;
    }

    bool updatedInMemory = false;
    setState(() {
      if (data != null) {
        _detectorLiveData[deviceId] = data;
      } else {
        _detectorLiveData.remove(deviceId);
      }

      if (isFresh && latest != null) {
        updatedInMemory = _markDeviceOnline(
          deviceId,
          host: hostHint,
          ip: ipHint,
          when: latest,
        );
      } else {
        _markDeviceOffline(deviceId, host: hostHint, ip: ipHint);
      }
    });

    if (isFresh && latest != null && updatedInMemory) {
      unawaited(
        AppDb.instance.touchDeviceSeen(
          deviceId,
          ip: ipHint ?? _deviceIp(deviceId),
          whenMs: latest.millisecondsSinceEpoch,
        ),
      );
    }

    _ensureDetectorPolling(deviceId);
  }

  void _ensureDetectorPolling(String deviceId) {
    _detectorPollTimers.remove(deviceId)?.cancel();
    _detectorPollTimers[deviceId] = Timer.periodic(const Duration(seconds: 1), (
      _,
    ) async {
      try {
        final signals = await _remoteService.fetchLiveSignals(deviceId);
        final data = _extractDetectorData(signals);
        final latest = _latestUpdatedAt(signals);
        final isFresh = latest != null && _isTimestampFresh(latest);
        final hostHint = data != null ? data['host']?.toString() : null;
        final ipHint = data != null ? data['ip']?.toString() : null;

        if (!mounted) {
          if (data != null) {
            _detectorLiveData[deviceId] = data;
          }
          if (isFresh && latest != null) {
            final updated = _markDeviceOnline(
              deviceId,
              host: hostHint,
              ip: ipHint,
              when: latest,
            );
            if (updated) {
              unawaited(
                AppDb.instance.touchDeviceSeen(
                  deviceId,
                  ip: ipHint ?? _deviceIp(deviceId),
                  whenMs: latest.millisecondsSinceEpoch,
                ),
              );
            }
          } else {
            _markDeviceOffline(deviceId, host: hostHint, ip: ipHint);
          }
          return;
        }

        bool updatedInMemory = false;
        if (data != null) {
          setState(() {
            _detectorLiveData[deviceId] = data;
            if (isFresh && latest != null) {
              updatedInMemory = _markDeviceOnline(
                deviceId,
                host: hostHint,
                ip: ipHint,
                when: latest,
              );
            } else {
              _markDeviceOffline(deviceId, host: hostHint, ip: ipHint);
            }
          });
          if (isFresh && latest != null && updatedInMemory) {
            unawaited(
              AppDb.instance.touchDeviceSeen(
                deviceId,
                ip: ipHint ?? _deviceIp(deviceId),
                whenMs: latest.millisecondsSinceEpoch,
              ),
            );
          }
        } else {
          setState(() {
            _detectorLiveData.remove(deviceId);
            _markDeviceOffline(deviceId, host: hostHint, ip: ipHint);
          });
        }
      } catch (e) {
        debugPrint('Detector poll error ($deviceId): $e');
      }
    });
  }

  Map<String, dynamic>? _extractDetectorData(List<RemoteLiveSignal> signals) {
    if (signals.isEmpty) return null;

    RemoteLiveSignal? selected;
    for (final signal in signals) {
      final name = signal.name.toLowerCase();
      final kind = signal.kind.toLowerCase();
      if (name.contains('detector') || kind.contains('detector')) {
        selected = signal;
        break;
      }
      if (selected == null &&
          (kind == 'other' ||
              name.contains('state') ||
              name.contains('detector'))) {
        selected = signal;
      }
    }
    selected ??= signals.first;

    final map = <String, dynamic>{};
    if (selected.valueNumeric != null) {
      map['distance_cm'] = selected.valueNumeric;
    }
    if (selected.valueText != null && selected.valueText!.isNotEmpty) {
      map['state'] = selected.valueText;
    }
    final extra = selected.extra;
    if (extra.isNotEmpty) {
      final soundEvt = extra['sound_evt'];
      if (soundEvt is bool) {
        map['sound_event'] = soundEvt;
      } else if (soundEvt is num) {
        map['sound_event'] = soundEvt != 0;
      }
      final soundDo = extra['sound_do'];
      if (soundDo is num) {
        map['sound_raw'] = soundDo.toInt();
      } else if (soundDo != null) {
        map['sound_raw'] = soundDo.toString();
      }
      if (!map.containsKey('distance_cm')) {
        final cm = extra['ultra_cm'];
        if (cm is num) {
          map['distance_cm'] = cm.toDouble();
        }
      }
      final ultraOk = extra['ultra_ok'];
      if (ultraOk is bool) {
        map['ultrasonic_ok'] = ultraOk;
      } else if (ultraOk is num) {
        map['ultrasonic_ok'] = ultraOk != 0;
      }
      for (final entry in extra.entries) {
        map[entry.key] = entry.value;
      }
    }
    map['updated_at'] = selected.updatedAt.toIso8601String();
    return map;
  }

  _ServoSnapshot? _extractSnapshotFromSignals(List<RemoteLiveSignal> signals) {
    bool? on;
    int? pos;

    for (final signal in signals) {
      final name = signal.name.toLowerCase();
      final kind = signal.kind.toLowerCase();
      if (!name.contains('servo') && !kind.contains('servo')) {
        continue;
      }

      if (signal.valueText != null) {
        final parsed = _parseOnValue(signal.valueText);
        if (parsed != null && on == null) {
          on = parsed;
        }
      }

      if (signal.valueNumeric != null) {
        final numeric = signal.valueNumeric!;
        pos ??= _parsePosValue(numeric);
        on ??= numeric >= 90;
      }

      final extra = signal.extra;
      final extraOn = _parseOnValue(extra['on'] ?? extra['state']);
      if (extraOn != null && on == null) {
        on = extraOn;
      }
      final extraPos = _parsePosValue(extra['pos'] ?? extra['position']);
      if (extraPos != null && pos == null) {
        pos = extraPos;
      }

      final servoExtra = extra['servo'];
      if (servoExtra is Map) {
        final mapped = servoExtra.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final servoOn = _parseOnValue(mapped['on']);
        final servoPos = _parsePosValue(mapped['pos']);
        if (servoOn != null && on == null) {
          on = servoOn;
        }
        if (servoPos != null && pos == null) {
          pos = servoPos;
        }
      }
    }

    if (on != null || pos != null) {
      return _ServoSnapshot(on: on, pos: pos);
    }
    return null;
  }

  DateTime? _latestUpdatedAt(List<RemoteLiveSignal> signals) {
    DateTime? latest;
    for (final signal in signals) {
      final ts = signal.updatedAt;
      if (latest == null || ts.isAfter(latest)) {
        latest = ts;
      }
    }
    return latest;
  }

  bool _isTimestampFresh(DateTime timestamp) {
    return DateTime.now().difference(timestamp).abs() <= _presenceWindow;
  }

  bool _updateDeviceLastSeenInMemory(
    String deviceId,
    DateTime when, {
    String? ip,
  }) {
    final lower = deviceId.trim().toLowerCase();
    final index = _devices.indexWhere(
      (element) => element.deviceId.trim().toLowerCase() == lower,
    );
    if (index == -1) return false;
    final existing = _devices[index];
    final newMs = when.millisecondsSinceEpoch;
    if (existing.lastSeenAt != null && existing.lastSeenAt! >= newMs) {
      if (ip != null && ip.isNotEmpty && existing.ip != ip) {
        final updated = List<Device>.from(_devices);
        updated[index] = updated[index].copyWith(ip: ip);
        _devices = updated;
      }
      return false;
    }

    final updated = List<Device>.from(_devices);
    updated[index] = updated[index].copyWith(
      lastSeenAt: newMs,
      ip: ip ?? existing.ip,
    );
    _devices = updated;
    return true;
  }

  bool? _parseOnValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) {
      if (value == 0) return false;
      if (value == 1) return true;
      return value >= 90;
    }
    final normalized = value.toString().trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if ({
      'true',
      'on',
      '1',
      'encendido',
      'open',
      'activo',
      'abierto',
    }.contains(normalized)) {
      return true;
    }
    if ({
      'false',
      'off',
      '0',
      'apagado',
      'close',
      'cerrado',
    }.contains(normalized)) {
      return false;
    }
    return null;
  }

  int? _parsePosValue(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final clamped = value.clamp(0, 180).round();
      return clamped;
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null) return null;
    return parsed.clamp(0, 180);
  }

  void _mergeServoSnapshot(
    String deviceId,
    _ServoSnapshot? incoming, {
    DateTime? updatedAt,
  }) {
    final isFresh = updatedAt != null && _isTimestampFresh(updatedAt);
    final ipHint = _deviceIp(deviceId);

    void updateSnapshot() {
      if (incoming == null) return;
      final current = _servoSnapshots[deviceId];
      final newOn = incoming.on ?? current?.on;
      final newPos = incoming.pos ?? current?.pos;
      if (current?.on == newOn && current?.pos == newPos) {
        return;
      }
      _servoSnapshots[deviceId] = _ServoSnapshot(on: newOn, pos: newPos);
    }

    if (!mounted) {
      updateSnapshot();
      if (updatedAt != null) {
        if (isFresh) {
          _markDeviceOnline(deviceId, ip: ipHint, when: updatedAt);
        } else {
          _markDeviceOffline(deviceId, ip: ipHint);
        }
      }
      return;
    }

    bool updatedInMemory = false;
    setState(() {
      updateSnapshot();
      if (updatedAt != null) {
        if (isFresh) {
          updatedInMemory = _markDeviceOnline(
            deviceId,
            ip: ipHint,
            when: updatedAt,
          );
        } else {
          _markDeviceOffline(deviceId, ip: ipHint);
        }
      }
    });

    if (updatedAt != null && isFresh && updatedInMemory) {
      unawaited(
        AppDb.instance.touchDeviceSeen(
          deviceId,
          ip: ipHint,
          whenMs: updatedAt.millisecondsSinceEpoch,
        ),
      );
    }
  }

  Map<String, dynamic>? _cardLiveDataFor(Device device) {
    final snapshot = _servoSnapshots[device.deviceId];
    if (snapshot != null) {
      final servo = <String, dynamic>{
        'on': snapshot.on ?? false,
        if (snapshot.pos != null) 'pos': snapshot.pos,
      };
      return {'servo': servo};
    }
    if (_hasServoControls(device)) {
      return {
        'servo': {'on': false},
      };
    }
    return null;
  }

  bool _shouldWatchServo(Device device) =>
      _deviceKind(device) == _DeviceKind.servo ||
      _servoActuators.containsKey(device.deviceId) ||
      _servoSnapshots.containsKey(device.deviceId);

  bool _isServoType(String type) => type.toLowerCase().contains('servo');

  bool _hasServoControls(Device device) =>
      _isServoType(device.type) ||
      _servoActuators.containsKey(device.deviceId) ||
      _servoSnapshots.containsKey(device.deviceId);

  _DeviceKind _deviceKind(Device device) {
    if (_hasServoControls(device)) {
      return _DeviceKind.servo;
    }
    final typeLower = device.type.toLowerCase();
    final nameLower = device.name.toLowerCase();
    if (_isCameraString(typeLower) || _isCameraString(nameLower)) {
      return _DeviceKind.camera;
    }
    if (typeLower.contains('esp') || typeLower.contains('detector')) {
      return _DeviceKind.detector;
    }
    return _DeviceKind.detector;
  }

  bool _isCameraString(String value) =>
      value.contains('cam') || value.contains('camera');

  Future<void> _toggleServoFromCard(Device device, bool on) async {
    final id = device.deviceId;
    if (_servoBusy.contains(id)) return;

    _setServoBusy(id, true);
    String? error;
    try {
      error = await _sendServoCommandRemote(id, on);
    } catch (e) {
      error = 'Error al enviar el comando al servo.';
      debugPrint('Error toggling servo ' + id + ': ' + e.toString());
    } finally {
      _setServoBusy(id, false);
    }

    if (error == null) {
      _mergeServoSnapshot(id, _ServoSnapshot(on: on, pos: on ? 180 : 0));
      _showHomeSnack('${device.name} ${on ? 'activado' : 'desactivado'}');
    } else {
      _showHomeSnack(error);
    }
  }

  Future<String?> _sendServoCommandRemote(String deviceId, bool on) async {
    final actuator = await _ensureServoActuator(deviceId);
    if (actuator == null) {
      return 'No se encontro un actuador de tipo servo en Supabase.';
    }
    try {
      await _remoteService.enqueueCommand(
        actuatorId: actuator.id,
        command: {
          'action': 'set_servo',
          'payload': {'on': on},
          'origin': 'home_card',
          'issued_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      return null;
    } catch (e) {
      debugPrint('Error enviando comando remoto: $e');
      return 'Error al enviar el comando al servo.';
    }
  }

  void _setServoBusy(String deviceId, bool value) {
    if (!mounted) return;
    setState(() {
      if (value) {
        _servoBusy.add(deviceId);
      } else {
        _servoBusy.remove(deviceId);
      }
    });
  }

  void _showHomeSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<RemoteActuator?> _ensureServoActuator(String deviceId) async {
    var actuator = _servoActuators[deviceId];
    if (actuator != null) return actuator;

    try {
      final fetched = await _remoteService.fetchActuators(deviceId);
      RemoteActuator? candidate;
      for (final item in fetched) {
        final kind = item.kind.toLowerCase();
        final metaKind = item.meta['kind']?.toString().toLowerCase() ?? '';
        if (kind.contains('servo') || metaKind.contains('servo')) {
          candidate = item;
          break;
        }
      }
      candidate ??= fetched.isNotEmpty ? fetched.first : null;
      actuator = candidate;
      if (actuator != null) {
        final RemoteActuator resolved = actuator;
        if (mounted) {
          setState(() => _servoActuators[deviceId] = resolved);
        } else {
          _servoActuators[deviceId] = resolved;
        }
        _syncServoStreams(_activeDevices);
      }
      return actuator;
    } catch (e) {
      debugPrint(
        'Error fetching actuators for ' + deviceId + ': ' + e.toString(),
      );
      return null;
    }
  }

  Future<bool> _warmActuators(List<DeviceRecord> remoteDevices) async {
    bool changed = false;
    for (final record in remoteDevices) {
      final id = record.id;
      if (_servoActuators.containsKey(id)) continue;
      try {
        final fetched = await _remoteService.fetchActuators(id);
        RemoteActuator? candidate;
        for (final item in fetched) {
          final kind = item.kind.toLowerCase();
          final metaKind = item.meta['kind']?.toString().toLowerCase() ?? '';
          if (kind.contains('servo') || metaKind.contains('servo')) {
            candidate = item;
            break;
          }
        }
        if (candidate == null) {
          for (final item in fetched) {
            final meta = item.meta;
            if (meta['on'] != null || meta['pos'] != null) {
              candidate = item;
              break;
            }
          }
        }
        if (candidate != null) {
          final RemoteActuator resolved = candidate;
          _servoActuators[id] = resolved;
          unawaited(AppDb.instance.touchDeviceSeen(id, type: 'servo'));
          unawaited(DeviceRepository.instance.updateType(id, 'servo'));
          changed = true;
        }
      } catch (e) {
        debugPrint('Error warming actuators for ' + id + ': ' + e.toString());
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
    return changed;
  }

  // ============== ACCIONES ==============

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Get.offAll(() => LoginScreen(circleNotifier: widget.circleNotifier));
  }

  Future<void> _goToDevices() async {
    await Get.to(() => const DevicesPage());
    if (mounted) {
      unawaited(_refresh());
    }
  }

  Widget _buildDevicesGrid() {
    const spacing = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final children = <Widget>[];
        int index = 0;
        final devices = _activeDevices;
        while (index < devices.length) {
          final cycle = index % 3;
          final remaining = devices.length - index;
          if ((cycle == 0 || cycle == 1) && remaining >= 2) {
            children.add(
              Row(
                children: [
                  Expanded(child: _buildHomeDeviceCard(devices[index])),
                  const SizedBox(width: spacing),
                  Expanded(child: _buildHomeDeviceCard(devices[index + 1])),
                ],
              ),
            );
            children.add(const SizedBox(height: spacing));
            index += 2;
          } else {
            children.add(
              SizedBox(
                width: double.infinity,
                child: _buildHomeDeviceCard(devices[index]),
              ),
            );
            children.add(const SizedBox(height: spacing));
            index += 1;
          }
        }
        if (children.isNotEmpty) {
          children.removeLast();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  Widget _buildHomeDeviceCard(Device device) {
    final online = _isOnline(device);
    final kind = _deviceKind(device);
    final showServo = kind == _DeviceKind.servo;
    final liveData =
        showServo ? _cardLiveDataFor(device) : _detectorLiveData[device.deviceId];

    String displayType;
    if (kind == _DeviceKind.servo) {
      displayType = 'servo';
    } else if (kind == _DeviceKind.camera) {
      displayType = 'camera';
    } else {
      displayType = device.type.isNotEmpty ? device.type : 'esp32';
    }

    final data = DeviceCardData(
      deviceId: device.deviceId,
      name: device.name,
      type: displayType,
      ip: device.ip,
      host: device.deviceId,
      online: online,
      lastSeenAt: device.lastSeenAt != null
          ? DateTime.fromMillisecondsSinceEpoch(device.lastSeenAt!)
          : null,
      liveData: liveData,
    );

    return DeviceCard(
      data: data,
      onOpen: () {
        Get.to(
          () => DeviceDetailPage(
            deviceId: device.deviceId,
            name: device.name,
            type: displayType,
            ip: device.ip,
            lastSeenAt: device.lastSeenAt != null
                ? DateTime.fromMillisecondsSinceEpoch(device.lastSeenAt!)
                : null,
          ),
        );
      },
      onRefresh: () => unawaited(_refresh()),
      onServoToggle:
          showServo ? (value) => _toggleServoFromCard(device, value) : null,
      isTogglingServo:
          showServo && _servoBusy.contains(device.deviceId),
    );
  }

  Future<void> _goToProvisioning() async {
    await Get.to(() => const ProvisioningScreen());
    if (mounted) {
      unawaited(_refresh());
    }
  }

  // ============== UI ==============

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: const [
          // ÚNICO botón de tema en la pantalla
          ThemeToggleButton(),
        ],
        leading: IconButton(
          tooltip: 'Cerrar sesión',
          icon: const Icon(Icons.logout),
          onPressed: _logout,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  // —— Avatar del usuario grande y centrado ——
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Center(
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: cs.primaryContainer,
                          child: Text(
                            _initials(_user),
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // —— Sección Familia (carrusel con foco central) ——
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Row(
                        children: [
                          Icon(Icons.family_restroom, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Familia',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          const Spacer(),
                          if (_family.isNotEmpty)
                            Text(
                              '${_family.length}',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 150,
                      child: _family.isEmpty
                          ? _EmptyInline(
                              icon: Icons.person_add_alt_1,
                              title: 'Sin familiares',
                              actionText: 'Añadir',
                              onAction: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Pantalla de familia pendiente.',
                                    ),
                                  ),
                                );
                              },
                            )
                          : PageView.builder(
                              controller: _pageCtrl,
                              itemCount: _family.length,
                              padEnds: true,
                              itemBuilder: (ctx, i) {
                                final t = (i - _page).abs().clamp(0, 1);
                                final scale = 1 - (0.16 * t);
                                final opacity = 1 - (0.55 * t);
                                return Center(
                                  child: AnimatedScale(
                                    scale: scale,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                    child: AnimatedOpacity(
                                      opacity: opacity,
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      child: _FamilyCard(member: _family[i]),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),

                  // —— Sección Dispositivos registrados (DB) + estado LAN (mDNS) ——
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Row(
                        children: [
                          Icon(Icons.devices_other, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Dispositivos',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _goToProvisioning,
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 16,
                            ),
                            label: const Text('Agregar'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _goToDevices,
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Ver todos'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_activeDevices.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: _EmptyInline(
                          icon: Icons.smart_toy_outlined,
                          title: 'Sin dispositivos activos en Inicio',
                          actionText: 'Elegir dispositivos',
                          onAction: _goToDevices,
                        ),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: _buildDevicesGrid(),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
      ),
      // Barra inferior simple (sin botón extra de “agregar”, ya está en otra pantalla)
      bottomNavigationBar: _BottomNav(
        onHelp: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Centro de ayuda (pendiente).')),
          );
        },
        onFamily: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pantalla de familia (pendiente).')),
          );
        },
        onHome: () {},
        onDevices: _goToDevices,
      ),
    );
  }

  String _initials(AuthUser? u) {
    final name = (u?.name ?? '').trim();
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+'));
      final a = parts.first.isNotEmpty ? parts.first[0] : '';
      final b = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
      return (a + b).toUpperCase();
    }
    final email = (u?.email ?? 'U');
    return email.isNotEmpty ? email[0].toUpperCase() : 'U';
  }
}

/* ======================= Widgets de Sección ======================= */

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.member});
  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 230,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.secondaryContainer,
            child: Text(
              _initials(member.name),
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    member.relation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  if ((member.phone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      member.phone!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final a = parts.isNotEmpty ? parts.first[0] : ' ';
    final b = parts.length > 1 ? parts.last[0] : ' ';
    return (a + b).toUpperCase();
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({
    required this.icon,
    required this.title,
    required this.actionText,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String actionText;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 36, color: cs.onSurfaceVariant),
        const SizedBox(height: 10),
        Text(title, style: TextStyle(color: cs.onSurfaceVariant)),
        TextButton(onPressed: onAction, child: Text(actionText)),
      ],
    );
  }
}

/* ======================= Bottom Navigation ======================= */

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.onHelp,
    required this.onFamily,
    required this.onHome,
    required this.onDevices,
  });

  final VoidCallback onHelp;
  final VoidCallback onFamily;
  final VoidCallback onHome;
  final VoidCallback onDevices;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavBtn(icon: Icons.help_outline, label: 'Ayuda', onTap: onHelp),
            _NavBtn(
              icon: Icons.people_alt_outlined,
              label: 'Familia',
              onTap: onFamily,
            ),
            _NavBtn(
              icon: Icons.home_filled,
              label: 'Inicio',
              onTap: onHome,
              active: true,
            ),
            _NavBtn(
              icon: Icons.devices_other,
              label: 'Dispositivos',
              onTap: onDevices,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
