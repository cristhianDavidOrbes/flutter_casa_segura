import 'package:hive/hive.dart';

class SecurityChatMessage extends HiveObject {
  SecurityChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String role; // 'user' or 'assistant'
  final String text;
  final DateTime createdAt;
}

class SecurityChatMessageAdapter extends TypeAdapter<SecurityChatMessage> {
  @override
  final int typeId = 3;

  @override
  SecurityChatMessage read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return SecurityChatMessage(
      role: fields[0] as String,
      text: fields[1] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(fields[2] as int),
    );
  }

  @override
  void write(BinaryWriter writer, SecurityChatMessage obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.role)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.createdAt.millisecondsSinceEpoch);
  }
}
