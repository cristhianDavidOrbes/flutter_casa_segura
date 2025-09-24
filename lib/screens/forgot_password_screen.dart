// lib/screens/forgot_password_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/theme_toggle_button.dart';
import 'package:appwrite/appwrite.dart';
import '../config/environment.dart';

/// URL pública del puente (Next/Vercel) que recibirá ?userId=...&secret=...
/// y redirigirá a la app con casa_segura://reset?userId=...&secret=...
const String kRecoveryBridgeUrl = 'https://redirrecion-home.vercel.app/reset';

class ForgotPasswordScreen extends StatefulWidget {
  /// Opcional: para prellenar el email si vienes del login.
  final String? initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _isLoading = false;

  late final Client _client;
  late final Account _account;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail ?? '';

    _client = Client()
      ..setEndpoint(Environment.appwritePublicEndpoint)
      ..setProject(Environment.appwriteProjectId);

    _account = Account(_client);
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
      // Envia el correo de recuperación con el enlace a tu puente en Vercel.
      await _account.createRecovery(
        email: _emailCtrl.text.trim(),
        url: kRecoveryBridgeUrl,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enlace de recuperación enviado. Revisa tu correo y abre el enlace.',
          ),
        ),
      );

      // Regresa al login tras un breve delay
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Get.back();
    } on AppwriteException catch (e) {
      // Manejo amigable de rate limit (429) u otros
      String msg = 'Error al enviar recuperación: ${e.message ?? e.code}';
      if (e.code == 429 || e.type == 'general_rate_limit_exceeded') {
        msg =
            'Has hecho demasiadas solicitudes. Espera un momento y vuelve a intentarlo (429).';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar recuperación: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Escribe tu correo';
    final email = v.trim();
    if (!email.contains('@') || !email.contains('.')) {
      return 'Correo no válido';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperar contraseña'),
        actions: const [
          ThemeToggleButton(),
        ],
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
                    'Ingresa tu correo y te enviaremos un enlace para restablecer tu contraseña.',
                    style: TextStyle(color: cs.onBackground),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _sendRecovery,
                          child: const Text('Enviar enlace de recuperación'),
                        ),
                  const SizedBox(height: 12),
                  Text(
                    'Cuando abras el enlace desde el correo, te llevará a:\n'
                    '$kRecoveryBridgeUrl, que abrirá la app automáticamente.',
                    style: TextStyle(
                      color: cs.onBackground.withOpacity(.75),
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
