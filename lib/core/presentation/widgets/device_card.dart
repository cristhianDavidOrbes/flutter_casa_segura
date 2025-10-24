import 'dart:math';

import 'package:flutter/material.dart';

class DeviceCardData {
  const DeviceCardData({
    required this.deviceId,
    required this.name,
    required this.type,
    this.ip,
    this.host,
    this.online = false,
    this.lastSeenAt,
    this.liveData,
  });

  final String deviceId;
  final String name;
  final String type;
  final String? ip;
  final String? host;
  final bool online;
  final DateTime? lastSeenAt;
  final Map<String, dynamic>? liveData;
}

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.data,
    this.onOpen,
    this.onRefresh,
    this.onServoToggle,
    this.isTogglingServo = false,
  });

  final DeviceCardData data;
  final VoidCallback? onOpen;
  final VoidCallback? onRefresh;
  final Future<void> Function(bool on)? onServoToggle;
  final bool isTogglingServo;

  bool get _isServo =>
      data.type.toLowerCase() == 'servo' ||
      data.type.toLowerCase().contains('servo');

  bool get _isCamera =>
      data.type.toLowerCase().contains('cam') ||
      data.type.toLowerCase().contains('camera');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final statusColor = data.online ? Colors.green : cs.outline;
    final statusLabel = data.online ? 'Conectado' : 'Desconectado';

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusAvatar(
                    icon: _iconForType(data.type),
                    color: statusColor,
                    online: data.online,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.type.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _secondaryLine(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onRefresh != null)
                    IconButton(
                      onPressed: onRefresh,
                      tooltip: 'Actualizar',
                      icon: const Icon(Icons.refresh),
                    ),
                ],
              ),
              if (_isCamera) ...[
                const SizedBox(height: 16),
                _CameraPreview(colorScheme: cs),
              ],
              const SizedBox(height: 14),
              _DataPreview(liveData: data.liveData),
              if (_isServo) ...[
                const SizedBox(height: 12),
                _ServoRow(
                  liveData: data.liveData,
                  onToggle: onServoToggle,
                  isBusy: isTogglingServo,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (onOpen != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: onOpen,
                        child: const Text('Ver'),
                      ),
                    ),
                  if (onOpen != null && onRefresh != null)
                    const SizedBox(width: 12),
                  if (onRefresh != null)
                    FilledButton.tonalIcon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.autorenew),
                      label: const Text('Actualizar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _secondaryLine() {
    final ip = data.ip?.trim();
    if (ip != null && ip.isNotEmpty) {
      return 'IP: $ip';
    }
    final host = data.host?.trim();
    if (host != null && host.isNotEmpty) {
      return 'Host: $host';
    }
    return 'ID: ${data.deviceId}';
  }
}

class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({
    required this.icon,
    required this.color,
    required this.online,
  });

  final IconData icon;
  final Color color;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = online ? color : cs.outline;
    final fillColor = online
        ? color.withOpacity(0.12)
        : cs.surfaceVariant.withOpacity(0.6);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(color: borderColor, width: 3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: borderColor, size: 22),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        color: colorScheme.surfaceVariant.withOpacity(0.7),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.videocam_outlined, color: colorScheme.onSurfaceVariant),
    );
  }
}

IconData _iconForType(String type) {
  final lower = type.toLowerCase();
  if (lower.contains('cam')) return Icons.videocam_outlined;
  if (lower.contains('servo')) return Icons.precision_manufacturing_outlined;
  if (lower.contains('detector')) return Icons.sensors;
  if (lower.contains('door') || lower.contains('lock')) {
    return Icons.meeting_room_outlined;
  }
  return Icons.memory;
}

const Set<String> _ignoreKeys = {'ok', 'status', 'message'};

class _DataPreview extends StatelessWidget {
  const _DataPreview({this.liveData});
  final Map<String, dynamic>? liveData;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pairs = _extractPairs(liveData);
    if (pairs.isEmpty) {
      return Text(
        'Sin datos aun.',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const rowExtent = 18.0;
        var maxRows = 3;
        if (constraints.maxHeight.isFinite) {
          maxRows = max(1, (constraints.maxHeight / rowExtent).floor());
        }
        final visible = pairs.take(maxRows).toList();
        final hasMore = pairs.length > visible.length;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in visible) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            if (hasMore)
              Text(
                '...',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
          ],
        );
      },
    );
  }
}

