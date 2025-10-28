import 'package:get_storage/get_storage.dart';

class MotionSettingsService {
  MotionSettingsService._();

  static final MotionSettingsService instance = MotionSettingsService._();

  final GetStorage _storage = GetStorage();

  static const String _keyPrefix = 'motion_threshold_cm_';
  static const double _defaultThresholdCm = 80.0;

  double thresholdFor(String deviceId) {
    final raw = _storage.read('${_keyPrefix}${deviceId.trim()}');
    if (raw is num) {
      final value = raw.toDouble();
      if (value > 0) return value;
    }
    return _defaultThresholdCm;
  }

  Future<void> setThreshold(String deviceId, double valueCm) async {
    final sanitized = valueCm.clamp(5.0, 400.0);
    await _storage.write('${_keyPrefix}${deviceId.trim()}', sanitized);
  }
}
