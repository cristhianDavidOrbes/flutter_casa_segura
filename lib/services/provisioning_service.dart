import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_seguridad_en_casa/core/config/environment.dart';

class ProvisioningResult {
  const ProvisioningResult({required this.ok, this.payload, this.message});

  final bool ok;
  final Map<String, dynamic>? payload;
  final String? message;

  bool get hasPayload => payload != null && payload!.isNotEmpty;
}

/// Servicio para onboard del equipo vAa SoftAP.
class ProvisioningService {
  ProvisioningService();

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
    'device_key',
    'token',
    'access_token',
    'refresh_token',
    'supabase_key',
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

    // Android 13+: permiso especAfico para Wi-Fi cercano
    final nearby = Permission.nearbyWifiDevices;
    if (await nearby._isSupported) req.add(nearby);

    final statuses = await req.request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ---------- BASQUEDA SSID DEL EQUIPO ----------
  /// Escanea redes desde el **telAfono** y devuelve el primer SSID que
  /// comience por [apPrefix]. Requiere permisos de ubicaciA3n en Android.
  Future<String?> findDeviceAp({
    int attempts = 4,
    Duration delay = const Duration(milliseconds: 900),
  }) async {
    final ok = await _ensurePermissions();
    if (!ok) return null;

    for (int i = 0; i < attempts; i++) {
      // Nota: WiFiForIoTPlugin no tiene reemplazo directo; se acepta advertencia.
      // ignore: deprecated_member_use
      final list = await WiFiForIoTPlugin.loadWifiList();
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

  /// Determines whether the device access point remains visible during provisioning.
  /// Returns true when the SSID is found and false otherwise.
  Future<bool> isDeviceApVisible(
    String apSsid, {
    int attempts = 3,
    Duration delay = const Duration(milliseconds: 600),
  }) async {
    final ok = await _ensurePermissions();
    if (!ok) return false;

    final target = apSsid.trim();
    final treatAsPrefix = target.isEmpty;

    for (int i = 0; i < attempts; i++) {
      try {
        // ignore: deprecated_member_use
        final list = await WiFiForIoTPlugin.loadWifiList();
        for (final network in list) {
            final ssid = (network.ssid ?? '').trim();
            if (ssid.isEmpty) continue;
            if (treatAsPrefix &&
                (ssid.startsWith(apPrefix) || ssid.startsWith('CASA-ESP'))) {
              return true;
            }
            if (!treatAsPrefix && ssid == target) {
              return true;
            }
        }
      } catch (_) {
        // Ignora y reintenta en la siguiente iteracion.
      }
      if (i < attempts - 1) {
        await Future.delayed(delay + Duration(milliseconds: 120 * i));
      }
    }
    return false;
  }

  // ---------- CONEXIAN AL SOFTAP ----------
  /// Conecta el telAfono al AP del equipo.
  /// En tu firmware actual el AP es **abierto** (sin contraseAa).
  Future<bool> connectToDeviceAp(String ssid, {String apPassword = ''}) async {
    final ok = await _ensurePermissions();
    if (!ok) return false;

    try {
      await WiFiForIoTPlugin.disconnect();
    } catch (_) {}

    final success = await _connectToNetwork(
      ssid: ssid,
      password: apPassword.isNotEmpty ? apPassword : null,
      withInternet: false,
      securityCandidates: apPassword.isEmpty
          ? const [NetworkSecurity.NONE]
          : const [
              NetworkSecurity.WPA,
              NetworkSecurity.WEP,
              NetworkSecurity.NONE,
            ],
      timeout: const Duration(seconds: 20),
      joinOnce: true,
    );
    if (!success) return false;

    // Ruta trAfico por Wi-Fi (Android) para alcanzar 192.168.4.1
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
  /// Pide la lista de redes que ve **el equipo** (no el telAfono).
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
    String? apSsid,
  }) async {
    final alias = _sanitizeAlias(name);
    final detectedType = await _detectDeviceTypeFromSoftAp();
    final deviceType = _normalizeDeviceType(detectedType);
    final uri = Uri.parse('http://$apIp/provision');
    final userId = _supabase.auth.currentUser?.id;
    final normalizedApSsid = _normalizeSsid(apSsid);
    final normalizedHomeSsid = _normalizeSsid(ssid);

    _DeviceCredentials? credentials;
    bool credentialsFromFallback = false;
    ProvisioningResult? pendingError;
    bool wifiTemporarilyDisabled = false;
    bool connectedToInternetWifi = false;
    bool reconnectionOk = true;

    try {
      if (normalizedApSsid != null) {
        await _temporarilyLeaveDeviceAp(normalizedApSsid);
      } else {
        try {
          await WiFiForIoTPlugin.forceWifiUsage(false);
        } catch (_) {}
      }

      if (normalizedHomeSsid != null) {
        connectedToInternetWifi = await _connectToInternetWifi(
          normalizedHomeSsid,
          pass,
        );
      }

      if (!connectedToInternetWifi) {
        wifiTemporarilyDisabled = await _toggleWifi(false);
        try {
          await WiFiForIoTPlugin.forceWifiUsage(false);
        } catch (_) {}
      }

      try {
        credentials = await _createDeviceCredentials(
          alias: alias,
          type: deviceType,
        );
      } catch (e) {
        final fallbackId = Environment.deviceFallbackId;
        final fallbackKey = Environment.deviceFallbackKey;
        if (fallbackId != null &&
            fallbackId.isNotEmpty &&
            fallbackKey != null &&
            fallbackKey.isNotEmpty) {
          credentials = _DeviceCredentials(
            id: fallbackId,
            key: fallbackKey,
            name: alias,
            type: deviceType,
          );
          credentialsFromFallback = true;
        } else {
          debugPrint('[Provisioning] Error generando credenciales: $e');
          pendingError = ProvisioningResult(
            ok: false,
            message:
                'No se pudo registrar el dispositivo en Supabase. '
                'Detalle: ${_describeError(e)}',
          );
        }
      }
    } finally {
      if (wifiTemporarilyDisabled) {
        await _toggleWifi(true);
        await Future.delayed(const Duration(milliseconds: 900));
      }

      if (normalizedApSsid != null) {
        reconnectionOk = await _ensureConnectedToDeviceAp(normalizedApSsid);
      } else if (!wifiTemporarilyDisabled && !connectedToInternetWifi) {
        // Si no habia internet via Wi-Fi y no se desconecto el AP, asegA?rate
        // de liberar la ruta para datos celulares.
        try {
          await WiFiForIoTPlugin.forceWifiUsage(false);
        } catch (_) {}
      }
    }

    if (!reconnectionOk && normalizedApSsid != null) {
      final apLabel = normalizedApSsid;
      return ProvisioningResult(
        ok: false,
        message:
            'No se pudo reconectar al AP del dispositivo ($apLabel). '
            'Conectate manualmente a ese AP y vuelve a intentar.',
      );
    } else {
      try {
        await WiFiForIoTPlugin.forceWifiUsage(true);
      } catch (_) {}
    }

    if (pendingError != null) {
      return pendingError;
    }

    if (credentials == null || !credentials.isValid) {
      return const ProvisioningResult(
        ok: false,
        message:
            'Las credenciales del dispositivo no se generaron correctamente. '
            'Reintenta la vinculacion.',
      );
    }

    final supabaseUrl = Environment.supabaseUrl.trim();
    final supabaseKey = Environment.supabaseAnonKey.trim();
    if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
      return const ProvisioningResult(
        ok: false,
        message:
            'La configuracion de Supabase en la aplicacion es invalida. '
            'Verifica tu archivo .env.',
      );
    }

    final payload = _buildProvisionPayload(
      ssid: ssid,
      pass: pass,
      credentials: credentials,
      supabaseUrl: supabaseUrl,
      supabaseKey: supabaseKey,
      userId: userId,
      usedFallbackCredentials: credentialsFromFallback,
    );
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

      return ProvisioningResult(ok: ok, payload: payloadMap, message: message);
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

  Map<String, dynamic> _buildProvisionPayload({
    required String ssid,
    required String pass,
    required _DeviceCredentials credentials,
    required String supabaseUrl,
    required String supabaseKey,
    String? userId,
    bool usedFallbackCredentials = false,
  }) {
    final payload = <String, dynamic>{
      'ssid': ssid,
      'pass': pass,
      'name': credentials.name,
      'device_id': credentials.id,
      'device_key': credentials.key,
      'device_type': credentials.type,
      'type': credentials.type,
      'supabase_url': supabaseUrl,
      'supabase_key': supabaseKey,
    };

    final trimmedUser = userId?.trim();
    if (trimmedUser != null && trimmedUser.isNotEmpty) {
      payload['user_id'] = trimmedUser;
    }

    if (usedFallbackCredentials) {
      payload['used_fallback'] = true;
    }
    return payload;
  }

  String? _normalizeSsid(String? value) {
    if (value == null) return null;
    final sanitized = value.replaceAll('"', '').trim();
    if (sanitized.isEmpty ||
        sanitized == '<unknown ssid>' ||
        sanitized.toLowerCase() == 'unknown ssid') {
      return null;
    }
    return sanitized;
  }

  Future<String?> _currentSsid() async {
    try {
      final raw = await WiFiForIoTPlugin.getSSID();
      return _normalizeSsid(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _connectToInternetWifi(String ssid, String pass) async {
    if (ssid.isEmpty) return false;

    try {
      await WiFiForIoTPlugin.setEnabled(true);
    } catch (_) {}

    final sanitizedPass = pass.trim();
    final success = await _connectToNetwork(
      ssid: ssid,
      password: sanitizedPass.isNotEmpty ? sanitizedPass : null,
      withInternet: true,
      securityCandidates: sanitizedPass.isEmpty
          ? const [NetworkSecurity.NONE]
          : const [
              NetworkSecurity.WPA,
              NetworkSecurity.WEP,
              NetworkSecurity.NONE,
            ],
      timeout: const Duration(seconds: 30),
      joinOnce: false,
    );
    if (!success) return false;

    try {
      await WiFiForIoTPlugin.forceWifiUsage(false);
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 350));
    return true;
  }

  Future<bool> _temporarilyLeaveDeviceAp(String ssid) async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(false);
    } catch (_) {}

    bool disconnected = false;
    try {
      disconnected = await WiFiForIoTPlugin.disconnect();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 350));
    if (!disconnected) {
      final current = await _currentSsid();
      disconnected = current != ssid;
    }
    return disconnected;
  }

