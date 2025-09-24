// lib/screens/device_detail_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({
    super.key,
    required this.deviceId,
    required this.name,
    required this.type,
    this.ip,
    this.lastSeenAt,
  });

  final String deviceId; // p.ej. casa-esp-xxxx (sin .local)
  final String name;
  final String type; // "esp", "esp32cam", etc.
  final String? ip;
  final int? lastSeenAt;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  bool get _online {
    if (widget.lastSeenAt == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - widget.lastSeenAt!) <= 8000; // mismo criterio que DevicesPage
  }

  String get _displayHost => widget.ip ?? '${widget.deviceId}.local';

  List<Uri> _tries(String path) {
    return <Uri>[
      if ((widget.ip ?? '').isNotEmpty) Uri.parse('http://${widget.ip}$path'),
      Uri.parse('http://${widget.deviceId}.local$path'),
    ];
  }

  Future<void> _doPing() async {
    String msg = 'sin respuesta';
    for (final u in _tries('/ping')) {
      try {
        final res = await http.get(u).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          msg = res.body;
          break;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _forgetAp() async {
    bool ok = false;
    for (final u in [
      ..._tries('/apmode'),
      ..._tries('/factory'), // por si no expone /apmode
    ]) {
      try {
        final res = await http.get(u).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          ok = true;
          break;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Pedido de AP enviado. El equipo debería encender su SSID CASA-ESP_xxxx en pocos segundos.'
              : 'No pudimos contactar al equipo. Si estaba offline, prueba borrar en la lista y reintentar.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final online = _online;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            tooltip: 'Ping',
            onPressed: _doPing,
            icon: const Icon(Icons.wifi_tethering),
          ),
          IconButton(
            tooltip: 'Recargar',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: online ? Colors.green : cs.outline,
              ),
              const SizedBox(width: 8),
              Text(
                online ? 'Conectado' : 'Desconectado',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: online ? Colors.green : cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Chip(
                label: Text(widget.type.toUpperCase()),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('ID: ${widget.deviceId}'),
          Text('IP: $_displayHost'),

          const SizedBox(height: 16),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Información',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _kv('Nombre', widget.name),
                    _kv('Tipo', widget.type),
                    _kv('IP', _displayHost),
                    _kv(
                      'Visto por última vez',
                      widget.lastSeenAt != null
                          ? DateTime.fromMillisecondsSinceEpoch(
                              widget.lastSeenAt!,
                            ).toIso8601String()
                          : '—',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Aquí puedes agregar tarjetas con lecturas/acciones específicas de tu firmware (por ejemplo /sensor, /relay).',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ====== Tarjeta específica para cámara ======
          if (widget.type.toLowerCase().contains('cam')) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: cs.surfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: const Text(
                      'Vista en vivo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 240,
                    child: _MjpegView(
                      url: 'http://$_displayHost/stream',
                      // si el stream falla, usa /photo cada 1s
                      fallbackSnapshotUrl: 'http://$_displayHost/photo',
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          // Botonera en Wrap (evita overflow horizontal)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _doPing,
                icon: const Icon(Icons.wifi),
                label: const Text('Ping'),
              ),
              OutlinedButton.icon(
                onPressed: _forgetAp,
                icon: const Icon(Icons.link_off),
                label: const Text('Olvidar (AP)'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

/// Widget sencillo para reproducir un MJPEG.
/// - Intenta abrir /stream.
/// - Si falla 3 veces seguidas, alterna a polling de /photo (snapshot).
class _MjpegView extends StatefulWidget {
  const _MjpegView({required this.url, this.fallbackSnapshotUrl});

  final String url;
  final String? fallbackSnapshotUrl;

  @override
  State<_MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<_MjpegView> {
  HttpClient? _client;
  StreamSubscription<List<int>>? _sub;

  // Parser state
  String? _boundary;
  final _buf = BytesBuilder(copy: false);
  Uint8List? _lastFrame;

  int _failCount = 0;
  Timer? _snapshotTimer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    _closed = true;
    _stopStream();
    _stopSnapshot();
    super.dispose();
  }

  void _stopStream() {
    _sub?.cancel();
    _sub = null;
    _client?.close(force: true);
    _client = null;
  }

  void _stopSnapshot() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
  }

  Future<void> _startStream() async {
    _stopStream();
    _stopSnapshot();

    // IMPORTANTE: autoUncompress va en el CLIENTE
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..autoUncompress = false;

    try {
      final req = await _client!.getUrl(Uri.parse(widget.url));
      req.headers.set(HttpHeaders.acceptHeader, 'multipart/x-mixed-replace');
      req.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

      final res = await req.close();
      if (res.statusCode != 200) {
        _onStreamFail();
        return;
      }

      // boundary de Content-Type
      final ct = res.headers.contentType;
      final boundary = _extractBoundary(ct?.parameters['boundary']);
      if (boundary == null) {
        _onStreamFail();
        return;
      }
      _boundary = boundary;

      _sub = res.listen(
        _onData,
        onError: (_) => _onStreamFail(),
        onDone: _onStreamFail,
        cancelOnError: true,
      );
    } catch (_) {
      _onStreamFail();
    }
  }

  String? _extractBoundary(String? b) {
    if (b == null || b.isEmpty) return null;
    // El stream trae líneas con "--<boundary>"
    if (b.startsWith('--')) return b;
    return '--$b';
  }

  // Busca sublista en lista (bytes)
  int _indexOf(List<int> data, List<int> pattern, [int start = 0]) {
    if (pattern.isEmpty) return -1;
    final plen = pattern.length;
    final dlen = data.length;
    for (int i = start; i <= dlen - plen; i++) {
      int j = 0;
      while (j < plen && data[i + j] == pattern[j]) {
        j++;
      }
      if (j == plen) return i;
    }
    return -1;
  }

  void _onData(List<int> chunk) {
    _buf.add(chunk);
    final bytes = _buf.toBytes();

    final boundary = _boundary!;
    final bBytes = ascii.encode(boundary);
    final nl = ascii.encode('\r\n');
    final headerSep = ascii.encode('\r\n\r\n');

    int searchFrom = 0;

    while (true) {
      // Encuentra el inicio de un boundary
      int bIdx = _indexOf(bytes, bBytes, searchFrom);
      if (bIdx < 0) break;

      // Desde allí, busca fin de cabeceras (\r\n\r\n)
      int hIdx = _indexOf(bytes, headerSep, bIdx);
      if (hIdx < 0) break;

      // Cabeceras por si queremos leer Content-Length
      final headerPart = ascii.decode(
        bytes.sublist(bIdx, hIdx),
        allowInvalid: true,
      );

      // Content-Length (opcional)
      int? contentLen;
      final lines = headerPart.split('\r\n');
      for (final ln in lines) {
        final l = ln.toLowerCase();
        if (l.startsWith('content-length:')) {
          final v = l.split(':').last.trim();
          contentLen = int.tryParse(v);
          break;
        }
      }

      final dataStart = hIdx + headerSep.length;
      if (contentLen != null) {
        // Espera a tener todos los bytes
        if (bytes.length < dataStart + contentLen) break;

        final frame = Uint8List.fromList(
          bytes.sublist(dataStart, dataStart + contentLen),
        );
        _setFrame(frame);

        // Avanza el puntero de búsqueda al final de este frame
        searchFrom = dataStart + contentLen;
      } else {
        // Sin Content-Length: leer hasta boundary siguiente
        final nextB = _indexOf(bytes, bBytes, dataStart);
        if (nextB < 0) break;
        final frame = Uint8List.fromList(
          bytes.sublist(dataStart, nextB - nl.length),
        );
        _setFrame(frame);
        searchFrom = nextB;
      }
    }

    // Compacta el buffer: deja desde el último boundary en adelante, o lo vacía
    if (searchFrom > 0 && searchFrom < bytes.length) {
      _buf.clear();
      _buf.add(bytes.sublist(searchFrom));
    } else if (searchFrom >= bytes.length) {
      _buf.clear();
    }
  }

  void _setFrame(Uint8List frame) {
    if (!mounted) return;
    setState(() {
      _lastFrame = frame;
      _failCount = 0;
    });
  }

  void _onStreamFail() {
    if (_closed) return;
    _stopStream();
    _failCount++;
    if (_failCount >= 3 && widget.fallbackSnapshotUrl != null) {
      // cambia a snapshots
      _startSnapshot();
    } else {
      // reintento corto
      Future.delayed(const Duration(seconds: 1), () {
        if (!_closed) _startStream();
      });
    }
  }

  void _startSnapshot() {
    _stopSnapshot();
    final url = widget.fallbackSnapshotUrl!;
    _snapshotTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          _setFrame(res.bodyBytes);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_lastFrame == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Image.memory(_lastFrame!, gaplessPlayback: true, fit: BoxFit.cover);
  }
}
