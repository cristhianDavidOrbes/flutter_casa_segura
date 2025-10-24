import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:flutter_seguridad_en_casa/features/security/domain/security_event.dart';

class SecurityEventStore {
  SecurityEventStore._();

  static const _boxName = 'security_events';
  static Box<SecurityEvent>? _box;

  static Future<void> init() async {
    if (_box?.isOpen == true) return;
    _box = await Hive.openBox<SecurityEvent>(_boxName);
  }

  static Box<SecurityEvent> get box {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
        'SecurityEventStore no inicializado. Llama init() antes.',
      );
    }
    return _box!;
  }

  static ValueListenable<Box<SecurityEvent>> listenable() => box.listenable();

  static Future<int> add(SecurityEvent event) async {
    return box.add(event);
  }

  static List<SecurityEvent> all() {
    final events = box.values.toList();
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events;
  }

  static Future<void> clear() async => box.clear();
}
