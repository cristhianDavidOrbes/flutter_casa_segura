import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_seguridad_en_casa/core/config/environment.dart';
import 'package:flutter_seguridad_en_casa/features/security/application/detection_engine.dart';
import 'package:flutter_seguridad_en_casa/features/security/application/gemini_vision_service.dart';
import 'package:flutter_seguridad_en_casa/features/family/application/family_presence_service.dart';
import 'package:flutter_seguridad_en_casa/repositories/family_repository.dart';
import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/features/security/application/notification_service.dart';
import 'package:flutter_seguridad_en_casa/features/security/data/security_event_store.dart';
import 'package:flutter_seguridad_en_casa/features/security/domain/security_event.dart';
import 'package:flutter_seguridad_en_casa/repositories/device_repository.dart';
import 'package:flutter_seguridad_en_casa/services/remote_device_service.dart';
import 'package:flutter_seguridad_en_casa/services/motion_settings_service.dart';

class SecurityMonitorService {
  SecurityMonitorService._();

  static final SecurityMonitorService instance = SecurityMonitorService._();

  final DeviceRepository _deviceRepository = DeviceRepository.instance;
  final RemoteDeviceService _remoteService = RemoteDeviceService();
  final DetectionEngine _detectionEngine = DetectionEngine.instance;
  final GeminiVisionService _visionService = GeminiVisionService.instance;
  final SupabaseClient _client = Supabase.instance.client;
  final HttpClient _baseHttpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  late final http.Client _httpClient = IOClient(_baseHttpClient);

  Timer? _cameraTimer;
  Timer? _sensorTimer;
  bool _isForeground = true;

  static const Duration _foregroundPollInterval = Duration(seconds: 5);
  static const Duration _backgroundPollInterval = Duration(seconds: 18);
  bool _running = false;
  bool _cameraPolling = false;
  bool _sensorPolling = false;

  final Map<String, _PendingDetection> _pendingDetections = {};
  final Map<String, _SignalCache> _signalCache = {};
  final Map<String, String> _deviceSnapshotUrls = {};
  final Map<String, DateTime> _snapshotCooldown = {};
  final Map<String, _SignedUrlCache> _signedUrlCache = {};
  final MotionSettingsService _motionSettings = MotionSettingsService.instance;
  final Map<String, _MotionCandidate> _motionCandidates = {};
  final Map<String, DateTime> _motionCooldownUntil = {};
  static const Duration _motionHoldDuration = Duration(seconds: 2);
  static const Duration _motionCooldownDuration = Duration(seconds: 15);
  List<DeviceRecord> _cachedDevices = <DeviceRecord>[];
  DateTime _lastDeviceRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _deviceRefreshInterval = Duration(seconds: 30);
  static const Duration _signalCacheTtl = Duration(seconds: 12);
  static const Duration _snapshotRetryDelay = Duration(seconds: 30);
  bool get _isAuthenticated => _client.auth.currentUser != null;

  Future<void> start() async {
    if (_running) return;
    if (!_ensureAuthenticated()) {
      return;
    }
    _running = true;

    _scheduleCameraTick(immediate: true);
    _scheduleSensorTick(immediate: true);
  }

  Duration get _cameraInterval =>
      _isForeground ? _foregroundPollInterval : _backgroundPollInterval;

  Duration get _sensorInterval =>
      _isForeground ? _foregroundPollInterval : _backgroundPollInterval;

  void _scheduleCameraTick({bool immediate = false}) {
    _cameraTimer?.cancel();
    if (!_running) return;
    final delay = immediate ? Duration.zero : _cameraInterval;
    _cameraTimer = Timer(delay, () async {
      _cameraTimer = null;
      await _pollCameras();
      if (_running) {
        _scheduleCameraTick();
      }
    });
  }

  void _scheduleSensorTick({bool immediate = false}) {
    _sensorTimer?.cancel();
    if (!_running) return;
    final delay = immediate ? Duration.zero : _sensorInterval;
    _sensorTimer = Timer(delay, () async {
      _sensorTimer = null;
      await _pollSensors();
      if (_running) {
        _scheduleSensorTick();
      }
    });
  }

