import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/features/security/application/gemini_vision_service.dart';
import 'package:flutter_seguridad_en_casa/repositories/family_repository.dart';

class FamilyMatch {
  const FamilyMatch({required this.member, required this.withinSchedule});

  final FamilyMember member;
  final bool withinSchedule;
}

class FamilyPresenceService {
  FamilyPresenceService._();

  static final FamilyPresenceService instance = FamilyPresenceService._();

  final FamilyRepository _familyRepository = FamilyRepository.instance;

  Future<FamilyMatch?> identify(Uint8List captureBytes) async {
    final members = await _familyRepository.listMembers();
    if (members.isEmpty) return null;

    for (final member in members) {
      final path = member.profileImagePath;
      if (path == null || path.isEmpty) continue;

      final file = File(path);
      if (!await file.exists()) continue;

      try {
        final profileBytes = await file.readAsBytes();
        final match = await GeminiVisionService.instance
            .isSamePerson(profileBytes, captureBytes);

        if (match == true) {
          final within = _isWithinSchedule(member, DateTime.now());
          return FamilyMatch(member: member, withinSchedule: within);
        }
      } catch (e) {
        // Ignore and continue with next member.
      }
    }
    return null;
  }

  bool _isWithinSchedule(FamilyMember member, DateTime now) {
    final start = member.entryStart;
    final end = member.entryEnd;
    if (start == null || start.isEmpty || end == null || end.isEmpty) {
      return true;
    }

    final startMinutes = _toMinutes(start);
    final endMinutes = _toMinutes(end);
    final currentMinutes = now.hour * 60 + now.minute;

    if (startMinutes == null || endMinutes == null) return true;

    if (endMinutes <= startMinutes) {
      // Window crosses midnight.
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }

    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  }

  int? _toMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }
}

