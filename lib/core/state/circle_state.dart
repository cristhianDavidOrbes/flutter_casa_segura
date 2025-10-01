import 'package:flutter/material.dart';

class CircleStateNotifier extends ValueNotifier<bool> {
  CircleStateNotifier() : super(false);

  void moveToCenter() => value = true;
  void moveToBottom() => value = false;
}
