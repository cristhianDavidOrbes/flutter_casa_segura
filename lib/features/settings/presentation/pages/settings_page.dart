import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/controllers/locale_controller.dart';
import 'package:flutter_seguridad_en_casa/features/family/presentation/pages/family_list_page.dart';
import 'package:flutter_seguridad_en_casa/features/settings/presentation/widgets/language_selector_sheet.dart';
import 'package:flutter_seguridad_en_casa/features/security/application/push_notification_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localeController = Get.find<LocaleController>();
    final currentLocale = localeController.locale.value;
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr)),
      body: ListView(
        children: [
          _SectionHeader(label: 'settings.section.general'.tr),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text('settings.language'.tr),
            subtitle: Text(
              'settings.language.current'.trParams({
                'value': _readableLocale(currentLocale.languageCode),
              }),
            ),
            onTap: () => _openLanguageSheet(context),
            trailing: const Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text('settings.push.title'.tr),
            subtitle: Text('settings.push.subtitle'.tr),
            onTap: () => _syncPushToken(context),
            trailing: const Icon(Icons.sync),
          ),
          const Divider(height: 32),
          _SectionHeader(label: 'settings.section.family'.tr),
          ListTile(
            leading: const Icon(Icons.groups_rounded),
            title: Text('settings.family.manage'.tr),
            subtitle: Text('settings.family.subtitle'.tr),
            onTap: () => Get.to(() => const FamilyListPage()),
            trailing: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _openLanguageSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const LanguageSelectorSheet(),
    );
  }

  Future<void> _syncPushToken(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('settings.push.syncing'.tr),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      await PushNotificationService.to.syncTokenWithUser();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: cs.primaryContainer,
          content: Text(
            'settings.push.success'.tr,
            style: TextStyle(color: cs.onPrimaryContainer),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: cs.errorContainer,
          content: Text(
            'settings.push.error'.trParams({'error': '$e'}),
            style: TextStyle(color: cs.onErrorContainer),
          ),
        ),
      );
    }
  }

  String _readableLocale(String lang) {
    switch (lang) {
      case 'en':
        return 'settings.language.en'.tr;
      case 'es':
      default:
        return 'settings.language.es'.tr;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
