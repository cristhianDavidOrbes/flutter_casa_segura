import 'dart:async';

import 'dart:convert';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_seguridad_en_casa/repositories/device_repository.dart';
import 'package:flutter_seguridad_en_casa/services/remote_device_service.dart';
import 'package:flutter_seguridad_en_casa/models/device_remote_flags.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/mjpeg_stream_view.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';

class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({
    super.key,

    required this.deviceId,

    required this.name,

    required this.type,

    this.ip,

    this.lastSeenAt,
  });

  final String deviceId; // p.ej. casa-esp-xxxx (sin .local)

  final String name;

  final String type; // "esp", "esp32cam", "servo", etc.

  final String? ip;

  final DateTime? lastSeenAt;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  static const String _defaultSnapshotBucket = 'camera_frames';

  final RemoteDeviceService _remoteService = RemoteDeviceService();
  final DeviceRepository _repository = DeviceRepository.instance;

  StreamSubscription<RemoteDevicePresence?>? _presenceSub;
  StreamSubscription<List<RemoteLiveSignal>>? _signalsSub;

  Timer? _remoteSnapshotTimer;

  String? _remoteSnapshotBucket;
  String? _remoteSnapshotObjectKey;
  String? _remoteSnapshotUrl;
  bool _fetchingRemoteSnapshot = false;
  int _remoteSnapshotMisses = 0;
  static const int _remoteSnapshotMissLimit = 5;
  final List<String> _remoteSnapshotHistory = <String>[];
  DateTime? _lastSeenAt;

  String? _currentIp;
  String? _currentHost;

  DeviceRemoteFlags? _remoteFlags;
  StreamSubscription<DeviceRemoteFlags?>? _remoteFlagsSub;
  bool _awaitingRemotePing = false;

  bool _pinging = false;

  bool get _online {
    final last = _lastSeenAt;

    if (last == null) return false;

    return DateTime.now().difference(last) <= const Duration(minutes: 2);
  }

  String get _displayHost {
    final ip = _currentIp ?? widget.ip;
    if (ip != null && ip.isNotEmpty) return ip;
    final host = _currentHost;
    if (host != null && host.isNotEmpty) return host;
    return '${widget.deviceId}.local';
  }

  List<Uri> _tries(String path) {
    final seen = <String>{};
    final hosts = <String?>[
      (_currentIp ?? widget.ip)?.trim(),
      _currentHost?.trim(),
      '${widget.deviceId}.local',
    ];
    final uris = <Uri>[];
    for (final candidate in hosts) {
      if (candidate == null) continue;
      final value = candidate.trim();
      if (value.isEmpty) continue;
      if (!seen.add(value.toLowerCase())) continue;
      final withScheme =
          value.startsWith('http://') || value.startsWith('https://')
          ? value
          : 'http://$value';
      uris.add(Uri.parse('$withScheme$path'));
    }
    return uris;
  }

  String? _addressFromUri(Uri uri) {
    final host = uri.host.trim();

    return host.isEmpty ? null : host;
  }

  bool _isNumericIp(String value) {
    final pattern = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');

    return pattern.hasMatch(value);
  }

  void _recordPresence(DateTime when, {String? ip, String? host}) {
    final trimmed = ip?.trim();
    final trimmedHost = host?.trim();

    if (mounted) {
      setState(() {
        _lastSeenAt = when;

        if (trimmed != null && trimmed.isNotEmpty) {
          _currentIp = trimmed;
        }
        if (trimmedHost != null && trimmedHost.isNotEmpty) {
          _currentHost = trimmedHost;
        }
      });
    } else {
      _lastSeenAt = when;

      if (trimmed != null && trimmed.isNotEmpty) {
        _currentIp = trimmed;
      }
      if (trimmedHost != null && trimmedHost.isNotEmpty) {
        _currentHost = trimmedHost;
      }
    }

    final sanitizedIp =
        (trimmed != null && trimmed.isNotEmpty && _isNumericIp(trimmed))
        ? trimmed
        : null;

    unawaited(
      DeviceRepository.instance
          .updatePresence(widget.deviceId, ip: sanitizedIp, seenAt: when)
          .catchError((_) {}),
    );
  }

  String? _extractAddressFromMap(Map<String, dynamic> json) {
    String? pick(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();

        return trimmed.isNotEmpty ? trimmed : null;
      }

      if (value is num) return value.toString();

      return null;
    }

    String? address = pick(json['ip']) ?? pick(json['host']);

    final servo = json['servo'];

    if (servo is Map) {
      address ??= pick(servo['ip']);

      address ??= pick(servo['host']);
    }

    final network = json['network'];

    if (network is Map) {
      address ??= pick(network['ip']);

      address ??= pick(network['host']);
    }

    return address;
  }

  Future<void> _doPing() async {
    if (_pinging) return;

    if (mounted) {
      setState(() => _pinging = true);
    } else {
      _pinging = true;
    }

    Uri? successUri;

    String message = 'Sin respuesta';

    String? lastError;

    final paths = <String>['/ping', '/info', '/'];

    try {
      for (final path in paths) {
        bool hit = false;

        for (final uri in _tries(path)) {
          try {
            final res = await http.get(uri).timeout(const Duration(seconds: 2));

            if (res.statusCode == 200) {
              successUri = uri;

              message = path == '/ping'
                  ? (res.body.isNotEmpty ? res.body : 'ok')
                  : 'ok';

              hit = true;

              break;
            }

            lastError = 'HTTP ${res.statusCode}';
          } on TimeoutException {
            lastError = 'timeout';
          } catch (e) {
            lastError = e.toString();
          }
        }

        if (hit) break;
      }
    } finally {
      if (mounted) {
        setState(() => _pinging = false);
      } else {
        _pinging = false;
      }
    }

    if (!mounted) return;

    if (successUri != null) {
      if (_awaitingRemotePing) {
        setState(() => _awaitingRemotePing = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ping ${successUri.host}: $message'),
          duration: const Duration(seconds: 2),
        ),
      );

      _recordPresence(DateTime.now(), ip: _addressFromUri(successUri));
    } else {
      final lastAddress = _currentIp ?? widget.ip;
      final lastErrorLower = lastError?.toLowerCase() ?? '';
      if (lastErrorLower.contains('failed host lookup')) {
        await _requestRemotePingFallback();
        return;
      }

      final suffix = lastError != null ? ' ($lastError)' : '';
      var hint = '';
      if (_isPrivateIp(lastAddress) && lastErrorLower.contains('timed out')) {
        hint = '\nRecuerda que el ping directo solo funciona en la misma red.';
      }
      if (_remoteLastUpdate != null) {
        final ago = DateTime.now().difference(_remoteLastUpdate!);
        hint += '\nUltimo latido via Supabase hace ${_formatElapsed(ago)}.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sin respuesta$suffix$hint'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _requestRemotePingFallback() async {
    if (!mounted) return;
    if (_awaitingRemotePing) {
      final flags = _remoteFlags;
      String tail = '';
      if (flags?.pingAckAt != null) {
        final ago = DateTime.now().difference(flags!.pingAckAt!);
        tail = ' Ultimo ping remoto hace ${_formatElapsed(ago)}.';
      } else if (_remoteLastUpdate != null) {
        final ago = DateTime.now().difference(_remoteLastUpdate!);
        tail = ' Ultimo latido via Supabase hace ${_formatElapsed(ago)}.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ping remoto en espera.$tail'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      await _remoteService.requestRemotePing(widget.deviceId);
      if (!mounted) return;
      setState(() => _awaitingRemotePing = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ping remoto solicitado via Supabase. Se confirmara cuando el equipo sincronice.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo solicitar ping remoto: $e')),
      );
    }
  }

  Future<void> _forgetAp() async {
    try {
      await _repository.forgetAndReset(
        deviceId: widget.deviceId,
        ip: _currentIp ?? widget.ip,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dispositivo reiniciado por IP local. Volvera a modo AP en unos segundos.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar el reinicio local: $e')),
      );
    }
  }

  // ===== Datos en tiempo real =====

  // Ponemos '/sensors' primero para priorizar el JSON con datos reales.

  static const List<String> _candidateDataPaths = <String>[
    '/sensors',

    '/sensor',

    '/status',

    '/data',

    '/metrics',

    '/info',
  ];

  Map<String, dynamic>? _liveData;
  Map<String, dynamic>? _remoteLiveData;
  DateTime? _remoteLastUpdate;
  String? _remoteSourceLabel;
  bool _fetchingRemoteState = false;

  String? _endpointUsed;

  DateTime? _lastUpdate;

  String? _lastError;

  bool _autoRefresh = true;

  final Duration _period = const Duration(seconds: 2);

  Timer? _pollTimer;

  // ====== Estado/Control de SERVO (nuevo) ======

  bool? _servoOn; // null = desconocido; true/false = estado conocido

  bool _servoBusy = false;

  // ====== Deteccion de camara (nuevo sin quitar nada) ======

  bool _hasStream = false; // si detectamos /photo o /stream, mostramos video
  bool _cameraEnabled = false; // habilita UI de camara segun tipo o senales

  bool get _seVeControlServo {
    // Si el tipo lo dice o si el JSON trae "servo"

    final t = widget.type.toLowerCase();

    final byType = t.contains('servo');

    final data = _effectiveLiveData;
    final byData = data != null && data['servo'] != null;

    return byType || byData;
  }

  Map<String, dynamic>? get _effectiveLiveData => _liveData ?? _remoteLiveData;

  DateTime? get _effectiveLastUpdate =>
      _liveData != null ? _lastUpdate : _remoteLastUpdate;

  bool get _showingRemoteData => _liveData == null && _remoteLiveData != null;

  bool get _showCameraCard {
    if (!_cameraEnabled) return false;
    if (_hasStream) return true;
    if (_remoteSnapshotUrl != null) return true;
    if (_fetchingRemoteSnapshot) return true;
    return _remoteSnapshotBucket != null &&
        _remoteSnapshotObjectKey != null &&
        _remoteSnapshotObjectKey!.isNotEmpty;
  }

  bool _stringLooksLikeCamera(String? value) {
    if (value == null) return false;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized.contains('camera') ||
        normalized.contains('camara') ||
        normalized.contains('esp32cam') ||
        normalized.contains('videocam')) {
      return true;
    }
    if (normalized.startsWith('cam')) return true;
    if (normalized.contains(' cam') ||
        normalized.contains('cam ') ||
        normalized.contains('cam-') ||
        normalized.contains('cam_') ||
        normalized.endsWith('cam')) {
      return true;
    }
    if (normalized.contains('video') || normalized.contains('stream')) {
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> _getJsonFrom(String path) async {
    for (final uri in _tries(path)) {
      try {
        final res = await http
            .get(uri)
            .timeout(const Duration(seconds: 6)); // +timeout

        if (res.statusCode == 200) {
          final m = _decodeJsonMap(res.body);

          if (m != null) {
            _recordPresence(DateTime.now(), ip: _addressFromUri(uri));

            return m;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> _refreshServoState() async {
    // intenta /servo, y si no, /sensors

    Map<String, dynamic>? m = await _getJsonFrom('/servo');

    m ??= await _getJsonFrom('/sensors');

    bool? on;

    String? address;

    if (m != null) {
      // {on:true/false, pos:x} o {"servo":{"on":...}}

      if (m.containsKey('on')) {
        final v = m['on'];

        on = v is bool ? v : (v.toString().toLowerCase() == 'true');
      } else if (m['servo'] is Map) {
        final sv = m['servo'];

        final v = sv['on'];

        on = v is bool ? v : (v.toString().toLowerCase() == 'true');
      }

      address = _extractAddressFromMap(m);
    }

    if (!mounted) return;

    setState(() => _servoOn = on);

    if (address != null && address.isNotEmpty) {
      _recordPresence(DateTime.now(), ip: address);
    }
  }

  Future<void> _setServoOn(bool on) async {
    if (_servoBusy) return;

    setState(() => _servoBusy = true);

    bool ok = false;

    Uri? successUri;

    final body = jsonEncode({'on': on});

    for (final uri in _tries('/servo')) {
      try {
        final res = await http
            .post(
              uri,

              headers: {'Content-Type': 'application/json'},

              body: body,
            )
            .timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          ok = true;

          successUri = uri;

          break;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _servoBusy = false;

      if (ok) _servoOn = on;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar el estado del servo')),
      );
    } else {
      _recordPresence(
        DateTime.now(),

        ip: successUri != null ? _addressFromUri(successUri) : null,
      );
    }
  }

  @override
  void initState() {
    super.initState();

    _lastSeenAt = widget.lastSeenAt;

    _currentIp = widget.ip;

    _cameraEnabled =
        _stringLooksLikeCamera(widget.type) ||
        _stringLooksLikeCamera(widget.name);

    _presenceSub = _remoteService.watchDevicePresence(widget.deviceId).listen((
      presence,
    ) {
      if (!mounted || presence == null) return;
      final seen = presence.lastSeenAt;
      final ip = presence.ip?.trim();
      if (seen == null && (ip == null || ip.isEmpty)) return;
      _recordPresence(seen ?? DateTime.now(), ip: ip);
    });

    _signalsSub = _remoteService
        .watchLiveSignals(widget.deviceId)
        .listen(_onRemoteSignals);

    _loadRemoteSignalsOnce();

    _subscribeRemoteFlags();

    _refreshRemoteState(silent: true);

    if (_cameraEnabled) {
      _ensureSnapshotDefaults();
    }

    _startAuto();

    // Intento inicial de leer estado del servo (si aplica)

    _refreshServoState();

    // Deteccion de camara sin bloquear UI

    if (_cameraEnabled) {
      _probeStream();
    }
  }

  @override
  void dispose() {
    _stopAuto();

    _presenceSub?.cancel();
    _signalsSub?.cancel();
    _remoteFlagsSub?.cancel();
    _stopRemoteSnapshotTimer();

    super.dispose();
  }

  void _startAuto() {
    _pollOnce();

    _pollTimer?.cancel();

    if (_autoRefresh) {
      _pollTimer = Timer.periodic(_period, (_) => _pollOnce());
    }
  }

  void _stopAuto() {
    _pollTimer?.cancel();

    _pollTimer = null;
  }

  void _ensureSnapshotDefaults() {
    if (!_cameraEnabled) return;
    _remoteSnapshotBucket ??= _defaultSnapshotBucket;
    if ((_remoteSnapshotObjectKey == null ||
            _remoteSnapshotObjectKey!.isEmpty) &&
        widget.deviceId.isNotEmpty) {
      _remoteSnapshotObjectKey = '${widget.deviceId}/latest.jpg';
    }
    if (_remoteSnapshotTimer == null &&
        !_fetchingRemoteSnapshot &&
        _remoteSnapshotBucket != null &&
        _remoteSnapshotObjectKey != null &&
        _remoteSnapshotObjectKey!.isNotEmpty) {
      _startRemoteSnapshotTimer();
      _fetchSignedSnapshot();
    }
  }

  void _subscribeRemoteFlags() {
    _remoteService.ensureRemoteFlags(widget.deviceId).catchError((_) {});
    _remoteFlagsSub = _remoteService
        .watchRemoteFlags(widget.deviceId)
        .listen(_handleRemoteFlags);
  }

  void _loadRemoteSignalsOnce({int attempt = 0}) {
    _remoteService
        .fetchLiveSignals(widget.deviceId)
        .then((signals) {
          if (!mounted) return;
          _onRemoteSignals(signals);
        })
        .catchError((error, stackTrace) {
          debugPrint(
            'No se pudieron obtener las seÃÂÃÂÃÂÃÂ±ales remotas (intento ${attempt + 1}): $error',
          );
          if (!mounted) return;
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) {
              _loadRemoteSignalsOnce(attempt: attempt + 1);
            }
          });
        });
  }

  void _handleRemoteFlags(DeviceRemoteFlags? flags) {
    if (!mounted) return;
    final previous = _remoteFlags;
    setState(() {
      _remoteFlags = flags;
    });
    if (flags == null) return;

    if (_awaitingRemotePing &&
        flags.pingAcked &&
        !(previous?.pingAcked ?? false)) {
      _awaitingRemotePing = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ping remoto confirmado por Supabase.')),
      );
    }
  }

  void _onRemoteSignals(List<RemoteLiveSignal> signals) {
    String? snapshotPath;
    bool streamHint = false;
    String? ipHint;
    String? hostHint;
    DateTime? freshest;

    final remoteData = <String, dynamic>{};

    for (final signal in signals) {
      final snapshot = signal.snapshotPath;
      if (snapshot != null && snapshot.isNotEmpty && snapshotPath == null) {
        snapshotPath = snapshot;
      }
      final streamUrl = signal.extra['stream'];
      if (!streamHint && streamUrl is String && streamUrl.trim().isNotEmpty) {
        streamHint = true;
      }

      if (ipHint == null) {
        final extraIp = signal.extra['ip'];
        if (extraIp is String && extraIp.trim().isNotEmpty) {
          ipHint = extraIp.trim();
        }
      }
      if (hostHint == null) {
        final extraHost = signal.extra['host'] ?? signal.extra['hostname'];
        if (extraHost is String && extraHost.trim().isNotEmpty) {
          hostHint = extraHost.trim();
        }
      }

      final ts = signal.updatedAt;
      if (freshest == null || ts.isAfter(freshest)) {
        freshest = ts;
      }

      _mergeRemoteSignal(remoteData, signal);
    }

    bool enabledNow = false;
    if ((snapshotPath != null || streamHint) && !_cameraEnabled) {
      _cameraEnabled = true;
      enabledNow = true;
    }

    bool streamStateChanged = false;
    if (streamHint && !_hasStream) {
      _hasStream = true;
      streamStateChanged = true;
    }

    if ((enabledNow || streamStateChanged) && mounted) {
      setState(() {});
    }

    if (_cameraEnabled) {
      _ensureSnapshotDefaults();
    }

    if (snapshotPath != null) {
      _updateRemoteSnapshotPath(snapshotPath);
    }

    if (enabledNow) {
      _probeStream();
    }

    if (ipHint != null || hostHint != null) {
      _recordPresence(freshest ?? DateTime.now(), ip: ipHint, host: hostHint);
    }

    if (remoteData.isNotEmpty) {
      _remoteLiveData = _sanitize(remoteData);
      _remoteLastUpdate = freshest;
      _remoteSourceLabel = 'Supabase';
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _updateRemoteSnapshotPath(String path) {
    final parsed = _parseStoragePath(path);
    if (parsed == null) return;
    final changed =
        parsed.bucket != _remoteSnapshotBucket ||
        parsed.object != _remoteSnapshotObjectKey;
    if (changed) {
      _remoteSnapshotBucket = parsed.bucket;
      _remoteSnapshotObjectKey = parsed.object;
      _remoteSnapshotUrl = null;
      _remoteSnapshotMisses = 0;
      _startRemoteSnapshotTimer();
      _fetchSignedSnapshot();
    } else if (_remoteSnapshotUrl == null) {
      _fetchSignedSnapshot();
    }
  }

  ({String bucket, String object})? _parseStoragePath(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        trimmed = uri.path;
      }
    }
    const marker = '/storage/v1/object/';
    final markerIndex = trimmed.indexOf(marker);
    if (markerIndex >= 0) {
      trimmed = trimmed.substring(markerIndex + marker.length);
    } else if (trimmed.startsWith('/')) {
      trimmed = trimmed.substring(1);
    }
    final firstSlash = trimmed.indexOf('/');
    if (firstSlash <= 0 || firstSlash >= trimmed.length - 1) {
      return null;
    }
    final bucket = trimmed.substring(0, firstSlash);
    var object = trimmed.substring(firstSlash + 1);
    while (object.startsWith('/')) {
      object = object.substring(1);
    }
    if (object.isEmpty) return null;
    if (bucket.isEmpty || object.isEmpty) {
      return null;
    }
    return (bucket: bucket, object: object);
  }

  void _startRemoteSnapshotTimer() {
    if (!_cameraEnabled) return;
    _remoteSnapshotTimer?.cancel();
    _remoteSnapshotTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _fetchSignedSnapshot(),
    );
  }

  void _stopRemoteSnapshotTimer() {
    _remoteSnapshotTimer?.cancel();
    _remoteSnapshotTimer = null;
  }

  void _triggerSnapshotRefresh() {
    if (!_cameraEnabled) return;
    if (_remoteSnapshotMisses >= _remoteSnapshotMissLimit) {
      _remoteSnapshotMisses = 0;
      _startRemoteSnapshotTimer();
    }
    _fetchSignedSnapshot();
  }

  Future<void> _fetchSignedSnapshot() async {
    if (!mounted || !_cameraEnabled) return;
    final bucket = _remoteSnapshotBucket;
    final object = _remoteSnapshotObjectKey;
    if (bucket == null || object == null || _fetchingRemoteSnapshot) return;
    _fetchingRemoteSnapshot = true;
    try {
      final signed = await Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(object, 30);
      if (!mounted) return;
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      final busted = signed.contains('?')
          ? '$signed&cb=$cacheBuster'
          : '$signed?cb=$cacheBuster';
      setState(() {
        if (_remoteSnapshotUrl != null && _remoteSnapshotUrl != busted) {
          _remoteSnapshotHistory.add(_remoteSnapshotUrl!);
          while (_remoteSnapshotHistory.length > 3) {
            _remoteSnapshotHistory.removeAt(0);
          }
        }
        _remoteSnapshotUrl = busted;
        _remoteSnapshotMisses = 0;
      });
    } on StorageException catch (error) {
      final code = error.statusCode?.toString();
      if (code == '404') {
        _remoteSnapshotMisses++;
        _remoteSnapshotUrl = null;
        final resolved = await _resolveSnapshotObject(bucket, object);
        if (resolved != null && resolved != object) {
          _remoteSnapshotObjectKey = resolved;
          _remoteSnapshotUrl = null;
          _remoteSnapshotMisses = 0;
          _fetchingRemoteSnapshot = false;
          return _fetchSignedSnapshot();
        }
        debugPrint(
          'Snapshot no encontrado (intento $_remoteSnapshotMisses): $bucket/$object',
        );
        if (_remoteSnapshotMisses >= _remoteSnapshotMissLimit) {
          _stopRemoteSnapshotTimer();
          _remoteSnapshotBucket = null;
          _remoteSnapshotObjectKey = null;
          if (mounted) {
            setState(() {});
          }
          debugPrint(
            'Snapshot remoto deshabilitado tras $_remoteSnapshotMisses intentos fallidos.',
          );
        }
      } else {
        debugPrint('Error creando URL firmada del snapshot: $error');
        if (mounted) {
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) _fetchSignedSnapshot();
          });
        }
      }
    } catch (error) {
      debugPrint('Error creando URL firmada del snapshot: $error');
      if (mounted) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) _fetchSignedSnapshot();
        });
      }
    } finally {
      _fetchingRemoteSnapshot = false;
    }
  }

  Future<String?> _resolveSnapshotObject(
    String bucket,
    String currentObject,
  ) async {
    final segments = currentObject.split('/');
    final targetFile = segments.isNotEmpty ? segments.last : currentObject;
    final initialPrefix = segments.length > 1
        ? segments.sublist(0, segments.length - 1).join('/')
        : '';

    final visited = <String>{};
    final prefixes = <String>{
      initialPrefix,
      widget.deviceId,
      '${widget.deviceId}/${widget.deviceId}',
      '',
    }.where((p) => p.trim().isNotEmpty || p == '').toList();

    for (final prefix in prefixes) {
      final result = await _searchStorageForFile(
        bucket: bucket,
        prefix: prefix,
        fileName: targetFile,
        visited: visited,
      );
      if (result != null) return result;
    }
    return null;
  }

  Future<String?> _searchStorageForFile({
    required String bucket,
    required String prefix,
    required String fileName,
    required Set<String> visited,
    int depth = 0,
  }) async {
    if (depth > 6) return null;
    final normalizedPrefix = prefix.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final cacheKey = '$bucket::$normalizedPrefix::$fileName';
    if (!visited.add(cacheKey)) return null;

    List<dynamic> entries;
    try {
      entries = await Supabase.instance.client.storage
          .from(bucket)
          .list(path: normalizedPrefix.isEmpty ? '' : normalizedPrefix);
    } catch (error) {
      debugPrint('Error listando storage ($normalizedPrefix): $error');
      return null;
    }
    for (final entry in entries) {
      final name = _entryName(entry);
      if (name == null || name.isEmpty) continue;
      final fullPath = normalizedPrefix.isEmpty
          ? name
          : '$normalizedPrefix/$name';
      final isFile = _isFile(entry, name);
      if (isFile && name == fileName) {
        debugPrint('Snapshot encontrado en $fullPath');
        if (fullPath != _remoteSnapshotObjectKey) {
          debugPrint(
            'Snapshot encontrado en $fullPath (antes $_remoteSnapshotObjectKey)',
          );
        }
        return fullPath;
      }
      if (!isFile) {
        final found = await _searchStorageForFile(
          bucket: bucket,
          prefix: fullPath,
          fileName: fileName,
          visited: visited,
          depth: depth + 1,
        );
        if (found != null) return found;
      }
    }
    return null;
  }

  String? _entryName(dynamic entry) {
    if (entry == null) return null;
    if (entry is Map) {
      final value = entry['name'];
      if (value is String) return value;
    }
    if (entry is FileObject) return entry.name;
    if (entry is FileObjectV2) return entry.name;
    try {
      final dynamic dynamicEntry = entry;
      final value = dynamicEntry.name;
      if (value is String) return value;
    } catch (_) {}
    return null;
  }

  bool _isFile(dynamic entry, String name) {
    bool? hasMetadata;
    try {
      final dynamic dynamicEntry = entry;
      hasMetadata = dynamicEntry.metadata != null;
    } catch (_) {
      if (entry is Map && entry.containsKey('metadata')) {
        hasMetadata = entry['metadata'] != null;
      }
    }
    if (hasMetadata == true) return true;
    if (hasMetadata == false) return false;
    // Fallback heuristic: treat as file if it looks like one.
    return name.contains('.');
  }

  Future<void> _pollOnce() async {
    final paths = <String>[
      if (_endpointUsed != null) _endpointUsed!,

      ..._candidateDataPaths.where((p) => p != _endpointUsed),
    ];

    Map<String, dynamic>? data;

    String? hitPath;

    String? lastErr;

    for (final path in paths) {
      for (final uri in _tries(path)) {
        try {
          final res = await http
              .get(uri)
              .timeout(const Duration(seconds: 6)); // +timeout

          if (res.statusCode == 200) {
            final parsed = _decodeJsonMap(res.body);

            if (parsed != null) {
              final sanitized = _sanitize(parsed);

              // si la respuesta es trivial (p. ej. {"ok":true}), intenta siguiente

              if (_isTrivialPayload(sanitized)) {
                lastErr = 'Respuesta trivial en $path';

                continue;
              }

              data = sanitized;

              hitPath = path;

              break;
            }
          } else {
            lastErr = 'HTTP ${res.statusCode}';
          }
        } catch (e) {
          lastErr = e.toString();
        }
      }

      if (data != null) break;
    }

    if (!mounted) return;

    setState(() {
      _liveData = data;

      _endpointUsed = hitPath;

      _lastUpdate = DateTime.now();

      _lastError = data == null ? lastErr ?? 'Sin respuesta' : null;
    });

    if (data == null) {
      _refreshRemoteState(silent: true);
    }

    // Si hay datos y aparece "servo", actualiza el switch si no lo sabemos aun

    if (_seVeControlServo && _servoOn == null) {
      _refreshServoState();
    }
  }

  // --- NUEVO: deteccion de /photo o /stream para mostrar camara aunque type sea "esp"

  Future<void> _probeStream() async {
    if (!_cameraEnabled) return;
    bool ok = false;

    // Probo /photo primero (respuesta finita)

    for (final u in _tries('/photo')) {
      try {
        final res = await http.get(u).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200 &&
            res.headers['content-type']?.contains('image/jpeg') == true) {
          ok = true;

          break;
        }
      } catch (_) {}
    }

    if (!ok) {
      // Si /photo no respondio, intento abrir cabecera de /stream con HttpClient y lo cierro

      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4);

        for (final base in _tries('/stream')) {
          try {
            final req = await client.getUrl(base);

            req.headers.set(
              HttpHeaders.acceptHeader,

              'multipart/x-mixed-replace',
            );

            final res = await req.close().timeout(const Duration(seconds: 4));

            if (res.statusCode == 200 &&
                (res.headers.contentType?.mimeType ?? '').contains(
                  'multipart',
                )) {
              ok = true;

              break;
            }
          } catch (_) {}
        }

        client.close(force: true);
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() => _hasStream = ok);
  }

  Map<String, dynamic>? _decodeJsonMap(String source) {
    if (source.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(source);

      if (decoded is Map<String, dynamic>) return decoded;

      if (decoded is Map) {
        final out = <String, dynamic>{};

        decoded.forEach((k, v) => out[k.toString()] = v);

        return out;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _refreshRemoteState({bool silent = false}) async {
    if (_fetchingRemoteState) return;
    _fetchingRemoteState = true;
    try {
      final remote = await _remoteService.fetchCurrentState(widget.deviceId);
      if (!mounted) return;
      if (remote.isNotEmpty) {
        DateTime? remoteUpdatedAt;
        final rawTs = remote['last_updated_at'];
        if (rawTs is String) {
          remoteUpdatedAt = DateTime.tryParse(rawTs);
        } else if (rawTs is DateTime) {
          remoteUpdatedAt = rawTs;
        }
        setState(() {
          _remoteLiveData = _sanitize(remote);
          _remoteLastUpdate = remoteUpdatedAt ?? DateTime.now();
          _remoteSourceLabel = 'Supabase';
        });
      } else if (!silent) {
        debugPrint('Estado remoto vacio para ${widget.deviceId}');
      }
    } catch (e) {
      if (!silent) {
        debugPrint('No se pudo obtener estado remoto: $e');
      }
    } finally {
      _fetchingRemoteState = false;
    }
  }

  void _mergeRemoteSignal(Map<String, dynamic> out, RemoteLiveSignal signal) {
    final rawName = signal.name.trim();
    final name = rawName.isEmpty ? signal.id : rawName;

    final entry = <String, dynamic>{
      'kind': signal.kind,
      if (signal.valueNumeric != null) 'value_numeric': signal.valueNumeric,
      if (signal.valueText != null && signal.valueText!.isNotEmpty)
        'value_text': signal.valueText,
      if (signal.extra.isNotEmpty) 'extra': signal.extra,
    };

    out[name] = entry;

    if (signal.extra.isNotEmpty) {
      for (final MapEntry<dynamic, dynamic> item in signal.extra.entries) {
        out[item.key.toString()] = item.value;
      }
    }

    if (name == 'detector_state') {
      final extra = signal.extra;

      final sound = <String, dynamic>{};
      if (extra.containsKey('sound_evt')) {
        sound['event'] = extra['sound_evt'];
      }
      if (extra.containsKey('sound_do')) {
        sound['do'] = extra['sound_do'];
      }
      if (sound.isNotEmpty) {
        final existing = out['sound'];
        if (existing is Map<String, dynamic>) {
          existing.addAll(sound);
        } else {
          out['sound'] = sound;
        }
      }

      final ultrasonic = <String, dynamic>{};
      if (extra.containsKey('ultra_cm')) {
        ultrasonic['cm'] = extra['ultra_cm'];
      }
      if (extra.containsKey('ultra_ok')) {
        ultrasonic['ok'] = extra['ultra_ok'];
      }
      if (ultrasonic.isNotEmpty) {
        final existing = out['ultrasonic'];
        if (existing is Map<String, dynamic>) {
          existing.addAll(ultrasonic);
        } else {
          out['ultrasonic'] = ultrasonic;
        }
      }
    }
  }

  static const Set<String> _sensitiveKeys = {
    'ssid',

    'pass',

    'password',

    'token',

    'access_token',

    'refresh_token',

    'user_id',

    'wifi',

    'clave',
  };

  Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final out = <String, dynamic>{};

    input.forEach((k, v) {
      final key = k.toString();

      if (_sensitiveKeys.contains(key.toLowerCase())) return;

      out[key] = v;
    });

    return out;
  }

  // Considera "trivial" si solo trae claves tipo ok/status o esta vacio.

  bool _isTrivialPayload(Map<String, dynamic> m) {
    if (m.isEmpty) return true;

    final keys = m.keys.map((e) => e.toString().toLowerCase()).toList();

    final allAreFlags = keys.every(
      (k) => k == 'ok' || k == 'status' || k == 'message',
    );

    if (allAreFlags) return true;

    if (m.length == 1) {
      final v = m.values.first;

      if (v is bool && (keys.first == 'ok' || keys.first == 'status')) {
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final detectorSummary = _buildDetectorSummary(cs);
    final data = _effectiveLiveData;
    final usingRemote = _showingRemoteData;
    final dataSourceLabel = usingRemote
        ? (_remoteSourceLabel ?? 'Supabase')
        : _endpointUsed;
    final remoteFlagsInfo = _buildRemoteFlagsInfo(cs);

    final online = _online;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),

        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Ping',

            onPressed: _doPing,

            icon: const Icon(Icons.wifi_tethering),
          ),

          IconButton(
            tooltip: 'Recargar',

            onPressed: () {
              _pollOnce();

              _refreshServoState();

              setState(() {}); // refresca encabezados
            },

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),

        children: [
          Row(
            children: [
              Icon(
                Icons.circle,

                size: 12,

                color: online ? Colors.green : cs.outline,
              ),

              const SizedBox(width: 8),

              Text(
                online ? 'Conectado' : 'Desconectado',

                style: TextStyle(
                  fontWeight: FontWeight.w600,

                  color: online ? Colors.green : cs.onSurfaceVariant,
                ),
              ),

              const Spacer(),

              Chip(
                label: Text(widget.type.toUpperCase()),

                visualDensity: VisualDensity.compact,
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text('ID: ${widget.deviceId}'),

          Text('IP/Host: $_displayHost'),

          const SizedBox(height: 16),

          Card(
            elevation: 1,

            child: Padding(
              padding: const EdgeInsets.all(16),

              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 16),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      'Informacion',

                      style: TextStyle(
                        fontWeight: FontWeight.w700,

                        color: cs.primary,
                      ),
                    ),

                    const SizedBox(height: 12),

                    _kv('Nombre', widget.name),

                    _kv('Tipo', widget.type),

                    _kv('Host', _displayHost),

                    _kv(
                      'Visto por ultima vez',

                      _lastSeenAt != null
                          ? _lastSeenAt!.toLocal().toIso8601String()
                          : '--',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ====== Control de SERVO (nuevo, aparece solo si corresponde) ======
          if (_seVeControlServo) ...[
            const SizedBox(height: 16),

            Card(
              elevation: 1,

              clipBehavior: Clip.antiAlias,

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,

                children: [
                  Container(
                    color: cs.surfaceContainerHighest,

                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,

                      vertical: 8,
                    ),

                    child: const Text(
                      'Control de servo',

                      style: TextStyle(
                        fontWeight: FontWeight.w700,

                        fontSize: 16,
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,

                      vertical: 10,
                    ),

                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Estado:',

                            style: TextStyle(
                              color: cs.onSurfaceVariant,

                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        if (_servoOn == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),

                            child: SizedBox(
                              height: 20,

                              width: 20,

                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Switch.adaptive(
                            value: _servoOn ?? false,

                            onChanged: _servoBusy
                                ? null
                                : (v) {
                                    _setServoOn(v);
                                  },
                          ),

                        const SizedBox(width: 8),

                        FilledButton.icon(
                          onPressed: _servoBusy
                              ? null
                              : () => _refreshServoState(),

                          icon: const Icon(Icons.refresh),

                          label: const Text('Leer'),
                        ),
                      ],
                    ),
                  ),

                  if (_servoBusy)
                    const Padding(
                      padding: EdgeInsets.only(left: 12, right: 12, bottom: 12),

                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
            ),
          ],

          // ====== Datos en tiempo real ======
          const SizedBox(height: 16),

          Card(
            elevation: 1,

            clipBehavior: Clip.antiAlias,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                Container(
                  color: cs.surfaceContainerHighest,

                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,

                    vertical: 8,
                  ),

                  child: Row(
                    children: [
                      const Icon(Icons.sensors, size: 18),

                      const SizedBox(width: 8),

                      const Text(
                        'Datos en tiempo real',

                        style: TextStyle(
                          fontWeight: FontWeight.w700,

                          fontSize: 16,
                        ),
                      ),

                      const Spacer(),

                      if (dataSourceLabel != null && dataSourceLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,

                            vertical: 4,
                          ),

                          decoration: BoxDecoration(
                            color: usingRemote
                                ? cs.primaryContainer
                                : cs.surface,

                            borderRadius: BorderRadius.circular(12),

                            border: usingRemote
                                ? null
                                : Border.all(color: cs.outlineVariant),
                          ),

                          child: Text(
                            usingRemote
                                ? 'via $dataSourceLabel'
                                : dataSourceLabel,

                            style: TextStyle(
                              fontSize: 12,

                              color: usingRemote
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),

                  child: Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _pollOnce,

                        icon: const Icon(Icons.sync),

                        label: const Text('Actualizar'),
                      ),

                      const SizedBox(width: 8),

                      FilterChip(
                        label: const Text('Auto'),

                        selected: _autoRefresh,

                        onSelected: (v) {
                          setState(() => _autoRefresh = v);

                          if (v) {
                            _startAuto();
                          } else {
                            _stopAuto();
                          }
                        },
                      ),

                      const Spacer(),

                      if (_effectiveLastUpdate != null)
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,

                            child: Text(
                              'Actualizado: ${_effectiveLastUpdate!.toLocal().toIso8601String()}',

                              maxLines: 1,

                              overflow: TextOverflow.ellipsis,

                              softWrap: false,

                              style: TextStyle(
                                fontSize: 12,

                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                if (data == null && !usingRemote && _lastError == null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Buscando datos en ${_candidateDataPaths.join(", ")} ...',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                      if (remoteFlagsInfo != null) ...[
                        remoteFlagsInfo,
                        const SizedBox(height: 12),
                      ],
                    ],
                  )
                else if (data == null && _lastError != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No hay datos: $_lastError',
                                style: TextStyle(color: cs.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (remoteFlagsInfo != null) ...[
                        remoteFlagsInfo,
                        const SizedBox(height: 12),
                      ],
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (usingRemote && _lastError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            'No se pudo conectar por red local ($_lastError). '
                            'Mostrando los datos sincronizados desde Supabase.',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (remoteFlagsInfo != null) ...[
                        remoteFlagsInfo,
                        const SizedBox(height: 12),
                      ],
                      if (detectorSummary != null) ...[
                        detectorSummary,
                        const SizedBox(height: 12),
                      ],
                      _DataList(
                        data: data!,

                        onCopyJson: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                            ClipboardData(
                              text: const JsonEncoder.withIndent(
                                '  ',
                              ).convert(data),
                            ),
                          );

                          if (!mounted) return;

                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('JSON copiado al portapapeles'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ====== Tarjeta especifica para camara ======
          if (_showCameraCard) ...[
            const SizedBox(height: 16),

            Card(
              elevation: 1,

              clipBehavior: Clip.antiAlias,

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,

                children: [
                  Container(
                    color: cs.surfaceContainerHighest,

                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,

                      vertical: 8,
                    ),

                    child: const Text(
                      'Vista en vivo',

                      style: TextStyle(
                        fontWeight: FontWeight.w700,

                        fontSize: 16,
                      ),
                    ),
                  ),

                  SizedBox(height: 240, child: _buildCameraContent()),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Botonera en Wrap (evita overflow horizontal)
          Wrap(
            spacing: 12,

            runSpacing: 8,

            children: [
              FilledButton.icon(
                onPressed: _pinging ? null : _doPing,

                icon: const Icon(Icons.wifi),

                label: const Text('Ping'),
              ),

              OutlinedButton.icon(
                onPressed: _forgetAp,

                icon: const Icon(Icons.link_off),

                label: const Text('Olvidar (AP)'),
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCameraContent() {
    if (_hasStream) {
      return MjpegStreamView(
        url: 'http://$_displayHost/stream',
        fallbackSnapshotUrl: 'http://$_displayHost/photo',
      );
    }
    if (_remoteSnapshotUrl != null) {
      return _RemoteSnapshotView(
        url: _remoteSnapshotUrl!,
        onRefresh: _triggerSnapshotRefresh,
        olderUrl: _remoteSnapshotHistory.isNotEmpty
            ? _remoteSnapshotHistory.last
            : null,
        history: _remoteSnapshotHistory,
      );
    }
    if (_fetchingRemoteSnapshot) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_remoteSnapshotBucket != null) {
      return _CameraPlaceholder(onRetry: _triggerSnapshotRefresh);
    }
    return const Center(child: Text('Sin stream detectado.'));
  }

  bool _isPrivateIp(String? value) {
    if (value == null || value.isEmpty) return false;
    final v = value.trim();
    if (v.startsWith('10.') || v.startsWith('192.168.')) return true;
    if (v.startsWith('172.')) {
      final parts = v.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? -1;
        return second >= 16 && second <= 31;
      }
    }
    return false;
  }

  String _formatElapsed(Duration duration) {
    if (duration.inSeconds <= 0) return 'instantes';
    if (duration.inMinutes < 1) {
      return '${duration.inSeconds}s';
    }
    if (duration.inHours < 1) {
      final mins = duration.inMinutes;
      final secs = duration.inSeconds % 60;
      return secs == 0 ? '${mins}m' : '${mins}m ${secs}s';
    }
    if (duration.inDays < 1) {
      final hours = duration.inHours;
      final mins = duration.inMinutes % 60;
      return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
    }
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    return hours == 0 ? '${days}d' : '${days}d ${hours}h';
  }

  Widget? _buildRemoteFlagsInfo(ColorScheme cs) {
    final flags = _remoteFlags;
    if (flags == null) return null;

    String pingDescription() {
      switch (flags.pingStatus) {
        case 'ack':
          final since = flags.pingAckAt != null
              ? _formatElapsed(DateTime.now().difference(flags.pingAckAt!))
              : 'instantes';
          return 'Ping remoto confirmado hace $since.';
        case 'pending':
          final since = flags.pingRequestedAt != null
              ? _formatElapsed(
                  DateTime.now().difference(flags.pingRequestedAt!),
                )
              : 'pocos segundos';
          return 'Ping remoto pendiente (solicitado hace $since).';
        case 'error':
          return 'Ping remoto con error: ${flags.pingNote ?? 'sin detalle'}';
        default:
          return 'Ping remoto sin solicitudes recientes.';
      }
    }

    const String forgetInfo =
        'El olvido remoto esta deshabilitado. Usa el modo AP local desde la misma red.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pingDescription(),
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            forgetInfo,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),

      child: Row(
        children: [
          SizedBox(
            width: 160,

            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),

          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Map<String, dynamic>? _stringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, entry) => MapEntry(key.toString(), entry));
    }
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower.isEmpty) return null;
      if (lower == 'true' || lower == 'yes' || lower == '1') return true;
      if (lower == 'false' || lower == 'no' || lower == '0') return false;
    }
    return null;
  }

  Widget? _buildDetectorSummary(ColorScheme cs) {
    final data = _effectiveLiveData;
    if (data == null) return null;

    final typeLower = widget.type.toLowerCase();
    final bool isDetector =
        typeLower.contains('detector') ||
        data.containsKey('sound') ||
        data.containsKey('ultrasonic');
    if (!isDetector) return null;

    final sound = _stringKeyedMap(data['sound']);
    final ultrasonic = _stringKeyedMap(data['ultrasonic']);

    final bool? soundEvt = _asBool(sound?['event'] ?? data['sound_evt']);
    final int? soundDo = _asInt(sound?['do'] ?? data['sound_do']);

    final double? distance = _asDouble(ultrasonic?['cm'] ?? data['ultra_cm']);
    final bool? ultraOk = _asBool(ultrasonic?['ok'] ?? data['ultra_ok']);

    final entries = <Widget>[];

    if (soundEvt != null) {
      final label = soundEvt ? 'Ruido detectado' : 'Sin ruido';
      final extra = soundDo != null ? ' (DO=$soundDo)' : '';
      entries.add(_kv('Sonido', '$label$extra'));
    } else if (soundDo != null) {
      entries.add(_kv('MicrÃÂÃÂÃÂÃÂ³fono DO', soundDo.toString()));
    }

    if (distance != null) {
      final formatted = distance.abs() >= 100
          ? distance.toStringAsFixed(0)
          : distance.toStringAsFixed(distance.abs() >= 10 ? 1 : 2);
      entries.add(_kv('Distancia', '$formatted cm'));
    }

    if (ultraOk != null) {
      entries.add(_kv('Ultrasonido', ultraOk ? 'OK' : 'Sin eco'));
    }

    if (entries.isEmpty) return null;

    final sourceLabel = _endpointUsed?.isNotEmpty == true
        ? _endpointUsed!
        : (_remoteSourceLabel?.isNotEmpty == true ? _remoteSourceLabel! : null);

    if (sourceLabel != null) {
      entries.add(_kv('Fuente', sourceLabel));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen de sensores',
          style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
        ),
        const SizedBox(height: 8),
        ...entries,
      ],
    );
  }
}

class _DataList extends StatelessWidget {
  const _DataList({required this.data, required this.onCopyJson});

  final Map<String, dynamic> data;

  final VoidCallback onCopyJson;

  List<MapEntry<String, String>> _flatten(dynamic value, [String prefix = '']) {
    final list = <MapEntry<String, String>>[];

    if (value is Map) {
      value.forEach((k, v) {
        final p = prefix.isEmpty ? '$k' : '$prefix.$k';

        list.addAll(_flatten(v, p));
      });
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final p = prefix.isEmpty ? '[$i]' : '$prefix[$i]';

        list.addAll(_flatten(value[i], p));
      }
    } else {
      list.add(MapEntry(prefix, value?.toString() ?? 'null'));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final flat = _flatten(data);

    return Column(
      children: [
        if (flat.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),

            child: Text(
              'Sin datos para mostrar.',

              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,

            physics: const NeverScrollableScrollPhysics(),

            itemCount: flat.length,

            separatorBuilder: (ctx, __) => const Divider(height: 1),

            itemBuilder: (ctx, i) {
              final e = flat[i];

              return ListTile(
                dense: true,

                title: Text(
                  e.key,

                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),

                subtitle: Text(e.value),

                trailing: IconButton(
                  tooltip: 'Copiar valor',

                  icon: const Icon(Icons.copy),

                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(ctx);
                    await Clipboard.setData(ClipboardData(text: e.value));
                    if (!ctx.mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Valor copiado')),
                    );
                  },
                ),
              );
            },
          ),

        Align(
          alignment: Alignment.centerRight,

          child: TextButton.icon(
            onPressed: onCopyJson,

            icon: const Icon(Icons.code),

            label: const Text('Copiar JSON'),
          ),
        ),
      ],
    );
  }
}

/// Widget sencillo para reproducir un MJPEG.

/// - Intenta abrir /stream.

/// - Si falla 3 veces seguidas, alterna a polling de /photo (snapshot).

class _RemoteSnapshotView extends StatelessWidget {
  const _RemoteSnapshotView({
    required this.url,
    required this.onRefresh,
    this.olderUrl,
    this.history = const [],
  });

  final String url;
  final VoidCallback onRefresh;
  final String? olderUrl;
  final List<String> history;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (history.isNotEmpty)
          Positioned.fill(
            child: Image.network(
              history.last,
              key: ValueKey('history_${history.last}'),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        Positioned.fill(
          child: Image.network(
            url,
            key: ValueKey(url),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: IconButton.filledTonal(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar foto',
          ),
        ),
      ],
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_camera_back_outlined,
            size: 48,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Esperando imagen remota...',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