List<MapEntry<String, String>> _extractPairs(Map<String, dynamic>? source) {
  if (source == null || source.isEmpty) return <MapEntry<String, String>>[];

  final pairs = <MapEntry<String, String>>[];
  final remaining = Map<String, dynamic>.from(source);

  void addPair(String label, String value, {String? removeKey}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    pairs.add(MapEntry(label, trimmed));
    if (removeKey != null) {
      remaining.remove(removeKey);
    }
  }

  String formatDistance(num value) {
    final absVal = value.abs();
    if (absVal >= 100) return '${value.toStringAsFixed(0)} cm';
    if (absVal >= 10) return '${value.toStringAsFixed(1)} cm';
    return '${value.toStringAsFixed(2)} cm';
  }

  String? formatBool(
    dynamic value, {
    String trueLabel = 'Si',
    String falseLabel = 'No',
  }) {
    if (value is bool) return value ? trueLabel : falseLabel;
    if (value is num) return value != 0 ? trueLabel : falseLabel;
    return null;
  }

  final servo = remaining.remove('servo');
  if (servo is Map) {
    final onLabel = formatBool(
      servo['on'],
      trueLabel: 'Activado',
      falseLabel: 'Apagado',
    );
    if (onLabel != null) addPair('Servo', onLabel);
    final pos = servo['pos'];
    if (pos is num) {
      final clamped = pos.clamp(0, 180).toInt();
      addPair('Posicion', '${clamped} deg');
    }
  }

  final distance =
      remaining.remove('distance_cm') ?? remaining.remove('ultra_cm');
  if (distance is num) {
    addPair('Distancia', formatDistance(distance));
  }

  final soundEvt =
      remaining.remove('sound_event') ?? remaining.remove('sound_evt');
  final soundLabel = formatBool(
    soundEvt,
    trueLabel: 'Detectado',
    falseLabel: 'Normal',
  );
  if (soundLabel != null) addPair('Sonido', soundLabel);

  final soundRaw =
      remaining.remove('sound_raw') ?? remaining.remove('sound_do');
  if (soundRaw is num) {
    addPair('Microfono DO', soundRaw.toInt().toString());
  } else if (soundRaw != null) {
    addPair('Microfono DO', soundRaw.toString());
  }

  final ultraOk =
      remaining.remove('ultrasonic_ok') ?? remaining.remove('ultra_ok');
  final ultraLabel = formatBool(
    ultraOk,
    trueLabel: 'OK',
    falseLabel: 'Sin eco',
  );
  if (ultraLabel != null) addPair('Ultrasonido', ultraLabel);

  final updated = remaining.remove('updated_at');
  if (updated is String && updated.isNotEmpty) {
    addPair('Actualizado', updated);
  }

  void walk(dynamic value, String prefix) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_ignoreKeys.contains(key.toLowerCase())) continue;
        final next = prefix.isEmpty ? key : '$prefix.$key';
        walk(entry.value, next);
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final next = prefix.isEmpty ? '[$i]' : '$prefix[$i]';
        walk(value[i], next);
      }
    } else {
      final textValue = (value ?? 'null').toString().trim();
      if (textValue.isEmpty) return;
      pairs.add(MapEntry(prefix.isEmpty ? 'valor' : prefix, textValue));
    }
  }

  walk(remaining, '');
  pairs.sort((a, b) => a.key.length.compareTo(b.key.length));
  return pairs;
}

class _ServoRow extends StatelessWidget {
  const _ServoRow({
    required this.liveData,
    required this.onToggle,
    required this.isBusy,
  });

  final Map<String, dynamic>? liveData;
  final Future<void> Function(bool on)? onToggle;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final result = _parse(liveData);
    final isOn = result.$1;
    final pos = result.$2;

    return Row(
      children: [
        Expanded(
          child: Text(
            isOn
                ? 'Activado (pos: ${pos ?? '-'} deg)'
                : 'Desactivado (pos: ${pos ?? '-'} deg)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.onSurface),
          ),
        ),
        const SizedBox(width: 8),
        if (isBusy)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Switch(
            value: isOn,
            onChanged: onToggle == null ? null : (value) => onToggle!(value),
          ),
      ],
    );
  }

  (bool, int?) _parse(Map<String, dynamic>? map) {
    if (map == null) return (false, null);

    final servo = map['servo'];
    if (servo is Map) {
      final on = (servo['on'] is bool)
          ? (servo['on'] as bool)
          : (servo['pos'] is num)
          ? (servo['pos'] as num) >= 90
          : false;
      final pos = (servo['pos'] is num)
          ? max(0, min(180, (servo['pos'] as num).toInt()))
          : null;
      return (on, pos);
    }

    final pos = (map['pos'] is num) ? (map['pos'] as num).toInt() : null;
    final on = (map['on'] is bool)
        ? (map['on'] as bool)
        : (pos != null ? pos >= 90 : false);
    return (on, pos);
  }
}
