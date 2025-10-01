// lib/features/home/presentation/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/core/state/circle_state.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart';
import 'package:flutter_seguridad_en_casa/features/auth/infrastructure/deeplink_service.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/login_screen.dart';
import 'package:flutter_seguridad_en_casa/screens/devices_page.dart';
import 'package:flutter_seguridad_en_casa/screens/provisioning_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.circleNotifier});

  final CircleStateNotifier circleNotifier;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthController _auth = Get.find<AuthController>();

  AuthUser? get _user => _auth.currentUser.value;

  String get _welcomeName {
    final user = _user;
    if (user == null) return 'Usuario';
    if (user.name != null && user.name!.trim().isNotEmpty) {
      return user.name!.trim();
    }
    return user.email;
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
      DeeplinkService().clearHistory();
      if (mounted) {
        Get.offAll(() => LoginScreen(circleNotifier: widget.circleNotifier));
      }
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cerrar sesion: ' + e.toString())),
        );
      }
    }
  }

  void _goToDevices() => Get.to(() => const DevicesPage());

  void _goToProvisioning() => Get.to(() => const ProvisioningScreen());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Bienvenido, $_welcomeName'),
        backgroundColor: cs.primary,
        actions: [
          const ThemeToggleButton(),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
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
                'Panel principal',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
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

