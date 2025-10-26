import 'package:hive/hive.dart';

class SecurityEvent {
  SecurityEvent({
    required this.deviceId,
    required this.deviceName,
    required this.label,
    required this.description,
    required this.localImagePath,
    required this.createdAt,
    this.remoteImageUrl,
    this.familyMemberId,
    this.familyMemberName,
    this.familyScheduleMatched,
  });

  final String deviceId;
  final String deviceName;
  final String label;
  final String description;
  final String localImagePath;
  final DateTime createdAt;
  final String? remoteImageUrl;
  final int? familyMemberId;
  final String? familyMemberName;
  final bool? familyScheduleMatched;
}

class SecurityEventAdapter extends TypeAdapter<SecurityEvent> {
  @override
  final int typeId = 2;

  @override
  SecurityEvent read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return SecurityEvent(
      deviceId: fields[0] as String,
      deviceName: fields[1] as String,
      label: fields[2] as String,
      description: fields[3] as String,
      localImagePath: fields[4] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(fields[5] as int),
      remoteImageUrl: fields[6] as String?,
      familyMemberId: fields[7] as int?,
      familyMemberName: fields[8] as String?,
      familyScheduleMatched: fields[9] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, SecurityEvent obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.deviceId)
      ..writeByte(1)
      ..write(obj.deviceName)
      ..writeByte(2)
      ..write(obj.label)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.localImagePath)
      ..writeByte(5)
      ..write(obj.createdAt.millisecondsSinceEpoch)
      ..writeByte(6)
      ..write(obj.remoteImageUrl)
      ..writeByte(7)
      ..write(obj.familyMemberId)
      ..writeByte(8)
      ..write(obj.familyMemberName)
      ..writeByte(9)
      ..write(obj.familyScheduleMatched);
  }
}


