// lib/screens/devices_page.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/repositories/device_repository.dart';
import '../services/lan_discovery_service.dart';
import 'device_detail_page.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _discovery = LanDiscoveryService();
  final DeviceRepository _repository = DeviceRepository.instance;

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

  Future<bool> _isOnLan() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('10.') || ip.startsWith('192.168.')) return true;
          if (ip.startsWith('172.')) {
            final parts = ip.split('.');
            if (parts.length >= 2) {
              final second = int.tryParse(parts[1]) ?? -1;
              if (second >= 16 && second <= 31) return true;
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
          const SnackBar(content: Text('Conectate a una red Wi-Fi primero.')),
        );
      }
      setState(() => _scanning = false);
      return;
    }

    List<DiscoveredDevice> discovered = const [];
    try {
      discovered = await _discovery.discover(
        timeout: const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint('Error en discover: $e');
    }

    final hits = <String, _OnlineHit>{};
    for (final device in discovered) {
      final key = _repository.normalizeKey(
        device.name.isNotEmpty ? device.name : device.id,
      );
      hits[key] = _OnlineHit(ip: device.ip, type: device.type, name: device.name);
    }

    try {
      await _repository.syncDiscovered(discovered);
    } catch (e) {
      debugPrint('Error sincronizando con Supabase: $e');
    }

    List<DeviceRecord> devices = const [];
    try {
      devices = await _repository.listDevices();
    } catch (e) {
      debugPrint('Error obteniendo dispositivos: $e');
    }

    final rows = <_Row>[];
    for (final device in devices) {
      final hit = hits[device.deviceKey];
            final lastSeen = hit != null ? DateTime.now() : (device.lastSeenAt ?? device.addedAt);
      rows.add(
        _Row(
          key: device.deviceKey,
          title: device.name,
          ip: hit?.ip ?? device.ip,
          type: device.type,
          online: hit != null,
          lastSeenAt: lastSeen,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _scanning = false;
    });
  }

  Future<void> _forget(_Row row) async {
    final tries = <Uri>[
      if ((row.ip ?? '').isNotEmpty) Uri.parse('http://${row.ip}/apmode'),
      Uri.parse('http://${row.key}.local/apmode'),
      if ((row.ip ?? '').isNotEmpty) Uri.parse('http://${row.ip}/factory'),
      Uri.parse('http://${row.key}.local/factory'),
    ];
    for (final uri in tries) {
      try {
        await http.get(uri).timeout(const Duration(seconds: 3));
        break;
      } catch (_) {}
    }

    try {
      await _repository.forget(row.key);
    } catch (e) {
      debugPrint('Error eliminando dispositivo en Supabase: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dispositivo olvidado. En pocos segundos deberia encender su AP CASA-ESP_xxxx.',
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
                      final chipText = row.online ? 'Conectado' : 'Desconectado';

                      return ListTile(
                        leading: Icon(Icons.memory, color: chipColor),
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
                                deviceId: row.key,
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
}

class _Row {
  const _Row({
    required this.key,
    required this.title,
    required this.ip,
    required this.type,
    required this.online,
    required this.lastSeenAt,
  });

  final String key;
  final String title;
  final String? ip;
  final String type;
  final bool online;
  final DateTime lastSeenAt;
}

class _OnlineHit {
  const _OnlineHit({this.ip, this.type, this.name});

  final String? ip;
  final String? type;
  final String? name;
}





