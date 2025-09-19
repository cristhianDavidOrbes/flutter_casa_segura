import 'package:hive/hive.dart';

/// Modelo simple para comentarios de la IA almacenados en Hive.
/// No usamos codegen; el adapter está escrito a mano.
class AiComment {
  int? id; // clave interna de Hive (opcional si usas add())
  final String text; // comentario de la IA
  final int createdAt; // epoch millis
  final String? deviceId; // opcional: a qué dispositivo se refiere
  final int? eventId; // opcional: id del evento en SQLite
  final List<String>
  labels; // etiquetas (por ejemplo: ["persona","sospechoso"])

  AiComment({
    this.id,
    required this.text,
    required this.createdAt,
    this.deviceId,
    this.eventId,
    this.labels = const [],
  });

  AiComment copyWith({
    int? id,
    String? text,
    int? createdAt,
    String? deviceId,
    int? eventId,
    List<String>? labels,
  }) {
    return AiComment(
      id: id ?? this.id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      deviceId: deviceId ?? this.deviceId,
      eventId: eventId ?? this.eventId,
      labels: labels ?? this.labels,
    );
  }
}

/// Adapter manual para Hive (elige un typeId único en tu app).
class AiCommentAdapter extends TypeAdapter<AiComment> {
  @override
  final int typeId = 1;

  @override
  AiComment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return AiComment(
      id: fields[0] as int?, // id (puede ser null si add())
      text: fields[1] as String,
      createdAt: fields[2] as int,
      deviceId: fields[3] as String?,
      eventId: fields[4] as int?,
      labels: (fields[5] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, AiComment obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.deviceId)
      ..writeByte(4)
      ..write(obj.eventId)
      ..writeByte(5)
      ..write(obj.labels);
  }
}
