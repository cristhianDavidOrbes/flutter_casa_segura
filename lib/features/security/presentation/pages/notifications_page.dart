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
    return Scaffold(
      appBar: AppBar(title: Text('notifications.title'.tr)),
      body: ValueListenableBuilder<Box<SecurityEvent>>(
        valueListenable: SecurityEventStore.listenable(),
        builder: (context, box, _) {
          final events = box.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (events.isEmpty) {
            return Center(
              child: Text(
                'notifications.empty'.tr,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            );
          }

          return ListView.separated(
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
                onTap: () => Get.to(
                  () => NotificationDetailPage(event: event),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final localeTag = Get.locale?.toLanguageTag();
    final formatter = DateFormat.yMd(localeTag).add_Hm();
    return formatter.format(date);
  }
}