  Future<bool> _ensureConnectedToDeviceAp(String ssid) async {
    const attempts = 4;
    for (int attempt = 0; attempt < attempts; attempt++) {
      final current = await _currentSsid();
      if (current == ssid) {
        try {
          await WiFiForIoTPlugin.forceWifiUsage(true);
        } catch (_) {}
        final reachable = await _probeAp();
        if (reachable) return true;
      }

      final connected = await _connectToNetwork(
        ssid: ssid,
        password: null,
        withInternet: false,
        securityCandidates: const [NetworkSecurity.NONE],
        timeout: const Duration(seconds: 20),
        joinOnce: true,
      );
      if (!connected) {
        await Future.delayed(const Duration(milliseconds: 700));
        continue;
      }

      try {
        await WiFiForIoTPlugin.forceWifiUsage(true);
      } catch (_) {}
      final reachable = await _probeAp();
      if (reachable) return true;
      await Future.delayed(const Duration(milliseconds: 700));
    }
    return false;
  }

  Future<bool> _connectToNetwork({
    required String ssid,
    String? password,
    required bool withInternet,
    List<NetworkSecurity>? securityCandidates,
    Duration timeout = const Duration(seconds: 25),
    bool joinOnce = true,
  }) async {
    final normalizedSsid = ssid.trim();
    if (normalizedSsid.isEmpty) return false;

    final already = await _currentSsid();
    if (already == normalizedSsid) return true;

    final candidates =
        securityCandidates ??
        (password != null && password.isNotEmpty
            ? const [
                NetworkSecurity.WPA,
                NetworkSecurity.WEP,
                NetworkSecurity.NONE,
              ]
            : const [NetworkSecurity.NONE]);

    for (final security in candidates) {
      try {
        final ok = await WiFiForIoTPlugin.connect(
          normalizedSsid,
          password: password,
          security: security,
          joinOnce: joinOnce,
          withInternet: withInternet,
          timeoutInSeconds: timeout.inSeconds,
        );
        if (!ok) continue;
      } catch (_) {
        continue;
      }

      final connected = await _waitForSsid(
        normalizedSsid,
        maxTries: 14,
        interval: const Duration(milliseconds: 600),
      );
      if (connected) {
        // Da un pequeño margen para que el sistema obtenga acceso real a Internet.
        await Future.delayed(const Duration(seconds: 2));
        return true;
      }
    }

    return false;
  }

