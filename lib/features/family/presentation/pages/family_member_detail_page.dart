import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/repositories/family_repository.dart';
import 'package:flutter_seguridad_en_casa/features/family/presentation/pages/add_family_member_page.dart';

class FamilyMemberDetailPage extends StatelessWidget {
  const FamilyMemberDetailPage({super.key, required this.member});

  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repo = FamilyRepository.instance;

    return Scaffold(
      appBar: AppBar(title: Text(member.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _HeaderCard(member: member),
          const SizedBox(height: 20),

          Text(
            'known.detail.logsTitle'.tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),

          FutureBuilder<List<Event>>(
            future: repo.recentPresenceEvents(member.id ?? -1),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return _LogsErrorView(
                  message: snapshot.error.toString(),
                );
              }

              final events = snapshot.data ?? const <Event>[];
              if (events.isEmpty) {
                return const _LogsEmptyView();
              }

              return Column(
                children: [
                  for (final event in events)
                    _PresenceTile(event: event, member: member),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          Text(
            'known.detail.note'.tr,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // ✅ EDIT Button
            ElevatedButton.icon(
              onPressed: () async {
                final updated = await Get.to<FamilyMember?>(
                  () => AddFamilyMemberPage(existingMember: member),
                );

                if (updated != null) {
                  Get.back(result: true);
                  Get.snackbar(
                    'known.detail.updatedTitle'.tr,
                    'known.detail.updatedBody'.tr,
                  );
                }
              },
              icon: const Icon(Icons.edit),
              label: Text('known.detail.edit'.tr),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                minimumSize: const Size(140, 48),
              ),
            ),

            // ✅ DELETE Button
            ElevatedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('known.detail.deleteTitle'.tr),
                    content: Text('known.detail.deleteConfirm'.tr),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('known.detail.cancel'.tr),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('known.detail.delete'.tr),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await repo.deleteFamilyMember(member.id!);

                  if (context.mounted) {
                    Get.back(result: true);
                    Get.snackbar(
                      'known.detail.deletedTitle'.tr,
                      'known.detail.deletedBody'.tr,
                    );
                  }
                }
              },
              icon: const Icon(Icons.delete),
              label: Text('known.detail.delete'.tr),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: const Size(140, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.member});

  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final createdAt = DateFormat.yMMMMd(Get.locale?.toLanguageTag())
        .format(DateTime.fromMillisecondsSinceEpoch(member.createdAt));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: cs.primary,
                backgroundImage: _avatar(member),
                child: _avatar(member) == null
                    ? Text(
                        _initials(member.name),
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.relation,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if ((member.phone ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined),
                  const SizedBox(width: 8),
                  Text(member.phone!),
                ],
              ),
            ),

          if ((member.email ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.alternate_email),
                  const SizedBox(width: 8),
                  Text(member.email!),
                ],
              ),
            ),

          Row(
            children: [
              const Icon(Icons.calendar_today_outlined),
              const SizedBox(width: 8),
              Text(
                'known.detail.memberSince'.trParams({'date': createdAt}),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ImageProvider<Object>? _avatar(FamilyMember member) {
    final path = member.profileImagePath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? FileImage(file) : null;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : "")).toUpperCase();
  }
}

class _PresenceTile extends StatelessWidget {
  const _PresenceTile({required this.event, required this.member});

  final Event event;
  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final localeTag = Get.locale?.toLanguageTag();
    final date = DateTime.fromMillisecondsSinceEpoch(event.ts);
    final dateLabel = DateFormat.yMMMd(localeTag).add_Hm().format(date);

    final isOutOfSchedule = event.type == 'entry_out_of_schedule';
    final isEntry = event.type == 'entry' || isOutOfSchedule;

    final icon = isEntry ? Icons.login : Icons.logout;

    final chipLabel = isOutOfSchedule
        ? 'known.detail.log.outOfSchedule'.tr
        : isEntry
            ? 'known.detail.log.entry'.tr
            : 'known.detail.log.exit'.tr;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            child: Icon(icon),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chipLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogsEmptyView extends StatelessWidget {
  const _LogsEmptyView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.timeline_outlined, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'known.detail.logs.empty'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LogsErrorView extends StatelessWidget {
  const _LogsErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: cs.onErrorContainer),
          const SizedBox(height: 12),
          Text(
            'known.detail.logs.error'.tr,
            style: TextStyle(color: cs.onErrorContainer),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onErrorContainer),
          ),
        ],
      ),
    );
  }
}
