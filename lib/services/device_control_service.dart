import 'dart:convert';
import 'package:http/http.dart' as http;

class DeviceControlService {
  const DeviceControlService();

  Future<bool> factoryResetByIp(
    String ip, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final uri = Uri.parse('http://$ip/factory_reset');
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({}),
          )
          .timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
