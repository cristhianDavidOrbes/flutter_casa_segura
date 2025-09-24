class EspDeviceInfo {
  final String id; // chip-id del dispositivo
  final String type; // "sensor" | "relay" | "cam" (libre)
  final String fw; // versión fw
  final String host; // IP alcanzable en LAN (p.ej. "192.168.1.50")
  final int port; // normalmente 80

  EspDeviceInfo({
    required this.id,
    required this.type,
    required this.fw,
    required this.host,
    this.port = 80,
  });

  factory EspDeviceInfo.fromJson(
    Map<String, dynamic> j,
    String host,
    int port,
  ) {
    return EspDeviceInfo(
      id: j['id'] as String,
      type: j['type'] as String? ?? 'sensor',
      fw: j['fw'] as String? ?? '1.0.0',
      host: host,
      port: port,
    );
  }

  Uri baseHttp() => Uri.parse('http://$host:$port');
  Uri infoUri() => Uri.parse('http://$host:$port/info');
}
