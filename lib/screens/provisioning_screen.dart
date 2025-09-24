// lib/screens/provisioning_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/theme_toggle_button.dart';
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
    for (int i = 0; i < 6; i++) {
      final list = await discovery.discover(
        timeout: const Duration(seconds: 3),
      );
      if (list.isNotEmpty) {
        if (alias != null && alias.trim().isNotEmpty) {
          for (final d in list) {
            if (d.name.toLowerCase() == alias.trim().toLowerCase()) {
              return d;
            }
          }
        } else {
          return list.first;
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  // Paso 3: enviar credenciales al equipo
  Future<void> _sendProvision() async {
    if (_selectedSsid == null ||
        _selectedSsid!.isEmpty ||
        _passCtrl.text.isEmpty) {
      Get.snackbar(
        'Provisioning',
        'Selecciona una red e introduce la contraseña.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _busy = true);
    final ok = await prov.sendProvision(
      ssid: _selectedSsid!.trim(),
      pass: _passCtrl.text.trim(),
      name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
    );
    setState(() => _busy = false);

    if (!ok) {
      Get.snackbar(
        'Provisioning',
        'Fallo enviando credenciales al equipo.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    Get.snackbar(
      'Provisioning',
      'Credenciales enviadas ✅. El equipo se está conectando a tu Wi-Fi…',
      snackPosition: SnackPosition.BOTTOM,
    );

    await prov.releaseWifiRouting();

    // Diálogo de espera mientras reaparece por mDNS
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 72,
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(
                child: Text('Esperando que el equipo aparezca en la red…'),
              ),
            ],
          ),
        ),
      ),
    );

    final dev = await _waitForDevice(alias: _nameCtrl.text.trim());
    if (mounted) Navigator.of(context).pop(); // cierra diálogo

    if (dev != null) {
      Get.snackbar(
        'Provisioning',
        '¡Listo! Conectado como ${dev.name} (${dev.ip}).',
        snackPosition: SnackPosition.BOTTOM,
      );
      Get.off(() => const DevicesPage());
    } else {
      Get.snackbar(
        'Provisioning',
        'Credenciales enviadas. No pudimos confirmar aún; revisa en “Dispositivos”.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
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
