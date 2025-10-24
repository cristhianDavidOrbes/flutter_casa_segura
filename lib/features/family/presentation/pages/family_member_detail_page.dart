import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/repositories/family_repository.dart';

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
            'family.detail.logs.title'.tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Event>>(
            future: repo.recentPresenceEvents(member.id ?? -1),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ));
              }
              if (snapshot.hasError) {
                return _LogsErrorView(
                  message: snapshot.error.toString(),
                );
              }
              final events = snapshot.data ?? const <Event>[];
              if (events.isEmpty) {
                return _LogsEmptyView();
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
            'family.detail.note'.tr,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
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
            color: Colors.black.withOpacity(0.08),
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
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if ((member.phone ?? '').isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.phone_outlined),
                const SizedBox(width: 8),
                Text(member.phone!),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if ((member.email ?? '').isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.alternate_email),
                const SizedBox(width: 8),
                Text(member.email!),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if ((member.entryStart ?? '').isNotEmpty &&
              (member.entryEnd ?? '').isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.schedule),
                const SizedBox(width: 8),
                Text(
                  'family.detail.schedule.window'.trParams({
                    'start': _formatTime(context, member.entryStart),
                    'end': _formatTime(context, member.entryEnd),
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined),
              const SizedBox(width: 8),
              Text('family.detail.memberSince'.trParams({'date': createdAt})),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final a = parts.isNotEmpty ? parts.first[0] : ' ';
    final b = parts.length > 1 ? parts.last[0] : ' ';
    return (a + b).toUpperCase();
  }

  ImageProvider<Object>? _avatar(FamilyMember member) {
    final path = member.profileImagePath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }

  String _formatTime(BuildContext context, String? value) {
    if (value == null || value.isEmpty) return '--';
    final parts = value.split(':');
    if (parts.length != 2) return value;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final time = TimeOfDay(hour: hour, minute: minute);
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
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
    final dateLabel =
        DateFormat.yMMMd(localeTag).add_Hm().format(date);
    final isOutOfSchedule = event.type == 'entry_out_of_schedule';
    final isEntry = event.type == 'entry' || isOutOfSchedule;
    final icon = isEntry ? Icons.login : Icons.logout;
    final chipLabel = isOutOfSchedule
        ? 'family.detail.log.outOfSchedule'.tr
        : isEntry
            ? 'family.detail.log.entry'.tr
            : 'family.detail.log.exit'.tr;
    final bg = isOutOfSchedule
        ? cs.errorContainer
        : isEntry
            ? cs.primaryContainer
            : cs.surfaceVariant;
    final fg = isOutOfSchedule
        ? cs.onErrorContainer
        : isEntry
            ? cs.onPrimaryContainer
            : cs.onSurfaceVariant;

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
            backgroundColor: bg,
            foregroundColor: fg,
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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
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
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.timeline_outlined, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'family.detail.logs.empty'.tr,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
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
            'family.detail.logs.error'.tr,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: cs.onErrorContainer),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onErrorContainer),
          ),
        ],
      ),
    );
  }
}





