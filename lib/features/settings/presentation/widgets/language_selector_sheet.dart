import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/controllers/locale_controller.dart';

class LanguageSelectorSheet extends StatelessWidget {
  const LanguageSelectorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final localeController = Get.find<LocaleController>();
    final locales = localeController.locales;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
              'settings.language'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'settings.language.subtitle'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Obx(
              () => Column(
                children: [
                  for (final locale in locales)
                    RadioListTile<Locale>(
                      value: locale,
                      groupValue: localeController.locale.value,
                      onChanged: (value) {
                        if (value != null) {
                          localeController.setLocale(value);
                        }
                      },
                      title: Text(_labelForLocale(locale).tr),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Get.back(),
              child: Text('settings.language.close'.tr),
            ),
          ],
        ),
      ),
    );
  }

  String _labelForLocale(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return 'settings.language.en';
      case 'es':
      default:
        return 'settings.language.es';
    }
  }
}
