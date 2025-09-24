// lib/screens/devices_page.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/theme_toggle_button.dart';
import '../services/lan_discovery_service.dart';
import '../data/local/app_db.dart';
import 'device_detail_page.dart'; // <-- navegación a detalle

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _discovery = LanDiscoveryService();

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
    _discovery.stop();
    super.dispose();
  }

  String _normKey(String s) {
    final k = s.toLowerCase().trim();
    return k.endsWith('.local') ? k.substring(0, k.length - 6) : k;
  }

  String _keyForDiscovered(DiscoveredDevice d) {
    if (d.name.trim().isNotEmpty) return _normKey(d.name);
    return _normKey(d.id);
  }

  bool _recent(int? lastSeenMs) {
    if (lastSeenMs == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastSeenMs) <= 8000;
  }

  Future<bool> _isOnLan() async {
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final ip = a.address;
          if (ip.startsWith('10.') || ip.startsWith('192.168.')) return true;
          if (ip.startsWith('172.')) {
            final p = ip.split('.');
            if (p.length >= 2) {
              final sec = int.tryParse(p[1]) ?? -1;
              if (sec >= 16 && sec <= 31) return true;
            }
          }
        }
      }
    } catch (_) {
      return true;
    }
    return false;
  }

  Future<void> _runScan() async {
    if (_scanning) return;
    setState(() => _scanning = true);

    final onLan = await _isOnLan();
    if (!onLan) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conéctate a una red Wi-Fi primero.')),
        );
      }
      setState(() => _scanning = false);
      return;
    }

    // 1) Descubrir
    List<DiscoveredDevice> found = const [];
    try {
      found = await _discovery.discover(timeout: const Duration(seconds: 4));
    } catch (_) {}

    final db = AppDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 2) Upsert + touch por host (dedupe)
    final seenKeys = <String, _OnlineHit>{};
    for (final d in found) {
      final key = _keyForDiscovered(d);
      seenKeys[key] = _OnlineHit(ip: d.ip, type: d.type, name: d.name);

      await db.upsertDeviceByDeviceId(
        deviceId: key,
        name: d.name.isNotEmpty ? d.name : key,
        type: d.type,
        ip: d.ip,
        addedAt: now,
      );
      await db.touchDeviceSeen(key, ip: d.ip);
    }

    // 3) Pintar DB + marcar online
    final devices = await db.fetchAllDevices();
    final rows = <_Row>[];
    for (final dev in devices) {
      final key = _normKey(dev.deviceId);
      final hit = seenKeys[key];
      rows.add(
        _Row(
          key: key,
          title: dev.name,
          ip: hit?.ip ?? dev.ip,
          type: dev.type,
          online: _recent(dev.lastSeenAt),
          lastSeenAt: dev.lastSeenAt,
        ),
      );
    }

    // 4) Cualquier hallazgo no presente (muy raro)
    for (final e in seenKeys.entries) {
      if (!rows.any((r) => r.key == e.key)) {
        rows.add(
          _Row(
            key: e.key,
            title: e.value.name ?? e.key,
            ip: e.value.ip,
            type: e.value.type ?? 'esp',
            online: true,
            lastSeenAt: now,
          ),
        );
      }
    }

    // Orden: online primero
    rows.sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _scanning = false;
    });
  }

  Future<void> _forget(_Row row) async {
    // 1) Intento fuerte de poner el equipo en AP
    final tries = <Uri>[
      if ((row.ip ?? '').isNotEmpty) Uri.parse('http://${row.ip}/apmode'),
      Uri.parse('http://${row.key}.local/apmode'),
      if ((row.ip ?? '').isNotEmpty) Uri.parse('http://${row.ip}/factory'),
      Uri.parse('http://${row.key}.local/factory'),
    ];
    for (final u in tries) {
      try {
        await http.get(u).timeout(const Duration(seconds: 3));
        break;
      } catch (_) {}
    }

    // 2) Limpiamos BD en todas las variantes de clave
    final db = AppDb.instance;
    await db.deleteDeviceByDeviceId(row.key);
    await db.deleteDeviceByDeviceId('${row.key}.local');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dispositivo olvidado. En pocos segundos debería encender su AP “CASA-ESP_xxxx”.',
          ),
        ),
      );
    }

    _runScan();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos (LAN)'),
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
                hintText: _scanning ? 'Buscando…' : 'Buscar en la red',
                suffixIcon: _scanning
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Buscar ahora',
                        icon: const Icon(Icons.refresh),
                        onPressed: _runScan,
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(
                      _scanning
                          ? 'Buscando dispositivos…'
                          : 'No hay dispositivos guardados todavía.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      final chipColor = r.online ? Colors.green : cs.outline;
                      final chipText = r.online ? 'Conectado' : 'Desconectado';

                      return ListTile(
                        leading: Icon(Icons.memory, color: chipColor),
                        title: Text(
                          r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${r.ip ?? '—'}  •  ${r.type}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: r.online
                                    ? Colors.green.withOpacity(.12)
                                    : cs.surfaceVariant,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: r.online ? Colors.green : cs.outline,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                chipText,
                                style: TextStyle(
                                  color: r.online
                                      ? Colors.green
                                      : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              tooltip: 'Opciones',
                              onSelected: (v) {
                                if (v == 'forget') _forget(r);
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

                        // === NAVEGACIÓN AL DETALLE ===
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DeviceDetailPage(
                                deviceId: r.key,
                                name: r.title,
                                type: r.type,
                                ip: r.ip,
                                lastSeenAt: r.lastSeenAt,
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
              'Tip: “Desconectar (olvidar)” elimina el equipo de la app y le pide entrar en AP. '
              'Para volver a usarlo, provisiona otra vez por SoftAP.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row {
  final String key; // device_id normalizado
  final String title; // nombre visible
  final String? ip;
  final String type;
  final bool online;
  final int? lastSeenAt;

  _Row({
    required this.key,
    required this.title,
    required this.ip,
    required this.type,
    required this.online,
    required this.lastSeenAt,
  });
}

class _OnlineHit {
  final String? ip;
  final String? type;
  final String? name;
  _OnlineHit({this.ip, this.type, this.name});
}
