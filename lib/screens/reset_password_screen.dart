// lib/screens/reset_password_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/theme_toggle_button.dart';
import 'package:appwrite/appwrite.dart';

import '../config/environment.dart';
import 'login_screen.dart';
import '../circle_state.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String userId;
  final String secret;

  const ResetPasswordScreen({
    super.key,
    required this.userId,
    required this.secret,
  });

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

  late final Client client;
  late final Account account;

  @override
  void initState() {
    super.initState();
    client = Client()
      ..setEndpoint(Environment.appwritePublicEndpoint)
      ..setProject(Environment.appwriteProjectId);
    account = Account(client);
  }

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
      // Appwrite v12+: updateRecovery(userId, secret, password)
      await account.updateRecovery(
        userId: widget.userId,
        secret: widget.secret,
        password: _pwd1Controller.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Contraseña actualizada con éxito')),
      );

      // Volvemos al login
      Get.offAll(
        () =>
            LoginScreen(circleNotifier: CircleStateNotifier()..moveToBottom()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validatePwd1(String? v) {
    if (v == null || v.trim().isEmpty) return 'Escribe tu nueva contraseña';
    if (v.trim().length < 8) return 'Debe tener al menos 8 caracteres';
    return null;
  }

  String? _validatePwd2(String? v) {
    if (v == null || v.trim().isEmpty) return 'Repite tu contraseña';
    if (v.trim() != _pwd1Controller.text.trim()) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restablecer contraseña'),
        actions: const [
          ThemeToggleButton(),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Text(
                  'Ingresa tu nueva contraseña y confírmala.',
                  style: TextStyle(color: cs.onBackground.withOpacity(.8)),
                ),
                const SizedBox(height: 16),

                // Nueva contraseña
                TextFormField(
                  controller: _pwd1Controller,
                  obscureText: _obscure1,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
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

                // Repite contraseña
                TextFormField(
                  controller: _pwd2Controller,
                  obscureText: _obscure2,
                  decoration: InputDecoration(
                    labelText: 'Repite la contraseña',
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

                // Botón
                _isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _resetPassword,
                          child: const Text('Actualizar contraseña'),
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
