import 'package:hive/hive.dart';
import 'ai_comment.dart';

class AiCommentStore {
  AiCommentStore._();
  static const _boxName = 'ai_comments';
  static Box<AiComment>? _box;

  static Future<void> init() async {
    if (_box?.isOpen == true) return;
    _box = await Hive.openBox<AiComment>(_boxName);
  }

  static Box<AiComment> get box {
    if (_box == null || !_box!.isOpen) {
      throw StateError('AiCommentStore no inicializado. Llama init() antes.');
    }
    return _box!;
  }

  /// Inserta y devuelve la key (int autoincremental de Hive)
  static Future<int> add(AiComment c) async {
    final key = await box.add(c);
    final saved = c.copyWith(id: key);
    await box.put(key, saved); // guarda el id dentro del objeto
    return key;
  }

  static Future<void> put(int key, AiComment c) => box.put(key, c);
  static AiComment? get(int key) => box.get(key);

  static List<AiComment> all() =>
      box.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static List<AiComment> byDevice(String deviceId) =>
      box.values.where((e) => e.deviceId == deviceId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static Future<void> delete(int key) => box.delete(key);
  static Future<int> clear() => box.clear();
}
