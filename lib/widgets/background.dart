import 'package:flutter/material.dart';

class Background extends StatelessWidget {
  final bool animateCircle;

  const Background({super.key, required this.animateCircle});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final circleSize = screenWidth * 1.5;

    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Container(color: scheme.primary),

        AnimatedPositioned(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,

          top: animateCircle
              ? screenHeight / 2 - circleSize / 2
              : screenHeight - circleSize / 2,
          left: screenWidth / 2 - circleSize / 2,
          child: Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: scheme.surface,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
