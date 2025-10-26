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
            Obx(() {
              final selected = localeController.locale.value;
              return Column(
                children: [
                  for (final locale in locales)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      title: Text(_labelForLocale(locale).tr),
                      trailing: Icon(
                        selected == locale
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected == locale
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      onTap: () => localeController.setLocale(locale),
                    ),
                ],
              );
            }),
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
