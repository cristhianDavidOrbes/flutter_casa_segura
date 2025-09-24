import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/theme_controller.dart';

class ThemeToggleButton extends StatelessWidget {
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double? iconSize;

  const ThemeToggleButton({
    super.key,
    this.color,
    this.padding = EdgeInsets.zero,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final iconColor = color ?? IconTheme.of(context).color;

    return IconButton(
      tooltip: 'Cambiar tema',
      padding: padding,
      iconSize: iconSize,
      onPressed: themeController.toggleTheme,
      icon: Icon(Icons.brightness_6, color: iconColor),
    );
  }
}
