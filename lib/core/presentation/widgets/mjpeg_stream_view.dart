import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Reusable MJPEG viewer with automatic reconnection and optional
/// snapshot fallback. Extracted from the device detail page so other
/// screens (like the AI assistant) can also render live camera feeds.
class MjpegStreamView extends StatefulWidget {
  const MjpegStreamView({
    super.key,
    required this.url,
    this.fallbackSnapshotUrl,
  });

  final String url;
  final String? fallbackSnapshotUrl;

  @override
  State<MjpegStreamView> createState() => _MjpegStreamViewState();
}

class _MjpegStreamViewState extends State<MjpegStreamView> {
  HttpClient? _httpClient;
  StreamSubscription<List<int>>? _sub;

  String? _boundary;
  final BytesBuilder _buf = BytesBuilder(copy: false);
  Uint8List? _lastFrame;

  int _failCount = 0;
  Timer? _snapshotTimer;

  bool _closed = false;
  bool _restartScheduled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startStream());
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_stopStream());
    _stopSnapshot();
    super.dispose();
  }

  Future<void> _stopStream() async {
    final sub = _sub;
    _sub = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    final client = _httpClient;
    _httpClient = null;
    client?.close(force: true);
    _boundary = null;
    _buf.clear();
  }

  void _stopSnapshot() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
  }

  Future<void> _startStream() async {
    if (_closed) return;

    await _stopStream();
    _stopSnapshot();

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      _httpClient = client;

      final uri = Uri.parse(widget.url);
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'multipart/x-mixed-replace',
      );
      request.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

      final response = await request.close();

      if (response.statusCode != 200) {
        client.close(force: true);
        _httpClient = null;
        _onStreamFail();
        return;
      }

      final boundary = _extractBoundary(
        response.headers.contentType?.parameters['boundary'],
      );

      if (boundary == null) {
        client.close(force: true);
        _httpClient = null;
        _onStreamFail();
        return;
      }

      _boundary = boundary;

      _sub = response.listen(
        _onData,
        onError: (Object error, StackTrace stackTrace) =>
            _handleStreamError(error, stackTrace),
        onDone: _handleStreamDone,
        cancelOnError: true,
      );
    } catch (_) {
      client?.close(force: true);
      if (identical(client, _httpClient)) {
        _httpClient = null;
      }
      _onStreamFail();
    }
  }

  String? _extractBoundary(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('--')) return value;
    return '--$value';
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
    final boundaryBytes = ascii.encode(boundary);
    final headerSep = ascii.encode('\r\n\r\n');
    final newLine = ascii.encode('\r\n');

    int searchFrom = 0;

    while (true) {
      final boundaryIdx = _indexOf(bytes, boundaryBytes, searchFrom);
      if (boundaryIdx < 0) break;

      final headerIdx = _indexOf(bytes, headerSep, boundaryIdx);
      if (headerIdx < 0) break;

      final headerPart = ascii.decode(
        bytes.sublist(boundaryIdx, headerIdx),
        allowInvalid: true,
      );

      int? contentLength;
      for (final line in headerPart.split('\r\n')) {
        final lower = line.toLowerCase();
        if (lower.startsWith('content-length:')) {
          final value = lower.split(':').last.trim();
          contentLength = int.tryParse(value);
          break;
        }
      }

      final dataStart = headerIdx + headerSep.length;

      if (contentLength != null) {
        if (bytes.length < dataStart + contentLength) break;
        final frame = Uint8List.fromList(
          bytes.sublist(dataStart, dataStart + contentLength),
        );
        _setFrame(frame);
        searchFrom = dataStart + contentLength;
      } else {
        final nextBoundary = _indexOf(bytes, boundaryBytes, dataStart);
        if (nextBoundary < 0) break;
        final frame = Uint8List.fromList(
          bytes.sublist(dataStart, nextBoundary - newLine.length),
        );
        _setFrame(frame);
        searchFrom = nextBoundary;
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

  void _handleStreamError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _onStreamFail();
  }

  void _handleStreamDone() {
    if (_closed) return;
    _onStreamFail();
  }

  void _onStreamFail() {
    if (_closed) return;

    _failCount++;
    if (_restartScheduled) return;
    _restartScheduled = true;

    unawaited(_recoverFromFailure());
  }

  Future<void> _recoverFromFailure() async {
    try {
      await _stopStream();

      if (_failCount >= 3 && widget.fallbackSnapshotUrl != null) {
        _startSnapshot();
        await Future.delayed(const Duration(seconds: 5));
      } else {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } finally {
      _restartScheduled = false;
    }

    if (_closed) return;
    await _startStream();
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
