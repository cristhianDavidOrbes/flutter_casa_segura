import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextPage;

  const SplashScreen({super.key, required this.nextPage});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showNext = false;

  @override
  void initState() {
    super.initState();
    // Espera 5 segundos antes de ir a la siguiente pantalla
    Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _showNext = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final splash = Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: const Center(
        child: RiveAnimation.asset(
          'assets/rive/cargando.riv',
          artboard: 'cargar',
          fit: BoxFit.contain,
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: _showNext,
          child: Offstage(
            offstage: !_showNext,
            child: widget.nextPage,
          ),
        ),
        Offstage(
          offstage: _showNext,
          child: splash,
        ),

        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: ThemeToggleButton(
                color: Theme.of(context).colorScheme.onPrimary,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
