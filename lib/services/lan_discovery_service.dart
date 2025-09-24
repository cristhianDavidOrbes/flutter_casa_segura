// lib/services/lan_discovery_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// Dispositivo anunciado por mDNS como _casa._tcp.local
class DiscoveredDevice {
  final String id; // ip:port (ID de sesión de descubrimiento)
  final String name; // TXT 'name' (alias humano)
  final String ip; // IPv4
  final int port; // SRV port
  final String type; // TXT 'type' (esp32/esp8266/esp32cam...)
  final String? deviceId; // TXT 'id' (chip-id HEX) -> clave estable en la DB
  final String? host; // TXT 'host' (hostname único mDNS)

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.type,
    this.deviceId,
    this.host,
  });
}

class LanDiscoveryService {
  static const String serviceName = '_casa._tcp.local';

  // Android: MethodChannel para tomar y soltar el MulticastLock
  static const _channel = MethodChannel('lan_discovery');

  static Future<void> _acquireMulticast() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('acquireMulticast');
      } catch (_) {}
    }
  }

  static Future<void> _releaseMulticast() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('releaseMulticast');
      } catch (_) {}
    }
  }

  MDnsClient? _client;
  bool _running = false;

  final _found = <String, DiscoveredDevice>{};
  final _controller = StreamController<List<DiscoveredDevice>>.broadcast();

  /// Stream con resultados acumulados mientras está corriendo `start()`.
  Stream<List<DiscoveredDevice>> get stream => _controller.stream;

  /// Inicia escaneo continuo por [timeout] y publica en [stream].
  Future<void> start({Duration timeout = const Duration(seconds: 6)}) async {
    if (_running) return;
    _running = true;
    _found.clear();
    _controller.add(const []);

    await _acquireMulticast();

    // Evita warning "reusePort not supported" en emulador Android.
    RawDatagramSocketFactory factory =
        (
          dynamic host,
          int port, {
          bool reuseAddress = true,
          bool reusePort = false,
          int ttl = 255,
          bool? v6Only,
        }) {
          return RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            port,
            reuseAddress: true,
            reusePort: false,
            ttl: ttl,
          );
        };

    final client = MDnsClient(rawDatagramSocketFactory: factory);
    _client = client;

    try {
      await client.start();
    } catch (_) {
      _running = false;
      _controller.add(const []);
      await _releaseMulticast();
      return;
    }

    final ptrStream = client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(serviceName),
    );

    final sub = ptrStream.listen((ptr) async {
      // SRV del servicio
      final srvStream = client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      );

      await for (final srv in srvStream) {
        // IP v4 del host
        final ipStream = client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        );

        await for (final ipRec in ipStream) {
          final ip = ipRec.address.address;
          final port = srv.port;

          String name = srv.target;
          String type = 'esp';
          String? devId;
          String? host;

          // TXT metadata
          final txtStream = client.lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(ptr.domainName),
          );

          await for (final txt in txtStream) {
            final entries = _extractTxtEntries(txt);
            final map = _parseTxt(entries);
            name = map['name'] ?? name;
            type = map['type'] ?? type;
            devId = map['id'] ?? devId;
            host = map['host'] ?? host;
          }

          if (ip.isNotEmpty) {
            final id = '$ip:$port';
            _found[id] = DiscoveredDevice(
              id: id,
              name: name,
              ip: ip,
              port: port,
              type: type,
              deviceId: devId,
              host: host,
            );
            _controller.add(_found.values.toList());
          }
        }
      }
    });

    // Parada automática tras timeout
    Future.delayed(timeout, () async {
      await sub.cancel();
      await stop(); // stop() es void
      _controller.add(_found.values.toList());
    });
  }

  /// Detiene el escaneo continuo.
  Future<void> stop() async {
    _running = false;
    try {
      _client?.stop();
    } catch (_) {}
    _client = null;
    await _releaseMulticast();
  }

  /// Escaneo “one-shot” (bloqueante) que devuelve la lista encontrada en [timeout].
  Future<List<DiscoveredDevice>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final found = <String, DiscoveredDevice>{};
    await _acquireMulticast();

    RawDatagramSocketFactory factory =
        (
          dynamic host,
          int port, {
          bool reuseAddress = true,
          bool reusePort = false,
          int ttl = 255,
          bool? v6Only,
        }) {
          return RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            port,
            reuseAddress: true,
            reusePort: false,
            ttl: ttl,
          );
        };

    final client = MDnsClient(rawDatagramSocketFactory: factory);
    try {
      await client.start();
    } catch (_) {
      await _releaseMulticast();
      return const [];
    }

    final ptrStream = client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(serviceName),
    );

    final sub = ptrStream.listen((ptr) async {
      final srvStream = client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      );

      await for (final srv in srvStream) {
        String ip = '';
        final ipStream = client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        );
        await for (final ipRec in ipStream) {
          ip = ipRec.address.address;
        }

        String name = srv.target;
        String type = 'esp';
        String? devId;
        String? host;

        final txtStream = client.lookup<TxtResourceRecord>(
          ResourceRecordQuery.text(ptr.domainName),
        );
        await for (final txt in txtStream) {
          final entries = _extractTxtEntries(txt);
          final map = _parseTxt(entries);
          name = map['name'] ?? name;
          type = map['type'] ?? type;
          devId = map['id'] ?? devId;
          host = map['host'] ?? host;
        }

        if (ip.isNotEmpty) {
          final id = '$ip:${srv.port}';
          found[id] = DiscoveredDevice(
            id: id,
            name: name,
            ip: ip,
            port: srv.port,
            type: type,
            deviceId: devId,
            host: host,
          );
        }
      }
    });

    await Future.delayed(timeout);
    await sub.cancel();
    try {
      client.stop();
    } catch (_) {}
    await _releaseMulticast();

    return found.values.toList();
  }

  // ---------- helpers ----------
  List<String> _extractTxtEntries(TxtResourceRecord rec) {
    final dynamic t = rec.text;
    if (t == null) return const [];
    if (t is List<String>) return t;
    if (t is Iterable) return t.map((e) => e.toString()).toList();
    if (t is String) return [t];
    return const [];
  }

  Map<String, String> _parseTxt(List<String> entries) {
    final map = <String, String>{};
    for (final e in entries) {
      final i = e.indexOf('=');
      if (i > 0) {
        map[e.substring(0, i)] = e.substring(i + 1);
      }
    }
    return map;
  }
}
