import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:get/get.dart';

import 'login_screen.dart';
import '../circle_state.dart';
import '../controllers/theme_controller.dart';

class HomePage extends StatefulWidget {
  final Account account;
  final CircleStateNotifier circleNotifier;

  const HomePage({
    super.key,
    required this.account,
    required this.circleNotifier,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> _logout() async {
    try {
      await widget.account.deleteSession(sessionId: 'current');

      if (mounted) {
        Get.offAll(() => LoginScreen(circleNotifier: widget.circleNotifier));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ Error al cerrar sesión: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Página Principal"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            tooltip: 'Cambiar tema',
            onPressed: () => Get.find<ThemeController>().toggleTheme(),
            icon: const Icon(Icons.brightness_6),
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar Sesión",
          ),
        ],
      ),
      body: const Center(
        child: Text(
          "Bienvenido 🚀",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
