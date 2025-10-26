import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/core/state/circle_state.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/login_screen.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';

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
  double _strength = 0;

  final AuthController _auth = Get.find<AuthController>();

  @override
  void dispose() {
    _pwd1Controller.dispose();
    _pwd2Controller.dispose();
    super.dispose();
  }

  void _updateStrength(String value) {
    final pwd = value.trim();
    double score = 0;
    if (pwd.length >= 8) score += 0.25;
    if (RegExp(r'[A-Z]').hasMatch(pwd)) score += 0.25;
    if (RegExp(r'[0-9]').hasMatch(pwd)) score += 0.25;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>\-]').hasMatch(pwd)) score += 0.25;
    setState(() => _strength = score.clamp(0, 1));
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Restablecer contrasena'),
        actions: const [ThemeToggleButton()],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [cs.surfaceContainerHighest, cs.surface]
                : [cs.primary.withValues(alpha: 0.2), cs.surface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ResetHero(colorScheme: cs, textTheme: textTheme),
                    const SizedBox(height: 24),
                    Card(
                      elevation: 12,
                      color: cs.surface,
                      shadowColor: Colors.black.withValues(alpha: 0.18),
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
                              Text(
                                'Crea una contrasena unica y segura',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Tu nueva contrasena reemplazara la actual y cerrara cualquier sesion activa por seguridad.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 20),
                              _GuidelineRow(
                                icon: Icons.key_outlined,
                                text: 'Usa al menos 8 caracteres combinando mayusculas y minusculas.',
                              ),
                              _GuidelineRow(
                                icon: Icons.verified_user_outlined,
                                text: 'Agrega numeros y simbolos para reforzarla.',
                              ),
                              _GuidelineRow(
                                icon: Icons.no_accounts_outlined,
                                text: 'Evita informacion obvia como tu nombre o fecha.',
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _pwd1Controller,
                                obscureText: _obscure1,
                                validator: _validatePwd1,
                                onChanged: _updateStrength,
                                decoration: InputDecoration(
                                  labelText: 'Nueva contrasena',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                                    icon: Icon(
                                      _obscure1 ? Icons.visibility_off : Icons.visibility,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _StrengthMeter(strength: _strength),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _pwd2Controller,
                                obscureText: _obscure2,
                                validator: _validatePwd2,
                                decoration: InputDecoration(
                                  labelText: 'Confirma la contrasena',
                                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                                    icon: Icon(
                                      _obscure2 ? Icons.visibility_off : Icons.visibility,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 26),
                              _isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : FilledButton.icon(
                                      icon: const Icon(Icons.check_circle_outline),
                                      onPressed: _resetPassword,
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                      ),
                                      label: const Text('Actualizar contrasena'),
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

class _ResetHero extends StatelessWidget {
  const _ResetHero({required this.colorScheme, required this.textTheme});

  final ColorScheme colorScheme;
  final TextTheme textTheme;

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
            Icons.lock_person_outlined,
            color: colorScheme.onPrimary,
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Nueva contrasena, mismo hogar seguro',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Por seguridad cerraremos todas las sesiones activas y podras volver a iniciar con tu nueva clave.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _GuidelineRow extends StatelessWidget {
  const _GuidelineRow({required this.icon, required this.text});

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

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final double strength;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String label;
    Color color;
    if (strength >= 0.75) {
      label = 'Fortaleza: Excelente';
      color = Colors.green;
    } else if (strength >= 0.5) {
      label = 'Fortaleza: Buena';
      color = Colors.orange;
    } else if (strength > 0) {
      label = 'Fortaleza: Debil';
      color = Colors.redAccent;
    } else {
      label = 'Agrega mas caracteres y simbolos';
      color = cs.onSurfaceVariant;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: strength == 0 ? null : strength,
          minHeight: 6,
          backgroundColor: cs.surfaceVariant,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
              ),
        ),
      ],
    );
  }
}
