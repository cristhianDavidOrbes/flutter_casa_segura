import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:flutter_seguridad_en_casa/features/ai/domain/security_chat_message.dart';

class SecurityChatStore {
  SecurityChatStore._();

  static const _boxName = 'security_chat';
  static Box<SecurityChatMessage>? _box;

  static Future<void> init() async {
    if (_box?.isOpen == true) return;
    _box = await Hive.openBox<SecurityChatMessage>(_boxName);
  }

  static Box<SecurityChatMessage> get box {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
        'SecurityChatStore no inicializado. Llama init() antes.',
      );
    }
    return _box!;
  }

  static ValueListenable<Box<SecurityChatMessage>> listenable() =>
      box.listenable();

  static List<SecurityChatMessage> history() {
    final items = box.values.toList();
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  static Future<void> add(SecurityChatMessage message) async {
    await box.add(message);
  }

  static Future<void> clear() async => box.clear();
}
