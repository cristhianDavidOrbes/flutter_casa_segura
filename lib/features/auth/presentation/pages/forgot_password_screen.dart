// lib/features/auth/presentation/pages/forgot_password_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/core/config/environment.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  /// Optional prefill coming from login screen.
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;

  final AuthController _auth = Get.find<AuthController>();

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendRecovery() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _auth.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.reset.sent'.tr)),
      );

      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Get.back();
    } on AppFailure catch (e) {
      final message =
          e.message.isNotEmpty ? e.message : 'auth.reset.failed'.tr;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'auth.reset.error'.trParams({'error': e.toString()}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'auth.reset.emailRequired'.tr;
    }
    final email = value.trim();
    if (!email.contains('@') || !email.contains('.')) {
      return 'auth.reset.emailInvalid'.tr;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('auth.reset.title'.tr),
        actions: const [ThemeToggleButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'auth.reset.description'.tr,
                    style: TextStyle(color: colorScheme.onBackground),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                    decoration: InputDecoration(
                      labelText: 'auth.login.emailLabel'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _sendRecovery,
                          child: Text('auth.reset.submit'.tr),
                        ),
                  const SizedBox(height: 12),
                  Text(
                    'auth.reset.schemeInfo'.trParams({
                      'scheme': Environment.supabaseResetRedirect,
                    }),
                    style: TextStyle(
                      color: colorScheme.onBackground.withOpacity(.75),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
