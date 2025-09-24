// lib/services/provisioning_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

/// Servicio para onboard del equipo vía SoftAP.
class ProvisioningService {
  /// Prefijo del SSID que emite el equipo en modo AP.
  static const String apPrefix = 'CASA-ESP_';

  /// IP fija del SoftAP (servidor HTTP del equipo).
  static const String apIp = '192.168.4.1';

  // ---------- PERMISOS ----------
  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    final req = <Permission>[Permission.locationWhenInUse, Permission.location];

    // Android 13+: permiso específico para Wi-Fi cercano
    final nearby = Permission.nearbyWifiDevices;
    if (await nearby._isSupported) req.add(nearby);

    final statuses = await req.request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ---------- BÚSQUEDA SSID DEL EQUIPO ----------
  /// Escanea redes desde el **teléfono** y devuelve el primer SSID que
  /// comience por [apPrefix]. Requiere permisos de ubicación en Android.
  Future<String?> findDeviceAp() async {
    final ok = await _ensurePermissions();
    if (!ok) return null;

    // Nota: loadWifiList está “deprecated”, pero para identificar el SSID
    // del equipo es la forma práctica. Si quieres evitar el warning,
    // se puede migrar a wifi_scan. Para ahora, funciona.
    final list = await WiFiForIoTPlugin.loadWifiList() ?? <WifiNetwork>[];
    for (final w in list) {
      final ssid = (w.ssid ?? '').trim();
      if (ssid.startsWith(apPrefix)) return ssid;
    }
    return null;
  }

  // ---------- CONEXIÓN AL SOFTAP ----------
  /// Conecta el teléfono al AP del equipo.
  /// En tu firmware actual el AP es **abierto** (sin contraseña).
  Future<bool> connectToDeviceAp(String ssid, {String apPassword = ''}) async {
    final ok = await _ensurePermissions();
    if (!ok) return false;

    try {
      await WiFiForIoTPlugin.disconnect();
    } catch (_) {}

    bool success = false;

    // Usa findAndConnect; para AP abierto pasa password = ''.
    try {
      success = await WiFiForIoTPlugin.findAndConnect(
        ssid,
        password: apPassword,
        joinOnce: true,
        withInternet: false, // MUY IMPORTANTE: AP no tiene internet
      );
    } catch (_) {
      success = false;
    }

    // Poll corto hasta que el SSID activo sea el del AP
    for (int i = 0; i < 10 && !success; i++) {
      final current = await WiFiForIoTPlugin.getSSID();
      if ((current ?? '') == ssid) {
        success = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 600));
    }
    if (!success) return false;

    // Ruta tráfico por Wi-Fi (Android) para alcanzar 192.168.4.1
    try {
      await WiFiForIoTPlugin.forceWifiUsage(true);
    } catch (_) {}

    // Verifica que el HTTP del equipo responda
    final reachable = await _probeAp();
    if (!reachable) {
      try {
        await WiFiForIoTPlugin.forceWifiUsage(false);
      } catch (_) {}
      return false;
    }
    return true;
  }

  // ---------- UTILIDADES HTTP EN EL AP ----------
  /// Pide la lista de redes que ve **el equipo** (no el teléfono).
  /// Endpoint del firmware: GET http://192.168.4.1/nets
  Future<List<String>> fetchNets() async {
    try {
      final uri = Uri.parse('http://$apIp/nets');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body);
      // El firmware devuelve lista de objetos {ssid, rssi}. Normalizamos.
      if (data is List) {
        final out = <String>[];
        for (final e in data) {
          if (e is Map && e['ssid'] is String) {
            final s = (e['ssid'] as String).trim();
            if (s.isNotEmpty) out.add(s);
          } else if (e is String) {
            out.add(e);
          }
        }
        // sin duplicados
        return out.toSet().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Envía credenciales al equipo (POST /provision) => {"ok":true/false}
  Future<bool> sendProvision({
    required String ssid,
    required String pass,
    String? name,
  }) async {
    final uri = Uri.parse('http://$apIp/provision');
    final body = jsonEncode({
      'ssid': ssid,
      'pass': pass,
      if (name != null && name.isNotEmpty) 'name': name,
    });

    try {
      final res = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return false;

      final data = jsonDecode(res.body);
      if (data is Map && (data['ok'] == true)) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Desactiva el “routing” por Wi-Fi en Android (vuelve a normal).
  Future<void> releaseWifiRouting() async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(false);
    } catch (_) {}
  }

  Future<void> disconnectFromAp() async {
    try {
      await WiFiForIoTPlugin.disconnect();
    } catch (_) {}
    await releaseWifiRouting();
  }

  // ---------- PRIVADO ----------
  Future<bool> _probeAp() async {
    try {
      final res = await http
          .get(Uri.parse('http://$apIp/'))
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// Helper: detectar si el permiso existe en la versión actual del SO.
extension on Permission {
  Future<bool> get _isSupported async {
    try {
      await status; // si no existe, lanza
      return true;
    } catch (_) {
      return false;
    }
  }
}
