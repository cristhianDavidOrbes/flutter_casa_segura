import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/core/config/environment.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _isLoading = false;
  bool _emailSent = false;

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

    setState(() {
      _isLoading = true;
      _emailSent = false;
    });

    try {
      await _auth.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (!mounted) return;

      setState(() => _emailSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('!Listo! Revisa tu correo.')),
      );
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message.isNotEmpty ? e.message : 'No pudimos enviar el enlace. Intentalo mas tarde.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar el enlace: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Necesitamos tu correo electronico';
    if (!email.contains('@') || !email.contains('.')) return 'Ingresa un correo valido';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('?Olvidaste tu contrasena?'),
        actions: const [ThemeToggleButton()],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [cs.surfaceContainerHighest, cs.surface]
                : [cs.primary.withValues(alpha: 0.24), cs.surface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ForgotHero(
                      textTheme: textTheme,
                      colorScheme: cs,
                      emailSent: _emailSent,
                    ),
                    const SizedBox(height: 24),
                    Card(
                      elevation: 12,
                      shadowColor: Colors.black.withValues(alpha: 0.18),
                      color: cs.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 26),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Text(
                                  _emailSent ? '!Correo enviado!' : 'Recupera tu acceso',
                                  key: ValueKey<bool>(_emailSent),
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _emailSent ? cs.primary : cs.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  _emailSent
                                      ? 'Enviamos un enlace a ${_emailCtrl.text.trim()}. Sigue las instrucciones para restablecer tu contrasena.'
                                      : 'Ingresa el correo que usaste al registrarte y te enviaremos un enlace seguro para restablecer tu contrasena.',
                                  key: ValueKey<String>(_emailSent ? 'success' : 'description'),
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const _TipRow(
                                icon: Icons.mark_email_read_outlined,
                                text: 'Si no ves el mensaje, revisa la carpeta de spam o promociones.',
                              ),
                              const _TipRow(
                                icon: Icons.schedule_outlined,
                                text: 'El enlace tiene validez limitada. Usalo cuanto antes.',
                              ),
                              const _TipRow(
                                icon: Icons.support_agent_outlined,
                                text: '?Necesitas ayuda? Respondenos desde el correo o escribe a soporte.',
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                validator: _validateEmail,
                                enabled: !_emailSent,
                                decoration: InputDecoration(
                                  labelText: 'Correo electronico',
                                  hintText: 'persona@dominio.com',
                                  prefixIcon: const Icon(Icons.alternate_email),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              _isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 220),
                                      child: _emailSent
                                          ? FilledButton.icon(
                                              key: const ValueKey('resend'),
                                              icon: const Icon(Icons.refresh_outlined),
                                              onPressed: _sendRecovery,
                                              style: FilledButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(vertical: 13),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(18),
                                                ),
                                              ),
                                              label: const Text('Enviar de nuevo'),
                                            )
                                          : FilledButton.icon(
                                              key: const ValueKey('send'),
                                              icon: const Icon(Icons.send_outlined),
                                              onPressed: _sendRecovery,
                                              style: FilledButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(vertical: 14),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(18),
                                                ),
                                              ),
                                              label: const Text('Enviar enlace'),
                                            ),
                                    ),
                              const SizedBox(height: 18),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.surfaceVariant.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.link_outlined, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Enlace de redireccion: ${Environment.supabaseResetRedirect}',
                                          style: textTheme.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.center,
                                child: TextButton.icon(
                                  onPressed: () => Get.back(),
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('Volver al inicio de sesion'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForgotHero extends StatelessWidget {
  const _ForgotHero({
    required this.textTheme,
    required this.colorScheme,
    required this.emailSent,
  });

  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final bool emailSent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.primaryContainer],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            emailSent ? Icons.mark_email_read_rounded : Icons.lock_reset_outlined,
            color: colorScheme.onPrimary,
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          emailSent ? '!Correo enviado!' : 'Recupera tu acceso',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          emailSent
              ? 'Te enviamos un enlace para que puedas restablecerla.'
              : 'Ingresa tu correo y te enviaremos un enlace seguro.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
