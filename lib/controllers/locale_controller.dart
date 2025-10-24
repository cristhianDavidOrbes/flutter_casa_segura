import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class LocaleController extends GetxController {
  LocaleController({GetStorage? storage})
      : _storage = storage ?? GetStorage(),
        locale = Rx<Locale>(const Locale('es', 'ES')) {
    locale.value = _loadInitialLocale(_storage);
  }

  static const String _storageKey = 'selected_locale';

  final GetStorage _storage;

  final locales = <Locale>[
    const Locale('es', 'ES'),
    const Locale('en', 'US'),
    const Locale('hi', 'IN'),
  ];

  final Rx<Locale> locale;

  static Locale _loadInitialLocale(GetStorage storage) {
    final saved = storage.read<String>(_storageKey);
    final fallback = const Locale('es', 'ES');
    if (saved == null) return fallback;

    final parts = saved.split('_');
    if (parts.isEmpty) return fallback;
    if (parts.length == 1) return Locale(parts[0]);
    return Locale(parts[0], parts[1]);
  }

  @override
  void onInit() {
    super.onInit();
    Get.updateLocale(locale.value);
  }

  void setLocale(Locale value) {
    if (!locales.contains(value)) return;
    locale.value = value;
    _storage.write(_storageKey, _encodeLocale(value));
    Get.updateLocale(value);
  }

  String _encodeLocale(Locale locale) {
    final country = locale.countryCode;
    if (country == null || country.isEmpty) {
      return locale.languageCode;
    }
    return '${locale.languageCode}_$country';
  }
}
