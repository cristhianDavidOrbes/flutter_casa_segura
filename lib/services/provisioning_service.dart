// lib/services/provisioning_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

import 'package:supabase_flutter/supabase_flutter.dart';


class ProvisioningResult {
  const ProvisioningResult({
    required this.ok,
    this.payload,
    this.message,
  });

  final bool ok;
  final Map<String, dynamic>? payload;
  final String? message;

  bool get hasPayload => payload != null && payload!.isNotEmpty;
}

/// Servicio para onboard del equipo vía SoftAP.
class ProvisioningService {

  static const Duration _preProvisionDelay = Duration(milliseconds: 450);
  static const Duration _postProvisionDelay = Duration(milliseconds: 750);

  static const Set<String> _ignoredMessageKeys = {
    'ok',
    'message',
    'msg',
    'error',
    'status',
  };

  static const Set<String> _sensitiveKeys = {
    'pass',
    'password',
    'ssid',
    'user_id',
    'token',
    'access_token',
    'refresh_token',
  };

  /// Prefijo del SSID que emite el equipo en modo AP.
  static const String apPrefix = 'CASA-ESP_';

  /// IP fija del SoftAP (servidor HTTP del equipo).
  static const String apIp = '192.168.4.1';

  final SupabaseClient _supabase = Supabase.instance.client;

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
  Future<String?> findDeviceAp({int attempts = 4, Duration delay = const Duration(milliseconds: 900)}) async {
    final ok = await _ensurePermissions();
    if (!ok) return null;

    for (int i = 0; i < attempts; i++) {
      // Nota: loadWifiList est? ?deprecated?, pero para identificar el SSID
      // del equipo es la forma pr?ctica. Si quieres evitar el warning,
      // se puede migrar a wifi_scan. Para ahora, funciona.
      final list = await WiFiForIoTPlugin.loadWifiList() ?? <WifiNetwork>[];
      for (final w in list) {
        final ssid = (w.ssid ?? '').trim();
        if (ssid.startsWith(apPrefix)) return ssid;
      }
      if (i < attempts - 1) {
        await Future.delayed(delay + Duration(milliseconds: 150 * i));
      }
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



  /// Env?a credenciales al equipo (POST /provision) y devuelve el resultado.
  Future<ProvisioningResult> sendProvision({
    required String ssid,
    required String pass,
    String? name,
  }) async {
    final uri = Uri.parse('http://$apIp/provision');
    final userId = _supabase.auth.currentUser?.id;

    final payload = <String, dynamic>{
      'ssid': ssid,
      'pass': pass,
      if (name != null && name.isNotEmpty) 'name': name,
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
    };
    final body = jsonEncode(payload);

    try {
      await Future.delayed(_preProvisionDelay);
      final res = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 8));

      await Future.delayed(_postProvisionDelay);

      if (res.statusCode != 200) {
        final reason = res.reasonPhrase;
        final detail = reason != null && reason.isNotEmpty ? ': $reason' : '';
        return ProvisioningResult(
          ok: false,
          message: 'HTTP ${res.statusCode}$detail',
        );
      }

      final data = _decodeJsonMap(res.body);
      final ok = _isSuccess(data);
      final message = data != null ? _extractMessage(data) : null;
      final payloadMap = data != null ? _extractPayload(data) : null;

      return ProvisioningResult(
        ok: ok,
        payload: payloadMap,
        message: message,
      );
    } on TimeoutException {
      return const ProvisioningResult(
        ok: false,
        message: 'Tiempo de espera agotado al contactar al equipo.',
      );
    } catch (e) {
      return ProvisioningResult(
        ok: false,
        message: 'Error enviando credenciales al equipo: ${e.toString()}',
      );
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


  Map<String, dynamic>? _decodeJsonMap(String source) {
    if (source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return _stringKeyedMap(decoded);
      }
    } catch (_) {}
    return null;
  }

  String? _extractMessage(Map<String, dynamic> data) {
    for (final key in const ['message', 'msg', 'error', 'detail', 'reason']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  bool _isSuccess(Map<String, dynamic>? data) {
    if (data == null) return true;

    final okField = data['ok'];
    if (okField is bool) return okField;
    if (okField is num) return okField != 0;
    if (okField is String) {
      final normalized = okField.trim().toLowerCase();
      if (normalized.isEmpty) {
        // continue checks
      } else if (const {'ok', 'true', 'success', '1', 'yes', 'done'}.contains(normalized)) {
        return true;
      } else if (const {'false', 'error', 'fail', 'ko', '0', 'no'}.contains(normalized)) {
        return false;
      }
    }

    final status = data['status'];
    if (status is String) {
      final normalized = status.trim().toLowerCase();
      if (const {'ok', 'success', 'done', 'ready', 'saved'}.contains(normalized)) {
        return true;
      }
      if (const {'error', 'fail', 'failed'}.contains(normalized)) {
        return false;
      }
    }

    final errorField = data['error'];
    if (errorField is bool) return !errorField;
    if (errorField is String && errorField.trim().isNotEmpty) {
      return false;
    }

    return true;
  }

  Map<String, dynamic>? _extractPayload(Map<String, dynamic> data) {
    final dynamic explicit = data['device'] ?? data['data'] ?? data['info'];
    if (explicit is Map) {
      final sanitized = _stringKeyedMap(explicit);
      sanitized.removeWhere((key, _) => _sensitiveKeys.contains(key.toLowerCase()));
      return sanitized.isEmpty ? null : sanitized;
    }

    final filtered = <String, dynamic>{};
    data.forEach((key, value) {
      final lower = key.toLowerCase();
      if (_ignoredMessageKeys.contains(lower)) {
        return;
      }
      if (_sensitiveKeys.contains(lower)) {
        return;
      }
      filtered[key] = value;
    });

    return filtered.isEmpty ? null : filtered;
  }

  Map<String, dynamic> _stringKeyedMap(Map input) {
    final map = <String, dynamic>{};
    input.forEach((key, value) {
      map[key.toString()] = value;
    });
    return map;
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
