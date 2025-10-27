import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'package:flutter_seguridad_en_casa/features/security/data/security_event_store.dart';
import 'package:flutter_seguridad_en_casa/features/security/domain/security_event.dart';
import 'package:flutter_seguridad_en_casa/features/security/presentation/pages/notification_detail_page.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Box<SecurityEvent>>(
      valueListenable: SecurityEventStore.listenable(),
      builder: (context, box, _) {
        final events = box.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return Scaffold(
          appBar: AppBar(
            title: Text('notifications.title'.tr),
            actions: [
              if (events.isNotEmpty)
                IconButton(
                  tooltip: 'notifications.clear'.tr,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => _confirmClear(),
                ),
            ],
          ),
          body: events.isEmpty
              ? Center(
                  child: Text(
                    'notifications.empty'.tr,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return ListTile(
                      leading: Icon(
                        event.familyMemberId != null
                            ? Icons.family_restroom
                            : Icons.shield_moon_outlined,
                      ),
                      title: Text(event.label),
                      subtitle: Text(
                        event.familyMemberName != null
                            ? 'notifications.list.familySubtitle'.trParams({
                                'name': event.familyMemberName!,
                                'device': event.deviceName,
                                'time': _formatDate(event.createdAt),
                              })
                            : 'notifications.list.subtitle'.trParams({
                                'device': event.deviceName,
                                'time': _formatDate(event.createdAt),
                              }),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Get.to(() => NotificationDetailPage(event: event)),
                    );
                  },
                ),
        );
      },
    );
  }

  void _confirmClear() {
    Get.dialog(
      AlertDialog(
        title: Text('notifications.clear'.tr),
        content: Text('notifications.clear.confirm'.tr),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text('notifications.clear.cancel'.tr),
          ),
          FilledButton(
            onPressed: () async {
              await SecurityEventStore.clear();
              Get.back();
              Get.snackbar(
                'notifications.title'.tr,
                'notifications.clear.success'.tr,
                snackPosition: SnackPosition.BOTTOM,
              );
            },
            child: Text('notifications.clear.accept'.tr),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final localeTag = Get.locale?.toLanguageTag();
    final formatter = DateFormat.yMd(localeTag).add_Hm();
    return formatter.format(date);
  }
}
