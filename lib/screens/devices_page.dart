// lib/screens/devices_page.dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/repositories/device_repository.dart';
import 'package:flutter_seguridad_en_casa/services/remote_device_service.dart';
import 'device_detail_page.dart';

enum _DeviceKind { servo, camera, detector }

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final DeviceRepository _repository = DeviceRepository.instance;
  final RemoteDeviceService _remoteService = RemoteDeviceService();

  bool _scanning = false;
  Timer? _autoTimer;
  List<_Row> _rows = const [];

  @override
  void initState() {
    super.initState();
    _runScan();
    _autoTimer = Timer.periodic(const Duration(seconds: 8), (_) => _runScan());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _runScan() async {
    if (_scanning) return;
    setState(() => _scanning = true);

    try {
      final devices = await _repository.listDevices();
      final rows = <_Row>[];
      for (final device in devices) {
        try {
          await _remoteService.ensureRemoteFlags(device.id);
        } catch (e) {
          debugPrint('No se pudo asegurar remote_flags para ${device.id}: $e');
        }
        try {
          final flags = await _remoteService.fetchRemoteFlags(device.id);
          if (flags != null && flags.forgetDone) {
            await _repository.finalizeRemoteForget(device.id);
            continue;
          }
        } catch (e) {
          debugPrint('No se pudieron leer remote_flags de ${device.id}: $e');
        }
        final kind = await _classifyDevice(device);
        await _ensureDeviceType(device, kind);
        final typeLabel = _displayType(device.name, device.type, kind);
        final local = await AppDb.instance.getDeviceByDeviceId(device.id);
        rows.add(
          _Row(
            id: device.id,
            title: device.name,
            ip: device.ip,
            type: typeLabel,
            kind: kind,
            online: device.isOnline,
            lastSeenAt: device.lastSeenAt ?? device.addedAt,
            homeActive: local?.homeActive ?? false,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
      });
    } catch (e) {
      debugPrint('Error obteniendo dispositivos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error obteniendo dispositivos: $e')),
        );
      }
    }

    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _forget(_Row row) async {
    try {
      final outcome =
          await _repository.forgetAndReset(deviceId: row.id, ip: row.ip);
      if (!mounted) return;
      switch (outcome) {
        case ForgetOutcome.local:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dispositivo reiniciado por IP local. Enciende su AP en breves segundos.',
              ),
            ),
          );
          break;
        case ForgetOutcome.remoteConfirmed:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Orden remota confirmada. El dispositivo entrara en modo AP en breve.',
              ),
            ),
          );
          break;
        case ForgetOutcome.remoteQueued:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Orden encolada en Supabase. Se ejecutara cuando el equipo se conecte; vuelve a intentar si no cambia a modo AP.',
              ),
            ),
          );
          await _runScan();
          return;
      }
    } on StateError catch (e) {
      debugPrint('StateError olvidando dispositivo ${row.id}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message,
            ),
          ),
        );
      }
      return;
    } catch (e) {
      debugPrint('Error eliminando dispositivo en Supabase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo completar el reinicio remoto: $e',
            ),
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo olvidado.'),
        ),
      );
    }

    _runScan();
  }

  Future<void> _toggleHomeActive(_Row row, bool active) async {
    try {
      await AppDb.instance.setDeviceHomeActive(row.id, active);
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final current in _rows)
            current.id == row.id ? current.copyWith(homeActive: active) : current
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? '${row.title} ahora estará activo en Inicio.'
                : '${row.title} se ocultará de Inicio.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error actualizando homeActive: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el estado en Inicio: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
        actions: const [ThemeToggleButton()],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              readOnly: true,
              onTap: _runScan,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _scanning ? 'Buscando...' : 'Buscar en la red',
                suffixIcon: IconButton(
                  onPressed: _runScan,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(
                      _scanning
                          ? 'Buscando dispositivos...'
                          : 'No hay dispositivos guardados todavia.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final chipColor = row.online ? Colors.green : cs.outline;
                      final chipText = row.online
                          ? 'Conectado'
                          : 'Desconectado';
                      final icon = _iconForKind(row.kind);

                      return ListTile(
                        leading: Icon(icon, color: chipColor),
                        title: Text(
                          row.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${row.ip ?? '-'} | ${row.type}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: row.homeActive,
                              onChanged: (value) =>
                                  _toggleHomeActive(row, value),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: row.online
                                    ? Colors.green.withOpacity(.12)
                                    : cs.surfaceVariant,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: row.online ? Colors.green : cs.outline,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                chipText,
                                style: TextStyle(
                                  color: row.online
                                      ? Colors.green
                                      : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              tooltip: 'Opciones',
                              onSelected: (value) {
                                if (value == 'forget') _forget(row);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'forget',
                                  child: Text('Desconectar (olvidar)'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DeviceDetailPage(
                                deviceId: row.id,
                                name: row.title,
                                type: row.type,
                                ip: row.ip,
                                lastSeenAt: row.lastSeenAt,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 16, right: 16),
            child: Text(
              'Tip: "Desconectar (olvidar)" elimina el equipo de la app y le pide entrar en AP. '
              'Para volver a usarlo, provisiona otra vez por SoftAP.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Future<_DeviceKind> _classifyDevice(DeviceRecord device) async {
    final rawType = device.type;
    final name = device.name;

    try {
      final cached = await AppDb.instance.getDeviceByDeviceId(device.id);
      final cachedType = cached?.type ?? '';
      if (_looksLikeServoString(cachedType)) {
        await _ensureDeviceType(device, _DeviceKind.servo);
        return _DeviceKind.servo;
      }
      if (_looksLikeCameraString(cachedType)) {
        await _ensureDeviceType(device, _DeviceKind.camera);
        return _DeviceKind.camera;
      }
    } catch (e) {
      debugPrint('No se pudo leer cache local para ${device.id}: $e');
    }

    if (_looksLikeServoString(rawType) || _looksLikeServoString(name)) {
      return _DeviceKind.servo;
    }

    try {
      final actuators = await _remoteService.fetchActuators(device.id);
      if (actuators.any(_actuatorLooksLikeServo)) {
        return _DeviceKind.servo;
      }
    } catch (e) {
      debugPrint('No se pudieron obtener actuadores de ${device.id}: $e');
    }

    if (_looksLikeCameraString(rawType) || _looksLikeCameraString(name)) {
      return _DeviceKind.camera;
    }

    try {
      final signals = await _remoteService.fetchLiveSignals(device.id);
      if (signals.any(_signalLooksLikeCamera)) {
        return _DeviceKind.camera;
      }
    } catch (e) {
      debugPrint('No se pudieron obtener senales de ${device.id}: $e');
    }

    return _DeviceKind.detector;
  }

  Future<void> _ensureDeviceType(DeviceRecord device, _DeviceKind kind) async {
    final target = _canonicalTypeForKind(kind);
    if (target == null) return;
    final current = device.type.trim().toLowerCase();
    if (current == target) return;
    try {
      await _repository.updateType(device.id, target);
    } catch (e) {
      debugPrint(
        'No se pudo actualizar el tipo del dispositivo ${device.id}: $e',
      );
    }
  }

  String _displayType(String name, String rawType, _DeviceKind kind) {
    final trimmedType = rawType.trim();
    final hasMeaningfulType =
        trimmedType.isNotEmpty &&
        _normalizeForMatch(trimmedType) != 'unknown' &&
        !_looksLikeServoString(trimmedType) &&
        !_looksLikeCameraString(trimmedType);

    switch (kind) {
      case _DeviceKind.servo:
        if (_looksLikeServoString(trimmedType)) return trimmedType;
        return 'Servo';
      case _DeviceKind.camera:
        if (_looksLikeCameraString(trimmedType)) {
          return trimmedType;
        }
        if (_looksLikeCameraString(name)) {
          return name;
        }
        return 'Camara';
      case _DeviceKind.detector:
        if (hasMeaningfulType) {
          return trimmedType;
        }
        return 'ESP32';
    }
  }

  IconData _iconForKind(_DeviceKind kind) {
    switch (kind) {
      case _DeviceKind.servo:
        return Icons.precision_manufacturing;
      case _DeviceKind.camera:
        return Icons.videocam_outlined;
      case _DeviceKind.detector:
        return Icons.sensors;
    }
  }

  bool _looksLikeServoString(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final normalized = _normalizeForMatch(value);
    return normalized.contains('servo') ||
        normalized.contains('actuador') ||
        normalized.contains('actuator');
  }

  bool _looksLikeCameraString(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final normalized = _normalizeForMatch(value);
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
    if (normalized.contains('video') ||
        normalized.contains('stream') ||
        normalized.contains('mjpeg')) {
      return true;
    }
    return false;
  }

  bool _actuatorLooksLikeServo(RemoteActuator actuator) {
    if (_looksLikeServoString(actuator.kind)) return true;
    if (_looksLikeServoString(actuator.name)) return true;

    final meta = actuator.meta;
    final metaKind = meta['kind'] ?? meta['type'] ?? meta['role'];
    if (metaKind is String && _looksLikeServoString(metaKind)) {
      return true;
    }
    return false;
  }

  bool _signalLooksLikeCamera(RemoteLiveSignal signal) {
    if (_looksLikeCameraString(signal.kind)) return true;
    if (_looksLikeCameraString(signal.name)) return true;

    final snapshot = signal.snapshotPath;
    if (snapshot != null && snapshot.isNotEmpty) return true;

    final stream = signal.extra['stream'];
    if (stream is String && stream.trim().isNotEmpty) return true;

    final label = signal.extra['label'];
    if (label is String && _looksLikeCameraString(label)) return true;

    return false;
  }

  String _normalizeForMatch(String value) {
    final buffer = StringBuffer();
    for (final codePoint in value.toLowerCase().runes) {
      switch (codePoint) {
        case 0x00E0: // a-grave
        case 0x00E1: // a-acute
        case 0x00E2: // a-circ
        case 0x00E3: // a-tilde
        case 0x00E4: // a-umlaut
          buffer.write('a');
          break;
        case 0x00E8: // e-grave
        case 0x00E9: // e-acute
        case 0x00EA: // e-circ
        case 0x00EB: // e-umlaut
          buffer.write('e');
          break;
        case 0x00EC: // i-grave
        case 0x00ED: // i-acute
        case 0x00EE: // i-circ
        case 0x00EF: // i-umlaut
          buffer.write('i');
          break;
        case 0x00F2: // o-grave
        case 0x00F3: // o-acute
        case 0x00F4: // o-circ
        case 0x00F5: // o-tilde
        case 0x00F6: // o-umlaut
          buffer.write('o');
          break;
        case 0x00F9: // u-grave
        case 0x00FA: // u-acute
        case 0x00FB: // u-circ
        case 0x00FC: // u-umlaut
          buffer.write('u');
          break;
        case 0x00F1: // n-tilde
          buffer.write('n');
          break;
        default:
          buffer.write(String.fromCharCode(codePoint));
      }
    }
    return buffer.toString();
  }

  String? _canonicalTypeForKind(_DeviceKind kind) {
    switch (kind) {
      case _DeviceKind.servo:
        return 'servo';
      case _DeviceKind.camera:
        return 'esp32cam';
      case _DeviceKind.detector:
        return null;
    }
  }
}

class _Row {
  const _Row({
    required this.id,
    required this.title,
    required this.ip,
    required this.type,
    required this.kind,
    required this.online,
    required this.lastSeenAt,
    required this.homeActive,
  });

  final String id;
  final String title;
  final String? ip;
  final String type;
  final _DeviceKind kind;
  final bool online;
  final DateTime lastSeenAt;
  final bool homeActive;

  _Row copyWith({bool? homeActive}) {
    return _Row(
      id: id,
      title: title,
      ip: ip,
      type: type,
      kind: kind,
      online: online,
      lastSeenAt: lastSeenAt,
      homeActive: homeActive ?? this.homeActive,
    );
  }
}
