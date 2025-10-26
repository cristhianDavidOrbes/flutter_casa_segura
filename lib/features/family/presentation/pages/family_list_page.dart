import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:flutter_seguridad_en_casa/controllers/family_controller.dart';
import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/features/family/presentation/pages/add_family_member_page.dart';
import 'package:flutter_seguridad_en_casa/features/family/presentation/pages/family_member_detail_page.dart';

class FamilyListPage extends StatefulWidget {
  const FamilyListPage({super.key});

  @override
  State<FamilyListPage> createState() => _FamilyListPageState();
}

class _FamilyListPageState extends State<FamilyListPage> {
  late final FamilyController _controller;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<FamilyController>()) {
      _controller = Get.find<FamilyController>();
    } else {
      _controller = Get.put(FamilyController(), permanent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('family.list.title'.tr),
        actions: [
          IconButton(
            tooltip: 'family.list.refresh'.tr,
            icon: const Icon(Icons.refresh),
            onPressed: _controller.loadMembers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Get.to<FamilyMember?>(
            () => const AddFamilyMemberPage(),
          );
          if (added != null) {
            Get.snackbar(
              'family.add.success.title'.tr,
              'family.add.success.body'.trParams({'name': added.name}),
              backgroundColor: cs.primaryContainer,
              colorText: cs.onPrimaryContainer,
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 3),
            );
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: Text('family.list.add'.tr),
      ),
      body: Obx(
        () {
          if (_controller.loading.value && _controller.members.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final error = _controller.error.value;
          if (error != null && _controller.members.isEmpty) {
            return _ErrorView(
              message: error,
              onRetry: _controller.loadMembers,
            );
          }

          if (_controller.members.isEmpty) {
            return _EmptyView(onAdd: () {
              Get.to(() => const AddFamilyMemberPage());
            });
          }

          return RefreshIndicator(
            onRefresh: _controller.loadMembers,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _controller.members.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final member = _controller.members[index];
                return _FamilyTile(
                  member: member,
                  onTap: () => Get.to(
                    () => FamilyMemberDetailPage(member: member),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _FamilyTile extends StatelessWidget {
  const _FamilyTile({required this.member, this.onTap});

  final FamilyMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final createdAt = DateFormat.yMMMd(Get.locale?.toLanguageTag())
        .format(DateTime.fromMillisecondsSinceEpoch(member.createdAt));
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  _initials(member.name),
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                    const SizedBox(height: 6),
                    Text(
                      'family.list.memberSince'.trParams({'date': createdAt}),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final a = parts.isNotEmpty ? parts.first[0] : ' ';
    final b = parts.length > 1 ? parts.last[0] : ' ';
    return (a + b).toUpperCase();
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 72, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              'family.list.empty.title'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'family.list.empty.subtitle'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add),
              label: Text('family.list.add'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: cs.error),
            const SizedBox(height: 12),
            Text(
              'family.list.error.title'.tr,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.error),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text('family.list.refresh'.tr),
            ),
          ],
        ),
      ),
    );
  }
}





