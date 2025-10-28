import 'dart:io';



import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:intl/intl.dart';



import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';

import 'package:flutter_seguridad_en_casa/features/security/domain/security_event.dart';

import 'package:flutter_seguridad_en_casa/repositories/family_repository.dart';



class NotificationDetailPage extends StatelessWidget {

  const NotificationDetailPage({super.key, required this.event});



  final SecurityEvent event;



  @override

  Widget build(BuildContext context) {

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(

      appBar: AppBar(title: Text('notifications.detail.title'.tr)),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(16),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Text(

              event.label,

              style: Theme.of(context)

                  .textTheme

                  .headlineSmall

                  ?.copyWith(fontWeight: FontWeight.w700),

            ),

            const SizedBox(height: 8),

            Text(

              'notifications.detail.device'

                  .trParams({'device': event.deviceName}),

              style: TextStyle(color: colorScheme.onSurfaceVariant),

            ),

            const SizedBox(height: 4),

            Text(

              'notifications.detail.time'.trParams({

                'time': _formatDate(event.createdAt),

              }),

              style: TextStyle(color: colorScheme.onSurfaceVariant),

            ),

            const SizedBox(height: 12),

            Text(

              event.description,

              style: TextStyle(color: colorScheme.onSurface),

            ),

            if (event.familyMemberName != null ||

                event.familyMemberId != null) ...[

              const SizedBox(height: 20),

              _FamilyInfo(event: event),

            ],

            const SizedBox(height: 16),

            if (event.localImagePath.isNotEmpty && File(event.localImagePath).existsSync())

              ClipRRect(

                borderRadius: BorderRadius.circular(18),

                child: Image.file(

                  File(event.localImagePath),

                  fit: BoxFit.cover,

                ),

              )

            else

              Container(

                height: 200,

                decoration: BoxDecoration(

                  color: colorScheme.surfaceContainerHighest,

                  borderRadius: BorderRadius.circular(18),

                ),

                alignment: Alignment.center,

                child: Text(

                  'notifications.detail.noImage'.tr,

                  style: TextStyle(color: colorScheme.onSurfaceVariant),

                ),

              ),

            if (event.remoteImageUrl != null) ...[

              const SizedBox(height: 8),

              Text(

                'notifications.detail.source'.trParams({

                  'url': event.remoteImageUrl!,

                }),

                style: TextStyle(

                  color: colorScheme.onSurfaceVariant,

                  fontSize: 12,

                ),

              ),

            ],

          ],

        ),

      ),

    );

  }



  String _formatDate(DateTime date) {

    final localeTag = Get.locale?.toLanguageTag();

    final formatter = DateFormat.yMd(localeTag).add_Hm();

    return formatter.format(date);

  }

}



class _FamilyInfo extends StatelessWidget {

  const _FamilyInfo({required this.event});



  final SecurityEvent event;



  @override

  Widget build(BuildContext context) {

    if (event.familyMemberId == null) {

      return _FamilyInfoBody(event: event, member: null);

    }

    return FutureBuilder<FamilyMember?>(

      future: FamilyRepository.instance.getMember(event.familyMemberId!),

      builder: (context, snapshot) {

        if (snapshot.connectionState == ConnectionState.waiting) {

          return const Padding(

            padding: EdgeInsets.symmetric(vertical: 12),

            child: Center(child: CircularProgressIndicator()),

          );

        }

        return _FamilyInfoBody(event: event, member: snapshot.data);

      },

    );

  }

}



class _FamilyInfoBody extends StatelessWidget {

  const _FamilyInfoBody({required this.event, required this.member});



  final SecurityEvent event;

  final FamilyMember? member;



  @override

  Widget build(BuildContext context) {

    final colorScheme = Theme.of(context).colorScheme;

    final name = event.familyMemberName ?? member?.name ?? 'â';

    final window = _formatWindow(context, member);

    final status = event.familyScheduleMatched == false

        ? 'notifications.detail.familySchedule.off'.trParams({'window': window})

        : 'notifications.detail.familySchedule.ok'.trParams({'window': window});



    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(

        color: colorScheme.surfaceContainerHighest,

        borderRadius: BorderRadius.circular(18),

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Text(

            'notifications.detail.familyDetected'.trParams({'name': name}),

            style: Theme.of(context)

                .textTheme

                .titleMedium

                ?.copyWith(fontWeight: FontWeight.w600),

          ),

          const SizedBox(height: 6),

          Text(

            status,

            style: Theme.of(context)

                .textTheme

                .bodyMedium

                ?.copyWith(color: colorScheme.onSurfaceVariant),

          ),

        ],

      ),

    );

  }



  String _formatWindow(BuildContext context, FamilyMember? member) {

    if (member == null || member.schedules.isEmpty) {

      return '--';

    }



    final entries = member.schedules

        .where((schedule) => schedule.start.isNotEmpty && schedule.end.isNotEmpty)

        .map(

          (schedule) =>

              '${_formatTime(context, schedule.start)} - ${_formatTime(context, schedule.end)}',

        )

        .toList(growable: false);



    if (entries.isEmpty) {

      return '--';

    }

    return entries.join(', ');

  }



  String _formatTime(BuildContext context, String value) {

    final parts = value.split(':');

    if (parts.length != 2) return value;

    final hour = int.tryParse(parts[0]) ?? 0;

    final minute = int.tryParse(parts[1]) ?? 0;

    final time = TimeOfDay(hour: hour, minute: minute);

    return MaterialLocalizations.of(context).formatTimeOfDay(time);

  }

}

