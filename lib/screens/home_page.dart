// lib/screens/home_page.dart
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:get/get.dart';

import 'login_screen.dart';
import '../circle_state.dart';
import '../widgets/theme_toggle_button.dart';
import 'devices_page.dart';
import 'provisioning_screen.dart';

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
        ).showSnackBar(SnackBar(content: Text("Error al cerrar sesión: $e")));
      }
    }
  }

  void _goToDevices() {
    Get.to(() => const DevicesPage());
  }

  void _goToProvisioning() {
    Get.to(() => const ProvisioningScreen());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Página Principal"),
        backgroundColor: cs.primary,
        actions: [
          const ThemeToggleButton(),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar Sesión",
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Bienvenido 🚀",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              // Buscar / administrar dispositivos en LAN (mDNS)
              ElevatedButton.icon(
                onPressed: _goToDevices,
                icon: const Icon(Icons.devices_other),
                label: const Text('Buscar / Administrar dispositivos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Reconocer/Provisionar dispositivo (SoftAP)
              OutlinedButton.icon(
                onPressed: _goToProvisioning,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Reconocer / Provisionar dispositivo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
