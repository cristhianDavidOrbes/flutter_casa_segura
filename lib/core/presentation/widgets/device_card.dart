// lib/features/devices/presentation/widgets/device_card.dart
import 'dart:math';

import 'package:flutter/material.dart';

/// Modelo mínimo esperado por la tarjeta.
/// Si ya tienes tu propio Device (p. ej. en app_db.dart), puedes
/// adaptar los campos o crear un mapper.
class DeviceCardData {
  const DeviceCardData({
    required this.deviceId,
    required this.name,
    required this.type, // "esp32cam", "esp", "servo", etc.
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

/// Tarjeta compacta para mostrar un dispositivo en un carrusel horizontal.
/// Ancho pensado para 2–3 tarjetas visibles en pantallas comunes.
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

  /// Navegar a la página de detalles.
  final VoidCallback? onOpen;

  /// Reintentar traer datos.
  final VoidCallback? onRefresh;

  /// Si el dispositivo es de type "servo", se muestra el switch.
  /// Se llama con el valor de destino (true=180, false=0).
  final Future<void> Function(bool on)? onServoToggle;

  /// Para mostrar un pequeño loader en el switch mientras golpeas al endpoint.
  final bool isTogglingServo;

  bool get _isServo =>
      data.type.toLowerCase() == 'servo' ||
      data.type.toLowerCase().contains('servo');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Encabezado: estado + tipo
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: data.online ? Colors.green : cs.outline,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      data.online ? 'Conectado' : 'Desconectado',
                      style: TextStyle(
                        fontSize: 12,
                        color: data.online ? Colors.green : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _TypeChip(type: data.type),
                  ],
                ),
                const SizedBox(height: 8),

                // Nombre
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

                // Host / IP
                Text(
                  (data.ip?.isNotEmpty ?? false)
                      ? 'IP: ${data.ip}'
                      : (data.host?.isNotEmpty ?? false)
                      ? 'Host: ${data.host}'
                      : 'ID: ${data.deviceId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),

                // Preview de datos
                _DataPreview(liveData: data.liveData),

                const Spacer(),

                // Si es servo, switch dedicado
                if (_isServo) ...[
                  const SizedBox(height: 8),
                  _ServoRow(
                    liveData: data.liveData,
                    onToggle: onServoToggle,
                    isBusy: isTogglingServo,
                  ),
                ],

                const SizedBox(height: 12),

                // Botonera inferior
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: onOpen,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text('Ver'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: onRefresh,
                      tooltip: 'Actualizar',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip con el tipo (ESP, CAM, SERVO)
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    IconData icon;
    final t = type.toLowerCase();
    if (t.contains('cam')) {
      icon = Icons.videocam;
    } else if (t.contains('servo')) {
      icon = Icons.switch_access_shortcut;
    } else {
      icon = Icons.memory;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            type.toUpperCase(),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Muestra hasta 3 pares clave/valor "útiles" del JSON.
/// Ignora payloads triviales como {"ok":true} o {"status":"ok"}.
class _DataPreview extends StatelessWidget {
  const _DataPreview({this.liveData});
  final Map<String, dynamic>? liveData;

  static const _ignoreKeys = {'ok', 'status', 'message'};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pairs = _extractPairs(liveData);
    if (pairs.isEmpty) {
      return Text(
        'Sin datos aún…',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in pairs.take(3)) ...[
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
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  List<MapEntry<String, String>> _extractPairs(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return [];
    // Flatten superficial y fácil.
    final out = <MapEntry<String, String>>[];

    void walk(dynamic v, [String prefix = '']) {
      if (v is Map) {
        for (final kv in v.entries) {
          final k = kv.key.toString();
          if (_ignoreKeys.contains(k.toLowerCase())) continue;
          final p = prefix.isEmpty ? k : '$prefix.$k';
          walk(kv.value, p);
        }
      } else if (v is List) {
        for (var i = 0; i < v.length; i++) {
          final p = '$prefix[$i]';
          walk(v[i], p);
        }
      } else {
        out.add(MapEntry(prefix, (v ?? 'null').toString()));
      }
    }

    walk(m);

    // Ordena por longitud de clave (heurística simple para legibilidad)
    out.sort((a, b) => a.key.length.compareTo(b.key.length));
    return out;
  }
}

/// Fila de control para servo: switch + etiqueta de estado.
/// Lee `servo.on` y/o `servo.pos` de liveData si existen.
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

    final parsed = _parse(liveData);
    final isOn = parsed.$1;
    final pos = parsed.$2;

    return Row(
      children: [
        Expanded(
          child: Text(
            isOn
                ? 'Activado (pos: ${pos ?? 180}°)'
                : 'Desactivado (pos: ${pos ?? 0}°)',
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
            onChanged: onToggle == null ? null : (v) => onToggle!(v),
          ),
      ],
    );
  }

  /// Devuelve (on, pos) leyendo de:
  /// - servo.on (bool)
  /// - servo.pos (int)
  /// - o heurística si sólo hay pos.
  (bool, int?) _parse(Map<String, dynamic>? m) {
    if (m == null) return (false, null);

    dynamic servo = m['servo'];
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

    // fallback: intenta con claves sueltas
    final pos = (m['pos'] is num) ? (m['pos'] as num).toInt() : null;
    final on = (m['on'] is bool)
        ? (m['on'] as bool)
        : (pos != null ? pos >= 90 : false);
    return (on, pos);
  }
}