  void stop() {
    _cameraTimer?.cancel();
    _sensorTimer?.cancel();
    _cameraTimer = null;
    _sensorTimer = null;
    _running = false;
    _cameraPolling = false;
    _sensorPolling = false;
    _pendingDetections.clear();
    _motionCandidates.clear();
    _motionCooldownUntil.clear();
    _signalCache.clear();
    _deviceSnapshotUrls.clear();
    _snapshotCooldown.clear();
    _signedUrlCache.clear();
    _signalCache.clear();
    _deviceSnapshotUrls.clear();
    _cachedDevices = <DeviceRecord>[];
    _lastDeviceRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void updateForegroundStatus(bool isForeground) {
    final nextState = isForeground;
    if (_isForeground == nextState) return;
    _isForeground = nextState;
    if (!_running) return;
    debugPrint(
      'SecurityMonitorService: ajustando intervalo a '
      '${nextState ? _foregroundPollInterval.inSeconds : _backgroundPollInterval.inSeconds}s',
    );
    _scheduleCameraTick(immediate: nextState);
    _scheduleSensorTick(immediate: nextState);
  }

  Future<void> _pollCameras() async {
    if (!_running || _cameraPolling) return;
    if (!_ensureAuthenticated()) return;
    _cameraPolling = true;
    try {
      final devices = await _getAvailableDevices();
      for (final device in devices) {
        if (!device.type.toLowerCase().contains('cam')) continue;
        await _processCameraDevice(device.id, device.name);
      }
    } catch (e, st) {
      debugPrint('Camera poll error: $e\n$st');
    } finally {
      _cameraPolling = false;
    }
  }

  Future<void> _processCameraDevice(String deviceId, String deviceName) async {
    final snapshot = await _downloadCameraSnapshot(deviceId);
    if (snapshot == null) {
      await _clearPending(deviceId);
      return;
    }

    final detection = await _detectionEngine.analyzeImage(snapshot.bytes);
    if (detection == null) {
      await _clearPending(deviceId);
      return;
    }

    final now = DateTime.now();
    var pending = _pendingDetections[deviceId];

    if (pending == null ||
        !DetectionEngine.isSimilar(pending.firstResult, detection)) {
      final tempPath = await _storeTempEvidence(snapshot.bytes, deviceId);
      pending = _PendingDetection(
        firstResult: detection,
        tempImagePath: tempPath,
        firstSeen: now,
        lastSeen: now,
        stage: _DetectionStage.green,
        snapshotUrl: snapshot.url,
      );
      _pendingDetections[deviceId] = pending;
      await NotificationService.instance.showDetectionStage(
        deviceName: deviceName,
        severity: DetectionSeverity.green,
        message: 'Se detecto movimiento puntual en $deviceName.',
      );
      return;
    }

    pending.lastSeen = now;
    pending.snapshotUrl = snapshot.url ?? pending.snapshotUrl;

    switch (pending.stage) {
      case _DetectionStage.green:
        pending.stage = _DetectionStage.yellow;
        await NotificationService.instance.showDetectionStage(
          deviceName: deviceName,
          severity: DetectionSeverity.yellow,
          message: 'La presencia persiste en $deviceName. Verifica la camara.',
        );
        break;
      case _DetectionStage.yellow:
        pending.stage = _DetectionStage.red;
        await _finalizeConfirmedDetection(
          deviceId: deviceId,
          deviceName: deviceName,
          pending: pending,
          detection: detection,
          snapshot: snapshot,
        );
        break;
      case _DetectionStage.red:
        // Ya se proceso la alerta critica; esperar a que desaparezca.
        break;
    }
  }

  Future<void> _finalizeConfirmedDetection({
    required String deviceId,
    required String deviceName,
    required _PendingDetection pending,
    required DetectionResult detection,
    required _SnapshotResult snapshot,
  }) async {
    final path = await _storeImage(snapshot.bytes, deviceId);

    FamilyMatch? familyMatch;
    if (detection.label.toLowerCase().contains('rostro')) {
      try {
        familyMatch = await FamilyPresenceService.instance.identify(
          snapshot.bytes,
        );
      } catch (e) {
        debugPrint('Family match error: $e');
      }
    }

    final scheduleWindow = familyMatch != null
        ? _formatScheduleWindow(familyMatch.member)
        : null;

    final descriptionFromGemini =
        await _visionService.describeImage(
          snapshot.bytes,
          context:
              'Describe detalladamente lo que se observa en esta captura del dispositivo "$deviceName". '
              'Enfocate en caracteristicas relevantes para seguridad.',
        ) ??
        'El dispositivo "$deviceName" detecto ${detection.label.toLowerCase()} '
            '(${(detection.confidence * 100).toStringAsFixed(1)}% confianza).';

    final scheduleMessage = familyMatch != null && scheduleWindow != null
        ? (familyMatch.withinSchedule
              ? 'security.event.family.within'.trParams({
                  'window': scheduleWindow,
                })
              : 'security.event.family.outside'.trParams({
                  'window': scheduleWindow,
                }))
        : null;

    final description = scheduleMessage == null
        ? descriptionFromGemini
        : '${descriptionFromGemini.trim()}\n\n$scheduleMessage';

    final baseLabel = familyMatch != null
        ? 'security.event.familyLabel'.trParams({
            'name': familyMatch.member.name,
          })
        : detection.label;

    final event = SecurityEvent(
      deviceId: deviceId,
      deviceName: deviceName,
      label: '🔴 $baseLabel',
      description: description,
      localImagePath: path,
      createdAt: DateTime.now(),
      remoteImageUrl: pending.snapshotUrl,
      familyMemberId: familyMatch?.member.id,
      familyMemberName: familyMatch?.member.name,
      familyScheduleMatched: familyMatch?.withinSchedule,
    );

    await SecurityEventStore.add(event);
    await NotificationService.instance.showSecurityAlert(event);
    unawaited(_syncEventToSupabase(event));

    if (familyMatch != null && familyMatch.member.id != null) {
      try {
        final deviceRow = await AppDb.instance.getDeviceByDeviceId(deviceId);
        final deviceRowId = deviceRow?.id;
        if (deviceRowId != null) {
          unawaited(
            FamilyRepository.instance.recordPresenceEvent(
              memberId: familyMatch.member.id!,
              deviceId: deviceRowId,
              type: familyMatch.withinSchedule
                  ? 'entry'
                  : 'entry_out_of_schedule',
              timestamp: event.createdAt.millisecondsSinceEpoch,
              imagePath: path,
            ),
          );
        }
      } catch (e) {
        debugPrint('Family presence log error: $e');
      }
    }

    if (pending.tempImagePath != null) {
      try {
        final file = File(pending.tempImagePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Temp cleanup error for $deviceId: $e');
      }
      pending.tempImagePath = null;
    }

    pending.stage = _DetectionStage.red;
  }

  Future<void> _pollSensors() async {
    if (!_running || _sensorPolling) return;
    if (!_ensureAuthenticated()) return;
    _sensorPolling = true;
    try {
      final devices = await _getAvailableDevices();
      for (final device in devices) {
        final typeLower = device.type.toLowerCase();
        if (typeLower.contains('cam')) continue;
        if (typeLower.contains('detector')) {
          await _processMotionDevice(device);
        }
      }
    } catch (e, st) {
      debugPrint('Sensor poll error: $e\n$st');
    } finally {
      _sensorPolling = false;
    }
  }

  Future<void> _processMotionDevice(DeviceRecord device) async {
    try {
      final sample = await _latestMotionSample(device.id);
      if (sample == null) {
        _motionCandidates.remove(device.id);
        return;
      }

      final distance = sample.distanceCm;
      if (distance < 0 || sample.ultraOk == false) {
        _motionCandidates.remove(device.id);
        return;
      }

      final threshold = _motionSettings.thresholdFor(device.id);
      if (distance > threshold) {
        _motionCandidates.remove(device.id);
        return;
      }

      final candidate = _motionCandidates.putIfAbsent(
        device.id,
        () => _MotionCandidate(
          firstBelow: sample.timestamp,
          lastDistance: distance,
          lastSample: sample.timestamp,
        ),
      );

      if (sample.timestamp.isBefore(candidate.firstBelow)) {
        candidate.firstBelow = sample.timestamp;
      }

      candidate.lastDistance = distance;
      candidate.lastSample = sample.timestamp;

      final elapsed = sample.timestamp.difference(candidate.firstBelow);
      final cooldownUntil = _motionCooldownUntil[device.id];
      if (elapsed >= _motionHoldDuration) {
        final now = DateTime.now();
        if (cooldownUntil == null || now.isAfter(cooldownUntil)) {
          _motionCooldownUntil[device.id] =
              now.add(_motionCooldownDuration);
          await _recordMotionEvent(
            device: device,
            distanceCm: distance,
            thresholdCm: threshold,
            occurredAt: sample.timestamp,
          );
        }
        _motionCandidates.remove(device.id);
      }
    } catch (e, st) {
      debugPrint('Motion processing error for ${device.id}: $e\n$st');
    }
  }

  Future<_MotionSample?> _latestMotionSample(String deviceId) async {
    final signals = await _getLiveSignals(deviceId);
    if (signals.isEmpty) return null;

    RemoteLiveSignal? latest;
    for (final signal in signals) {
      if (latest == null || signal.updatedAt.isAfter(latest!.updatedAt)) {
        latest = signal;
      }
    }
    if (latest == null) return null;

    final extra = latest!.extra;
    final dynamic direct = extra['ultra_cm'] ?? extra['distance_cm'];
    double? cm;
    if (direct is num) cm = direct.toDouble();

    final dynamic ultrasonic = extra['ultrasonic'];
    if (cm == null && ultrasonic is Map) {
      final raw = ultrasonic['cm'];
      if (raw is num) cm = raw.toDouble();
    }

    cm ??= latest!.valueNumeric;
    if (cm == null) return null;

    final dynamic ultraOkRaw =
        extra['ultra_ok'] ?? extra['ultrasonic_ok'];
    bool? ultraOk;
    if (ultraOkRaw is bool) ultraOk = ultraOkRaw;
    if (ultraOkRaw is num) ultraOk = ultraOkRaw != 0;
    if (ultraOk == null && ultrasonic is Map) {
      final rawOk = ultrasonic['ok'];
      if (rawOk is bool) ultraOk = rawOk;
      if (rawOk is num) ultraOk = rawOk != 0;
    }

    return _MotionSample(
      distanceCm: cm,
      timestamp: latest!.updatedAt,
      ultraOk: ultraOk,
    );
  }
  bool _ensureAuthenticated() {
    if (_isAuthenticated) return true;
    debugPrint(
      'SecurityMonitorService: no authenticated user, deteniendo monitoreo.',
    );
    stop();
    return false;
  }

  Future<void> _syncEventToSupabase(SecurityEvent event) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client.from('security_events').insert({
        'user_id': userId,
        'device_id': event.deviceId,
        'device_name': event.deviceName,
        'label': event.label,
        'description': event.description,
        'image_url': event.remoteImageUrl ?? '',
        'captured_at': event.createdAt.toIso8601String(),
        'family_member_id': event.familyMemberId,
        'family_member_name': event.familyMemberName,
        'family_schedule_matched': event.familyScheduleMatched,
      });
    } catch (e) {
      debugPrint('Supabase sync error: $e');
    }
  }

