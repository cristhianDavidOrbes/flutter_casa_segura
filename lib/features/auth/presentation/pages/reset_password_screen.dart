import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/core/state/circle_state.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/login_screen.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pwd1Controller = TextEditingController();
  final _pwd2Controller = TextEditingController();

  bool _isLoading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  final AuthController _auth = Get.find<AuthController>();

  @override
  void dispose() {
    _pwd1Controller.dispose();
    _pwd2Controller.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _auth.changePassword(newPassword: _pwd1Controller.text.trim());
      await _auth.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contrasena actualizada con exito.')),
      );

      Get.offAll(
        () =>
            LoginScreen(circleNotifier: CircleStateNotifier()..moveToBottom()),
      );
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar la contrasena: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validatePwd1(String? value) {
    final pwd = value?.trim() ?? '';
    if (pwd.isEmpty) return 'Escribe tu nueva contrasena';
    if (pwd.length < 8) return 'Debe tener al menos 8 caracteres';
    return null;
  }

  String? _validatePwd2(String? value) {
    final pwd = value?.trim() ?? '';
    if (pwd.isEmpty) return 'Repite tu contrasena';
    if (pwd != _pwd1Controller.text.trim()) {
      return 'Las contrasenas no coinciden';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restablecer contrasena'),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Text(
                  'Ingresa tu nueva contrasena y confirmala.',
                  style: TextStyle(color: cs.onSurface.withOpacity(.8)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pwd1Controller,
                  obscureText: _obscure1,
                  decoration: InputDecoration(
                    labelText: 'Nueva contrasena',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure1 = !_obscure1),
                      icon: Icon(
                        _obscure1 ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  validator: _validatePwd1,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pwd2Controller,
                  obscureText: _obscure2,
                  decoration: InputDecoration(
                    labelText: 'Repite la contrasena',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure2 = !_obscure2),
                      icon: Icon(
                        _obscure2 ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  validator: _validatePwd2,
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _resetPassword,
                          child: const Text('Actualizar contrasena'),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
