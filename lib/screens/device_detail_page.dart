// lib/screens/device_detail_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final String type; // "esp", "esp32cam", "servo", etc.
  final String? ip;
  final DateTime? lastSeenAt;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  bool get _online {
    if (widget.lastSeenAt == null) return false;
    return DateTime.now().difference(widget.lastSeenAt!) <=
        const Duration(seconds: 8); // mismo criterio que DevicesPage
  }

  String get _displayHost => widget.ip ?? '${widget.deviceId}.local';

  List<Uri> _tries(String path) {
    return <Uri>[
      if ((widget.ip ?? '').isNotEmpty) Uri.parse('http://${widget.ip}$path'),
      Uri.parse('http://${widget.deviceId}.local$path'),
    ];
  }

  Future<void> _doPing() async {
    // Mantengo tu lógica y agrego rutas de respaldo sin quitar nada
    String msg = 'sin respuesta';
    final paths = <String>['/ping', '/info', '/']; // añadí /info y /
    for (final p in paths) {
      for (final u in _tries(p)) {
        try {
          final res = await http.get(u).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            msg = res.body.isNotEmpty ? res.body : 'ok';
            p == '/ping' ? null : msg = 'ok'; // respuesta simple para info/raíz
            break;
          }
        } catch (_) {}
      }
      if (msg != 'sin respuesta') break;
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

  // ===== Datos en tiempo real =====
  // Ponemos '/sensors' primero para priorizar el JSON con datos reales.
  static const List<String> _candidateDataPaths = <String>[
    '/sensors',
    '/sensor',
    '/status',
    '/data',
    '/metrics',
    '/info',
  ];

  Map<String, dynamic>? _liveData;
  String? _endpointUsed;
  DateTime? _lastUpdate;
  String? _lastError;

  bool _autoRefresh = true;
  Duration _period = const Duration(seconds: 2);
  Timer? _pollTimer;

  // ====== Estado/Control de SERVO (nuevo) ======
  bool? _servoOn; // null = desconocido; true/false = estado conocido
  bool _servoBusy = false;

  // ====== Detección de cámara (nuevo sin quitar nada) ======
  bool _hasStream = false; // si detectamos /photo o /stream, mostramos video

  bool get _seVeControlServo {
    // Si el tipo lo dice o si el JSON trae "servo"
    final t = widget.type.toLowerCase();
    final byType = t.contains('servo');
    final byData = _liveData != null && _liveData!['servo'] != null;
    return byType || byData;
  }

  Future<Map<String, dynamic>?> _getJsonFrom(String path) async {
    for (final uri in _tries(path)) {
      try {
        final res = await http
            .get(uri)
            .timeout(const Duration(seconds: 6)); // +timeout
        if (res.statusCode == 200) {
          final m = _decodeJsonMap(res.body);
          if (m != null) return m;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _refreshServoState() async {
    // intenta /servo, y si no, /sensors
    Map<String, dynamic>? m = await _getJsonFrom('/servo');
    m ??= await _getJsonFrom('/sensors');
    bool? on;
    if (m != null) {
      // {on:true/false, pos:x} o {"servo":{"on":...}}
      if (m.containsKey('on')) {
        final v = m['on'];
        on = v is bool ? v : (v.toString().toLowerCase() == 'true');
      } else if (m['servo'] is Map) {
        final sv = m['servo'];
        final v = sv['on'];
        on = v is bool ? v : (v.toString().toLowerCase() == 'true');
      }
    }
    if (!mounted) return;
    setState(() => _servoOn = on);
  }

  Future<void> _setServoOn(bool on) async {
    if (_servoBusy) return;
    setState(() => _servoBusy = true);
    bool ok = false;
    final body = jsonEncode({'on': on});
    for (final uri in _tries('/servo')) {
      try {
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          ok = true;
          break;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _servoBusy = false;
      if (ok) _servoOn = on;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar el estado del servo')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _startAuto();
    // Intento inicial de leer estado del servo (si aplica)
    _refreshServoState();
    // Detección de cámara sin bloquear UI
    _probeStream();
  }

  @override
  void dispose() {
    _stopAuto();
    super.dispose();
  }

  void _startAuto() {
    _pollOnce();
    _pollTimer?.cancel();
    if (_autoRefresh) {
      _pollTimer = Timer.periodic(_period, (_) => _pollOnce());
    }
  }

  void _stopAuto() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce() async {
    final paths = <String>[
      if (_endpointUsed != null) _endpointUsed!,
      ..._candidateDataPaths.where((p) => p != _endpointUsed),
    ];

    Map<String, dynamic>? data;
    String? hitPath;
    String? lastErr;

    for (final path in paths) {
      for (final uri in _tries(path)) {
        try {
          final res = await http
              .get(uri)
              .timeout(const Duration(seconds: 6)); // +timeout
          if (res.statusCode == 200) {
            final parsed = _decodeJsonMap(res.body);
            if (parsed != null) {
              final sanitized = _sanitize(parsed);

              // si la respuesta es trivial (p. ej. {"ok":true}), intenta siguiente
              if (_isTrivialPayload(sanitized)) {
                lastErr = 'Respuesta trivial en $path';
                continue;
              }

              data = sanitized;
              hitPath = path;
              break;
            }
          } else {
            lastErr = 'HTTP ${res.statusCode}';
          }
        } catch (e) {
          lastErr = e.toString();
        }
      }
      if (data != null) break;
    }

    if (!mounted) return;
    setState(() {
      _liveData = data;
      _endpointUsed = hitPath;
      _lastUpdate = DateTime.now();
      _lastError = data == null ? lastErr ?? 'Sin respuesta' : null;
    });

    // Si hay datos y aparece "servo", actualiza el switch si no lo sabemos aún
    if (_seVeControlServo && _servoOn == null) {
      _refreshServoState();
    }
  }

  // --- NUEVO: detección de /photo o /stream para mostrar cámara aunque type sea "esp"
  Future<void> _probeStream() async {
    bool ok = false;
    // Probo /photo primero (respuesta finita)
    for (final u in _tries('/photo')) {
      try {
        final res = await http.get(u).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 &&
            res.headers['content-type']?.contains('image/jpeg') == true) {
          ok = true;
          break;
        }
      } catch (_) {}
    }
    if (!ok) {
      // Si /photo no respondió, intento abrir cabecera de /stream con HttpClient y lo cierro
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4);
        for (final base in _tries('/stream')) {
          try {
            final req = await client.getUrl(base);
            req.headers.set(
              HttpHeaders.acceptHeader,
              'multipart/x-mixed-replace',
            );
            final res = await req.close().timeout(const Duration(seconds: 4));
            if (res.statusCode == 200 &&
                (res.headers.contentType?.mimeType ?? '').contains(
                  'multipart',
                )) {
              ok = true;
              break;
            }
          } catch (_) {}
        }
        client.close(force: true);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _hasStream = ok);
  }

  Map<String, dynamic>? _decodeJsonMap(String source) {
    if (source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        final out = <String, dynamic>{};
        decoded.forEach((k, v) => out[k.toString()] = v);
        return out;
      }
    } catch (_) {}
    return null;
  }

  static const Set<String> _sensitiveKeys = {
    'ssid',
    'pass',
    'password',
    'token',
    'access_token',
    'refresh_token',
    'user_id',
    'wifi',
    'clave',
  };

  Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) {
      final key = k.toString();
      if (_sensitiveKeys.contains(key.toLowerCase())) return;
      out[key] = v;
    });
    return out;
  }

  // Considera "trivial" si sólo trae claves tipo ok/status o está vacío.
  bool _isTrivialPayload(Map<String, dynamic> m) {
    if (m.isEmpty) return true;
    final keys = m.keys.map((e) => e.toString().toLowerCase()).toList();
    final allAreFlags = keys.every(
      (k) => k == 'ok' || k == 'status' || k == 'message',
    );
    if (allAreFlags) return true;
    if (m.length == 1) {
      final v = m.values.first;
      if (v is bool && (keys.first == 'ok' || keys.first == 'status')) {
        return true;
      }
    }
    return false;
  }

  List<MapEntry<String, String>> _flattenForUi(
    dynamic value, [
    String prefix = '',
  ]) {
    final list = <MapEntry<String, String>>[];
    if (value is Map) {
      value.forEach((k, v) {
        final p = prefix.isEmpty ? '$k' : '$prefix.$k';
        list.addAll(_flattenForUi(v, p));
      });
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final p = prefix is String && prefix.isNotEmpty
            ? '$prefix[$i]'
            : '[$i]';
        list.addAll(_flattenForUi(value[i], p));
      }
    } else {
      list.add(MapEntry(prefix, value?.toString() ?? 'null'));
    }
    return list;
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
            onPressed: () {
              _pollOnce();
              _refreshServoState();
              setState(() {}); // refresca encabezados
            },
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
          Text('IP/Host: $_displayHost'),

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
                    _kv('Host', _displayHost),
                    _kv(
                      'Visto por última vez',
                      widget.lastSeenAt != null
                          ? widget.lastSeenAt!.toLocal().toIso8601String()
                          : '--',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ====== Control de SERVO (nuevo, aparece sólo si corresponde) ======
          if (_seVeControlServo) ...[
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
                      'Control de servo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Estado:',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_servoOn == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Switch.adaptive(
                            value: _servoOn ?? false,
                            onChanged: _servoBusy
                                ? null
                                : (v) {
                                    _setServoOn(v);
                                  },
                          ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _servoBusy
                              ? null
                              : () => _refreshServoState(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Leer'),
                        ),
                      ],
                    ),
                  ),
                  if (_servoBusy)
                    const Padding(
                      padding: EdgeInsets.only(left: 12, right: 12, bottom: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
            ),
          ],

          // ====== Datos en tiempo real ======
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
                  child: Row(
                    children: [
                      const Icon(Icons.sensors, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Datos en tiempo real',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      if (_endpointUsed != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Text(
                            _endpointUsed!,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _pollOnce,
                        icon: const Icon(Icons.sync),
                        label: const Text('Actualizar'),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Auto'),
                        selected: _autoRefresh,
                        onSelected: (v) {
                          setState(() => _autoRefresh = v);
                          if (v) {
                            _startAuto();
                          } else {
                            _stopAuto();
                          }
                        },
                      ),
                      const Spacer(),
                      if (_lastUpdate != null)
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Actualizado: ${_lastUpdate!.toLocal().toIso8601String()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_liveData == null && _lastError == null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Buscando datos en ${_candidateDataPaths.join(", ")} …',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                else if (_liveData == null && _lastError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: cs.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No hay datos: $_lastError',
                            style: TextStyle(color: cs.error),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _DataList(
                    data: _liveData!,
                    onCopyJson: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: const JsonEncoder.withIndent(
                            '  ',
                          ).convert(_liveData),
                        ),
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('JSON copiado al portapapeles'),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          // ====== Tarjeta específica para cámara ======
          if (widget.type.toLowerCase().contains('cam') || _hasStream) ...[
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

class _DataList extends StatelessWidget {
  const _DataList({required this.data, required this.onCopyJson});

  final Map<String, dynamic> data;
  final VoidCallback onCopyJson;

  List<MapEntry<String, String>> _flatten(dynamic value, [String prefix = '']) {
    final list = <MapEntry<String, String>>[];
    if (value is Map) {
      value.forEach((k, v) {
        final p = prefix.isEmpty ? '$k' : '$prefix.$k';
        list.addAll(_flatten(v, p));
      });
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final p = prefix.isEmpty ? '[$i]' : '$prefix[$i]';
        list.addAll(_flatten(value[i], p));
      }
    } else {
      list.add(MapEntry(prefix, value?.toString() ?? 'null'));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final flat = _flatten(data);

    return Column(
      children: [
        if (flat.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Sin datos para mostrar.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: flat.length,
            separatorBuilder: (ctx, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final e = flat[i];
              return ListTile(
                dense: true,
                title: Text(
                  e.key,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(e.value),
                trailing: IconButton(
                  tooltip: 'Copiar valor',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: e.value));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Valor copiado')),
                    );
                  },
                ),
              );
            },
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onCopyJson,
            icon: const Icon(Icons.code),
            label: const Text('Copiar JSON'),
          ),
        ),
      ],
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
    if (b.startsWith('--')) return b;
    return '--$b';
  }

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
      int bIdx = _indexOf(bytes, bBytes, searchFrom);
      if (bIdx < 0) break;

      int hIdx = _indexOf(bytes, headerSep, bIdx);
      if (hIdx < 0) break;

      final headerPart = ascii.decode(
        bytes.sublist(bIdx, hIdx),
        allowInvalid: true,
      );

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
        if (bytes.length < dataStart + contentLen) break;

        final frame = Uint8List.fromList(
          bytes.sublist(dataStart, dataStart + contentLen),
        );
        _setFrame(frame);

        searchFrom = dataStart + contentLen;
      } else {
        final nextB = _indexOf(bytes, bBytes, dataStart);
        if (nextB < 0) break;
        final frame = Uint8List.fromList(
          bytes.sublist(dataStart, nextB - nl.length),
        );
        _setFrame(frame);
        searchFrom = nextB;
      }
    }

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
      _startSnapshot();
    } else {
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