  Future<void> _clearPending(String deviceId) async {
    final pending = _pendingDetections.remove(deviceId);
    final tempPath = pending?.tempImagePath;
    if (tempPath == null) return;
    try {
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Temp cleanup error for $deviceId: $e');
    }
  }

  Future<_SnapshotResult?> _downloadCameraSnapshot(String deviceId) async {
    final cachedRaw = _deviceSnapshotUrls[deviceId];
    final cachedUrl = await _resolveSnapshotUrl(cachedRaw);
    final directResult = await _tryDownloadSnapshot(deviceId, cachedUrl);
    if (directResult != null) {
      return directResult;
    }

    try {
      final signals = await _getLiveSignals(deviceId);
      for (final signal in signals) {
        final candidates = _candidateSnapshotUrls(signal);
        for (final candidate in candidates) {
          final resolved = await _resolveSnapshotUrl(candidate);
          final result = await _tryDownloadSnapshot(deviceId, resolved);
          if (result != null) {
            _deviceSnapshotUrls[deviceId] = candidate;
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('Snapshot download error for $deviceId: $e');
    }
    return null;
  }

  bool _shouldSkipUrl(String url) {
    final lastFailure = _snapshotCooldown[url];
    if (lastFailure == null) return false;
    if (DateTime.now().difference(lastFailure) >= _snapshotRetryDelay) {
      _snapshotCooldown.remove(url);
      return false;
    }
    return true;
  }

  List<String> _candidateSnapshotUrls(RemoteLiveSignal signal) {
    final urls = <String>{};
    void addCandidate(dynamic raw) {
      if (raw is! String) return;
      final normalized = _normalizeMediaUrl(raw);
      if (normalized != null &&
          normalized.isNotEmpty &&
          !_isLikelyLocalUrl(normalized)) {
        urls.add(normalized);
      }
    }

    addCandidate(signal.extra['device_snapshot']);
    addCandidate(signal.extra['snapshot_url']);
    addCandidate(signal.extra['snapshot_signed']);
    addCandidate(signal.snapshotPath);
    addCandidate(signal.extra['snapshot']);

    return urls.toList(growable: false);
  }

  Future<String?> _storeTempEvidence(Uint8List bytes, String deviceId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        p.join(
          tempDir.path,
          'pending_${deviceId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('Temp evidence store error: $e');
    }
    return null;
  }

  String _formatScheduleWindow(FamilyMember member) {
    if (member.schedules.isEmpty) return '--';
    final entries = member.schedules
        .where((s) => s.start.isNotEmpty && s.end.isNotEmpty)
        .map((s) => '${s.start} - ${s.end}')
        .toList(growable: false);
    if (entries.isEmpty) return '--';
    return entries.join(', ');
  }

  Future<String> _storeImage(Uint8List bytes, String deviceId) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'security_captures'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final file = File(
      p.join(
        folder.path,
        '${deviceId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<List<DeviceRecord>> _getAvailableDevices() async {
    final now = DateTime.now();
    final shouldRefresh =
        _cachedDevices.isEmpty ||
        now.difference(_lastDeviceRefresh) >= _deviceRefreshInterval;
    if (!shouldRefresh) {
      return _cachedDevices;
    }
    try {
      _cachedDevices = await _deviceRepository.listDevices();
      _lastDeviceRefresh = now;
    } catch (e, st) {
      debugPrint('Device fetch error: $e\n$st');
      if (_cachedDevices.isEmpty) {
        return const <DeviceRecord>[];
      }
    }
    return _cachedDevices;
  }

  String? _normalizeMediaUrl(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = Environment.supabaseUrl.trim();
    if (base.isEmpty) return null;
    final normalizedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    if (trimmed.startsWith('/')) {
      return '$normalizedBase$trimmed';
    }
    return '$normalizedBase/$trimmed';
  }

  bool _isLikelyLocalUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'http') return false;
    final host = uri.host;
    if (host.isEmpty) return false;
    if (host == 'localhost' || host == '127.0.0.1') return true;
    if (host.endsWith('.local')) return true;
    final segments = host.split('.');
    if (segments.length == 4 &&
        segments.every((s) => int.tryParse(s) != null)) {
      final octets = segments.map((s) => int.parse(s)).toList(growable: false);
      final first = octets[0];
      final second = octets[1];
      if (first == 10) return true;
      if (first == 192 && second == 168) return true;
      if (first == 172 && second >= 16 && second <= 31) return true;
      if (first == 169 && second == 254) return true;
    }
    return false;
  }

  Future<String?> _resolveSnapshotUrl(String? raw) async {
    final normalized = _normalizeMediaUrl(raw);
    if (normalized == null) return null;
    if (normalized.startsWith('http://')) return normalized;

    final uri = Uri.tryParse(normalized);
    if (uri == null) return normalized;
    if (uri.pathSegments.contains('sign')) return normalized;
    if (uri.pathSegments.contains('public')) return normalized;
    if (!_isSupabaseHost(uri)) return normalized;

    return await _signedUrlFor(uri, normalized);
  }

  bool _isSupabaseHost(Uri uri) {
    final base = Environment.supabaseUrl.trim();
    if (base.isEmpty) return false;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || baseUri.host.isEmpty) return false;
    return uri.host == baseUri.host;
  }

  Future<String?> _signedUrlFor(Uri uri, String fallback) async {
    final segments = uri.pathSegments;
    final objectIndex = segments.indexOf('object');
    if (objectIndex < 0) return fallback;
    if (objectIndex + 1 >= segments.length) return fallback;

    final bucket = segments[objectIndex + 1];
    final objectPathSegments = segments.skip(objectIndex + 2);
    if (objectPathSegments.isEmpty) return fallback;

    final objectPath = objectPathSegments.join('/');
    final cacheKey = '$bucket/$objectPath';
    final cache = _signedUrlCache[cacheKey];
    final now = DateTime.now();
    if (cache != null && now.isBefore(cache.expiresAt)) {
      return cache.url;
    }

    const signedTtlSeconds = 300;
    try {
      final signed = await Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(objectPath, signedTtlSeconds);
      final cacheBuster = now.millisecondsSinceEpoch;
      final effective = signed.contains('?')
          ? '$signed&cb=$cacheBuster'
          : '$signed?cb=$cacheBuster';
      final expires = now.add(const Duration(seconds: signedTtlSeconds - 20));
      _signedUrlCache[cacheKey] = _SignedUrlCache(
        url: effective,
        expiresAt: expires,
      );
      return effective;
    } catch (e, st) {
      debugPrint('Signed URL error for $bucket/$objectPath: $e\n$st');
      if (cache != null) {
        // Reutiliza la URL anterior aunque esté cerca del vencimiento.
        return cache.url;
      }
      return null;
    }
  }

  Future<_SnapshotResult?> _tryDownloadSnapshot(
    String deviceId,
    String? normalizedUrl,
  ) async {
    if (normalizedUrl == null || normalizedUrl.isEmpty) return null;
    if (_shouldSkipUrl(normalizedUrl)) return null;
    try {
      final uri = Uri.parse(normalizedUrl);
      final timeout = uri.scheme == 'http'
          ? const Duration(seconds: 4)
          : const Duration(seconds: 10);
      final response = await _httpClient.get(uri).timeout(timeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _pendingDetections[deviceId]?.snapshotUrl = normalizedUrl;
        _snapshotCooldown.remove(normalizedUrl);
        return _SnapshotResult(response.bodyBytes, normalizedUrl);
      }
    } catch (e) {
      debugPrint('Direct snapshot fetch error for $deviceId: $e');
      _snapshotCooldown[normalizedUrl] = DateTime.now();
    }
    return null;
  }

  Future<List<RemoteLiveSignal>> _getLiveSignals(String deviceId) async {
    final now = DateTime.now();
    final cache = _signalCache[deviceId];
    if (cache != null && now.difference(cache.timestamp) < _signalCacheTtl) {
      return cache.signals;
    }
    try {
      final signals = await _remoteService.fetchLiveSignals(deviceId);
      _signalCache[deviceId] = _SignalCache(signals: signals, timestamp: now);
      return signals;
    } catch (e, st) {
      debugPrint('Live signals fetch error for $deviceId: $e\n$st');
      _signalCache[deviceId] = _SignalCache(
        signals: const <RemoteLiveSignal>[],
        timestamp: now,
      );
      return const <RemoteLiveSignal>[];
    }
  }

  DeviceRecord? _deviceRecord(String deviceId) {
    final lower = deviceId.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (final record in _cachedDevices) {
      if (record.id.trim().toLowerCase() == lower) {
        return record;
      }
    }
    return null;
  }
}

class _SignedUrlCache {
  _SignedUrlCache({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}

class _PendingDetection {
  _PendingDetection({
    required this.firstResult,
    required this.firstSeen,
    required this.lastSeen,
    this.tempImagePath,
    this.snapshotUrl,
    this.stage = _DetectionStage.green,
  });

  final DetectionResult firstResult;
  final DateTime firstSeen;
  DateTime lastSeen;
  _DetectionStage stage;
  String? snapshotUrl;
  String? tempImagePath;
}

class _SnapshotResult {
  const _SnapshotResult(this.bytes, this.url);

  final Uint8List bytes;
  final String? url;
}

enum _DetectionStage { green, yellow, red }

class _SignalCache {
  _SignalCache({required this.signals, required this.timestamp});

  final List<RemoteLiveSignal> signals;
  final DateTime timestamp;
}

class _MotionCandidate {
  _MotionCandidate({
    required this.firstBelow,
    required this.lastDistance,
    required this.lastSample,
  });

  DateTime firstBelow;
  double lastDistance;
  DateTime lastSample;
}

class _MotionSample {
  const _MotionSample({
    required this.distanceCm,
    required this.timestamp,
    required this.ultraOk,
  });

  final double distanceCm;
  final DateTime timestamp;
  final bool? ultraOk;
}
