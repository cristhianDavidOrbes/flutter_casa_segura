import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class SecurityMonitorService {
  SecurityMonitorService._();

  static final SecurityMonitorService instance = SecurityMonitorService._();

  final DeviceRepository _deviceRepository = DeviceRepository.instance;
  final RemoteDeviceService _remoteService = RemoteDeviceService();
  final DetectionEngine _detectionEngine = DetectionEngine.instance;
  final GeminiVisionService _visionService = GeminiVisionService.instance;
  final SupabaseClient _client = Supabase.instance.client;

  Timer? _cameraTimer;
  Timer? _sensorTimer;

  bool _running = false;
  bool _cameraPolling = false;
  bool _sensorPolling = false;

  final Map<String, _PendingDetection> _pendingDetections = {};
  bool get _isAuthenticated => _client.auth.currentUser != null;

  Future<void> start() async {
    if (_running) return;
    if (!_ensureAuthenticated()) {
      return;
    }
    _running = true;

    unawaited(_pollCameras());
    unawaited(_pollSensors());

    _cameraTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollCameras(),
    );
    _sensorTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollSensors(),
    );
  }

  void stop() {
    _cameraTimer?.cancel();
    _sensorTimer?.cancel();
    _running = false;
    _cameraPolling = false;
    _sensorPolling = false;
    _pendingDetections.clear();
  }

  Future<void> _pollCameras() async {
    if (!_running || _cameraPolling) return;
    if (!_ensureAuthenticated()) return;
    _cameraPolling = true;
    try {
      final devices = await _deviceRepository.listDevices();
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
    final imageBytes = await _downloadCameraSnapshot(deviceId);
    if (imageBytes == null) return;

    final detection = await _detectionEngine.analyzeImage(imageBytes);
    if (detection == null) {
      await _clearPending(deviceId);
      return;
    }

    var pending = _pendingDetections[deviceId];
    if (pending == null || pending.confirmed) {
      final tempPath = await _storeTempEvidence(imageBytes, deviceId);
      pending = _PendingDetection(
        firstResult: detection,
        tempImagePath: tempPath,
      );
      _pendingDetections[deviceId] = pending;
    }

    pending.attempts += 1;
    if (pending.attempts == 1) {
      unawaited(_confirmDetection(deviceId, deviceName, pending));
    }
  }

  Future<void> _confirmDetection(
    String deviceId,
    String deviceName,
    _PendingDetection pending,
  ) async {
    for (int i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final bytes = await _downloadCameraSnapshot(deviceId);
      if (bytes == null) continue;

      final detection = await _detectionEngine.analyzeImage(bytes);
      if (detection == null) continue;
      if (detection.label != pending.firstResult.label) continue;
      if (!DetectionEngine.isSimilar(pending.firstResult, detection)) continue;

      final path = await _storeImage(bytes, deviceId);

      FamilyMatch? familyMatch;
      if (detection.label.toLowerCase().contains('rostro')) {
        try {
          familyMatch = await FamilyPresenceService.instance.identify(bytes);
        } catch (e) {
          debugPrint('Family match error: $e');
        }
      }

      final scheduleWindow = familyMatch != null
          ? _formatScheduleWindow(familyMatch.member)
          : null;

      final descriptionFromGemini =
          await _visionService.describeImage(
            bytes,
            context:
                'Describe detalladamente lo que se observa en esta captura del dispositivo "$deviceName". '
                'Enfocate en caracteristicas relevantes para seguridad.',
          ) ??
          'El dispositivo "$deviceName" detecto ${detection.label.toLowerCase()} '
              '(${(detection.confidence * 100).toStringAsFixed(1)}% confianza).';

      final scheduleMessage = familyMatch != null && scheduleWindow != null
          ? (familyMatch.withinSchedule
              ? 'security.event.family.within'
                  .trParams({'window': scheduleWindow})
              : 'security.event.family.outside'
                  .trParams({'window': scheduleWindow}))
          : null;

      final description = scheduleMessage == null
          ? descriptionFromGemini
          : '${descriptionFromGemini.trim()}\n\n$scheduleMessage';

      final event = SecurityEvent(
        deviceId: deviceId,
        deviceName: deviceName,
        label: familyMatch != null
            ? 'security.event.familyLabel'
                .trParams({'name': familyMatch.member.name})
            : detection.label,
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
          final deviceRow =
              await AppDb.instance.getDeviceByDeviceId(deviceId);
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
      pending.confirmed = true;
      await _clearPending(deviceId);
      return;
    }

    await _clearPending(deviceId);
  }

  Future<void> _pollSensors() async {
    if (!_running || _sensorPolling) return;
    if (!_ensureAuthenticated()) return;
    _sensorPolling = true;
    try {
      final devices = await _deviceRepository.listDevices();
      for (final device in devices) {
        if (device.type.toLowerCase().contains('cam')) continue;
        // TODO: integrar lectura real de sensores.
      }
    } catch (e, st) {
      debugPrint('Sensor poll error: $e\n$st');
    } finally {
      _sensorPolling = false;
    }
  }

  bool _ensureAuthenticated() {
    if (_isAuthenticated) return true;
    debugPrint('SecurityMonitorService: no authenticated user, deteniendo monitoreo.');
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

  Future<Uint8List?> _downloadCameraSnapshot(String deviceId) async {
    try {
      final signals = await _remoteService.fetchLiveSignals(deviceId);
      for (final signal in signals) {
        final snapshot = signal.snapshotPath ?? signal.extra['snapshot'];
        final stream = signal.extra['stream'];
        String? url;
        if (snapshot is String && snapshot.trim().isNotEmpty) {
          url = snapshot.trim();
        } else if (stream is String && stream.trim().isNotEmpty) {
          url = stream.trim();
        }
        if (url == null) continue;
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          _pendingDetections[deviceId]?.snapshotUrl = url;
          return response.bodyBytes;
        }
      }
    } catch (e) {
      debugPrint('Snapshot download error for $deviceId: $e');
    }
    return null;
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
}

class _PendingDetection {
  _PendingDetection({required this.firstResult, this.tempImagePath});

  final DetectionResult firstResult;
  bool confirmed = false;
  int attempts = 0;
  String? snapshotUrl;
  String? tempImagePath;
}