  Future<bool> _toggleWifi(bool enable) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      await WiFiForIoTPlugin.setEnabled(enable);
    } catch (_) {}

    if (!enable) {
      try {
        await WiFiForIoTPlugin.disconnect();
      } catch (_) {}
    }

    await Future.delayed(
      enable
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 600),
    );

    try {
      final state = await WiFiForIoTPlugin.isEnabled();
      return state == enable;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _waitForSsid(
    String ssid, {
    int maxTries = 8,
    Duration interval = const Duration(milliseconds: 450),
  }) async {
    for (int i = 0; i < maxTries; i++) {
      final current = await _currentSsid();
      if (current == ssid) return true;
      await Future.delayed(interval);
    }
    return false;
  }

  String _describeError(Object error) {
    if (error is PostgrestException) {
      final codeSuffix = error.code != null ? ' (codigo ${error.code})' : '';
      final message = error.message.trim();
      return message.isNotEmpty
          ? '$message$codeSuffix'
          : 'Supabase devolvio un error$codeSuffix';
    }
    if (error is TimeoutException) {
      final duration = error.duration;
      final seconds = duration != null ? duration.inSeconds : 0;
      return 'Tiempo de espera agotado (${seconds}s)';
    }
    return error.toString();
  }

  /// Desactiva el aroutinga por Wi-Fi en Android (vuelve a normal).
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

  String _sanitizeAlias(String? name) {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 'Dispositivo $stamp';
  }

  Future<String?> _detectDeviceTypeFromSoftAp() async {
    try {
      final response = await http
          .get(Uri.parse('http://$apIp/info'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      final decoded = _decodeJsonMap(response.body);
      final typeRaw = decoded?['type'];
      if (typeRaw is String && typeRaw.trim().isNotEmpty) {
        return _normalizeDeviceType(typeRaw);
      }
    } catch (_) {}
    return null;
  }

  String _normalizeDeviceType(String? value) {
    if (value == null) return 'esp32';
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return 'esp32';
    if (normalized.contains('servo')) return 'servo';
    if (normalized.contains('cam')) return 'esp32cam';
    if (normalized.contains('esp32')) return 'esp32';
    if (normalized.contains('esp8266')) return 'esp8266';
    if (normalized.contains('detector')) return 'esp32';
    return normalized;
  }

  Future<_DeviceCredentials> _createDeviceCredentials({
    required String alias,
    required String type,
  }) async {
    String workingAlias = alias;
    bool routingReleased = false;

    try {
      await WiFiForIoTPlugin.forceWifiUsage(false);
      routingReleased = true;
    } catch (_) {}

    try {
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final response = await _supabase.rpc(
            'generate_device',
            params: {'_name': workingAlias, '_type': type},
          );

          final map = _normalizeSupabaseResponse(response);
          final id = (map?['id'] as String?)?.trim();
          final key = (map?['device_key'] as String?)?.trim();
          final resolvedName = (map?['name'] as String?)?.trim();
          final resolvedType = (map?['type'] as String?)?.trim();

          if (id == null || id.isEmpty || key == null || key.isEmpty) {
            throw StateError(
              'Supabase no devolvio credenciales del dispositivo.',
            );
          }

          return _DeviceCredentials(
            id: id,
            key: key,
            name: resolvedName?.isNotEmpty == true
                ? resolvedName!
                : workingAlias,
            type: resolvedType?.isNotEmpty == true ? resolvedType! : type,
          );
        } on PostgrestException catch (e) {
          if (e.code == '23505' && attempt < 2) {
            workingAlias =
                '$alias-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
            continue;
          }
          rethrow;
        }
      }
      throw StateError(
        'No se pudieron generar credenciales unicas para el dispositivo.',
      );
    } finally {
      if (routingReleased) {
        try {
          await WiFiForIoTPlugin.forceWifiUsage(true);
        } catch (_) {}
      }
    }
  }

  Map<String, dynamic>? _normalizeSupabaseResponse(dynamic response) {
    if (response is List && response.isNotEmpty) {
      final first = response.first;
      if (first is Map) return _stringKeyedMap(first);
    } else if (response is Map) {
      return _stringKeyedMap(response);
    }
    return null;
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
      } else if (const {
        'ok',
        'true',
        'success',
        '1',
        'yes',
        'done',
      }.contains(normalized)) {
        return true;
      } else if (const {
        'false',
        'error',
        'fail',
        'ko',
        '0',
        'no',
      }.contains(normalized)) {
        return false;
      }
    }

    final status = data['status'];
    if (status is String) {
      final normalized = status.trim().toLowerCase();
      if (const {
        'ok',
        'success',
        'done',
        'ready',
        'saved',
      }.contains(normalized)) {
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
      sanitized.removeWhere(
        (key, _) => _sensitiveKeys.contains(key.toLowerCase()),
      );
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

class _DeviceCredentials {
  _DeviceCredentials({
    required String id,
    required String key,
    required String name,
    required String type,
  }) : id = id.trim(),
       key = key.trim(),
       name = name.trim(),
       type = type.trim();

  final String id;
  final String key;
  final String name;
  final String type;

  bool get isValid =>
      id.isNotEmpty && key.isNotEmpty && name.isNotEmpty && type.isNotEmpty;
}

// Helper: detectar si el permiso existe en la versiA3n actual del SO.
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


