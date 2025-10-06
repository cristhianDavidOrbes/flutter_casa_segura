// lib/screens/provisioning_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/repositories/device_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

import '../services/provisioning_service.dart';
import '../services/lan_discovery_service.dart';
import 'devices_page.dart';

class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  final prov = ProvisioningService();
  final DeviceRepository _deviceRepository = DeviceRepository.instance;

  bool _busy = false;

  String? _apSsid; // SSID del AP del equipo (CASA-ESP_xxxx)
  List<String> _phoneNets = const []; // Redes visibles por el teléfono
  String? _selectedSsid; // Red doméstica elegida
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(); // alias opcional del equipo

  // NUEVO: control para mostrar/ocultar contraseña
  bool _obscurePass = true;

  @override
  void dispose() {
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // Paso 1: buscar el AP del equipo
  Future<void> _findAp() async {
    setState(() => _busy = true);
    final ssid = await prov.findDeviceAp();
    setState(() {
      _apSsid = ssid;
      _busy = false;
    });

    if (ssid == null) {
      Get.snackbar(
        'Provisioning',
        'No se encontró el AP del equipo (prefijo ${ProvisioningService.apPrefix}).',
        snackPosition: SnackPosition.BOTTOM,
      );
    } else {
      Get.snackbar(
        'Provisioning',
        'Encontrado AP: $ssid',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // Paso 2: conectarse al AP del equipo
  Future<void> _connectToDeviceAp() async {
    final ssid = _apSsid;
    if (ssid == null) {
      Get.snackbar(
        'Provisioning',
        'Primero busca el AP del equipo.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() => _busy = true);
    final ok = await prov.connectToDeviceAp(ssid);
    setState(() => _busy = false);

    if (!ok) {
      Get.snackbar(
        'Provisioning',
        'No se pudo conectar al AP $ssid',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    Get.snackbar(
      'Provisioning',
      'Conectado al AP $ssid',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  // Escanear redes visibles por el TELÉFONO (para elegir la del lugar)
  Future<void> _scanPhoneNets() async {
    final status = await Permission.locationWhenInUse.request();
    if (status != PermissionStatus.granted) {
      Get.snackbar(
        'Provisioning',
        'Permiso de ubicación requerido para escanear Wi-Fi.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      FocusScope.of(context).unfocus();
      setState(() => _busy = true);

      final List<WifiNetwork>? list = await WiFiForIoTPlugin.loadWifiList();
      final names = <String>{};
      for (final w in (list ?? const <WifiNetwork>[])) {
        final s = (w.ssid ?? '').trim();
        if (s.isNotEmpty) names.add(s);
      }
      final nets = names.toList()..sort();
      setState(() {
        _phoneNets = nets;
        if (nets.isNotEmpty &&
            (_selectedSsid == null || _selectedSsid!.isEmpty)) {
          _selectedSsid = nets.first;
        }
      });
    } catch (_) {
      Get.snackbar(
        'Provisioning',
        'No se pudo escanear Wi-Fi desde el teléfono.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  // Espera a que el dispositivo reaparezca en LAN (mDNS)
  Future<DiscoveredDevice?> _waitForDevice({String? alias}) async {
    final discovery = LanDiscoveryService();
    final target = alias?.trim();
    final targetLower = (target != null && target.isNotEmpty)
        ? target.toLowerCase()
        : null;

    await Future.delayed(const Duration(seconds: 2));

    const attempts = 12;
    for (int i = 0; i < attempts; i++) {
      final list = await discovery.discover(
        timeout: const Duration(seconds: 4),
      );
      if (list.isNotEmpty) {
        if (targetLower != null) {
          for (final d in list) {
            if (d.name.toLowerCase() == targetLower) {
              return d;
            }
          }
        } else {
          return list.first;
        }
      }
      if (i < attempts - 1) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    return null;
  }

  // Paso 3

  // Paso 3: enviar credenciales al equipo
  Future<void> _sendProvision() async {
    if (_selectedSsid == null ||
        _selectedSsid!.isEmpty ||
        _passCtrl.text.isEmpty) {
      Get.snackbar(
        'Provisioning',
        'Selecciona una red e introduce la contrase?a.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _busy = true);
    final aliasInput = _nameCtrl.text.trim();
    final result = await prov.sendProvision(
      ssid: _selectedSsid!.trim(),
      pass: _passCtrl.text.trim(),
      name: aliasInput.isEmpty ? null : aliasInput,
    );
    setState(() => _busy = false);

    final bool accepted = result.ok || _looksLikeProvisionAccepted(result);
    if (!accepted) {
      final failureMessage = _resolveFailureMessage(result);
      Get.snackbar(
        'Provisioning',
        failureMessage,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    final successMessage = _resolveSuccessMessage(result);
    Get.snackbar(
      'Provisioning',
      successMessage,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 4),
    );

    await prov.releaseWifiRouting();
    await Future.delayed(const Duration(seconds: 2));
    await _showProvisionAck(result, headline: successMessage);

    // Di?logo de espera mientras reaparece por mDNS
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 76,
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(
                child: Text('Esperando que el equipo aparezca en la red...'),
              ),
            ],
          ),
        ),
      ),
    );

    final alias = aliasInput.isEmpty ? null : aliasInput;
    final dev = await _waitForDevice(alias: alias);
    if (mounted) Navigator.of(context).pop();

    if (dev != null) {
      try {
        await _deviceRepository.upsertDiscoveredDevice(dev, alias: alias);
      } catch (e) {
        Get.log('Error guardando dispositivo en Supabase: ${e.toString()}');
      }

      Get.snackbar(
        'Provisioning',
        'Listo! Conectado como ${dev.name} (${dev.ip}).',
        snackPosition: SnackPosition.BOTTOM,
      );
      Get.off(() => const DevicesPage());
    } else {
      final synthetic = (result.payload != null && result.payload!.isNotEmpty)
          ? _deviceFromPayload(result.payload!, alias: alias)
          : null;

      if (synthetic != null) {
        try {
          await _deviceRepository.upsertDiscoveredDevice(
            synthetic,
            alias: alias ?? (synthetic.name.isNotEmpty ? synthetic.name : null),
          );
        } catch (e) {
          Get.log(
            'Error guardando dispositivo en Supabase (payload): ${e.toString()}',
          );
        }

        Get.snackbar(
          'Provisioning',
          'Dispositivo registrado. Puede tardar unos segundos en verse como conectado.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
        Get.off(() => const DevicesPage());
      } else {
        Get.snackbar(
          'Provisioning',
          'Credenciales enviadas. No pudimos confirmar aun; revisa en "Dispositivos".',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  bool _looksLikeProvisionAccepted(ProvisioningResult result) {
    if (result.hasPayload) return true;
    final message = result.message?.toLowerCase() ?? '';
    if (message.isEmpty) return false;

    const hints = [
      'abort',
      'ap closed',
      'ap_closed',
      'salir del ap',
      'credentials saved',
      'credenciales guardadas',
      'connecting',
      'conectando',
      'success',
      'ok',
    ];
    for (final hint in hints) {
      if (message.contains(hint)) return true;
    }
    return false;
  }

  String _resolveFailureMessage(ProvisioningResult result) {
    final message = result.message?.trim();
    if (message == null || message.isEmpty) {
      return 'Fallo enviando credenciales al equipo.';
    }
    return message;
  }

  String _resolveSuccessMessage(ProvisioningResult result) {
    final message = result.message?.trim();
    if (message == null || message.isEmpty) {
      return 'Credenciales enviadas. El equipo se esta conectando a tu Wi-Fi...';
    }
    final lower = message.toLowerCase();
    if (lower.contains('abort') ||
        lower.contains('ap closed') ||
        lower.contains('ap_closed')) {
      return 'Credenciales enviadas. El equipo se reiniciara y saldra del modo AP.';
    }
    if (lower.contains('success') ||
        lower.contains('ok') ||
        lower.contains('conectado') ||
        lower.contains('connected')) {
      return message;
    }
    return 'Credenciales enviadas. El equipo se esta conectando a tu Wi-Fi...';
  }

  DiscoveredDevice? _deviceFromPayload(
    Map<String, dynamic> payload, {
    String? alias,
  }) {
    if (payload.isEmpty) return null;

    final normalized = <String, dynamic>{};
    payload.forEach((key, value) {
      normalized[key.toString().toLowerCase()] = value;
    });

    String? pickString(List<String> keys) {
      for (final key in keys) {
        final value = normalized[key];
        if (value == null) continue;
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is num) return value.toString();
      }
      return null;
    }

    int? pickInt(List<String> keys) {
      for (final key in keys) {
        final value = normalized[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    final host = pickString(['host', 'hostname', 'mdns_host']);
    final ip = pickString([
      'ip',
      'ipv4',
      'address',
      'addr',
      'lan_ip',
      'local_ip',
    ]);
    final port = pickInt(['port', 'http_port', 'tcp_port']) ?? 80;
    final deviceId = pickString([
      'device_key',
      'key',
      'id',
      'chip',
      'chip_id',
      'identifier',
    ]);
    final type = pickString(['type', 'device_type', 'kind', 'model']) ?? 'esp';
    final nameFromPayload = pickString([
      'alias',
      'name',
      'device_name',
      'label',
    ]);

    final resolvedName = (alias != null && alias.trim().isNotEmpty)
        ? alias.trim()
        : (nameFromPayload?.trim().isNotEmpty == true
              ? nameFromPayload!.trim()
              : (host?.trim().isNotEmpty == true
                    ? host!.trim()
                    : (deviceId?.trim().isNotEmpty == true
                          ? deviceId!.trim()
                          : 'Dispositivo')));

    final syntheticId = deviceId?.trim().isNotEmpty == true
        ? deviceId!.trim()
        : (host?.trim().isNotEmpty == true
              ? host!.trim()
              : (ip?.trim().isNotEmpty == true ? '${ip!.trim()}:$port' : null));

    if (syntheticId == null) return null;

    return DiscoveredDevice(
      id: syntheticId,
      name: resolvedName,
      ip: ip?.trim() ?? '',
      port: port,
      type: type.trim().isNotEmpty ? type.trim() : 'esp',
      deviceId: deviceId?.trim().isNotEmpty == true ? deviceId!.trim() : null,
      host: host?.trim().isNotEmpty == true ? host!.trim() : null,
    );
  }

  Future<void> _showProvisionAck(
    ProvisioningResult result, {
    String? headline,
  }) async {
    if (!mounted) return;
    final data = result.payload;
    if (data == null || data.isEmpty) return;

    final entries =
        data.entries.map((entry) => MapEntry(entry.key, entry.value)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    final message = result.message?.trim();
    final showMessage =
        message != null &&
        message.isNotEmpty &&
        (headline == null || headline.trim() != message);

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Datos del dispositivo'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMessage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      message!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ...entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.value == null ? '-' : entry.value.toString(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Provisionar (SoftAP)'),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // BLOQUE 1: Buscar AP del equipo
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '1) Buscar AP del equipo (CASA-ESP_XXXX)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _apSsid == null ? 'Sin detectar' : _apSsid!,
                              style: TextStyle(
                                color: _apSsid == null
                                    ? cs.outline
                                    : cs.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _busy ? null : _findAp,
                            icon: const Icon(Icons.wifi_find),
                            label: const Text('Buscar'),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      const Text(
                        '2) Conectarse al AP del equipo',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _apSsid == null
                                  ? 'Ningún AP'
                                  : 'Conectar a: $_apSsid',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _apSsid == null
                                    ? cs.outline
                                    : cs.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: (_busy || _apSsid == null)
                                ? null
                                : _connectToDeviceAp,
                            icon: const Icon(Icons.wifi),
                            label: const Text('Conectar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // BLOQUE 2: Elegir red del lugar y enviar credenciales
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '3) Elegir red Wi-Fi del lugar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),

                      // Ambos Expanded para evitar overflow
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedSsid,
                              isExpanded: true,
                              items: _phoneNets
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedSsid = v),
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'SSID',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _scanPhoneNets,
                              icon: const Icon(Icons.refresh),
                              label: const Text(
                                'Escanear',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscurePass, // ← NUEVO
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          border: const OutlineInputBorder(),
                          // ← NUEVO: botón "ojo"
                          suffixIcon: IconButton(
                            tooltip: _obscurePass
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
                            icon: Icon(
                              _obscurePass
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePass = !_obscurePass),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                      ),

                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Alias del equipo (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _sendProvision,
                        icon: const Icon(Icons.send),
                        label: const Text('Enviar credenciales'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Tip: si no ves redes, activa Ubicación y concede permisos de Wi-Fi en Android.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 24),
            ],
          ),

          if (_busy)
            Container(
              color: Colors.black.withOpacity(.15),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
