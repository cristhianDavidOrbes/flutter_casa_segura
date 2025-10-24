import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rive/rive.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/background.dart';
import 'package:flutter_seguridad_en_casa/core/state/circle_state.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.circleNotifier});

  final CircleStateNotifier circleNotifier;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _pwdFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePwd = true;
  String? _pendingVerificationEmail;
  bool _isResendingEmail = false;

  final AuthController _auth = Get.find<AuthController>();

  Artboard? _artboard;
  SMIInput<double>? _iAnim;

  static const double _kIdle = 0;
  static const double _kCorreo = 1;
  static const double _kContrasena = 2;
  static const double _kNoRegistrado = 3;
  static const double _kRegistrado = 4;

  @override
  void initState() {
    super.initState();
    _loadRive();

    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) {
        _setAnim(_kCorreo);
      } else if (!_pwdFocus.hasFocus) {
        _setAnim(_kIdle);
      }
    });

    _pwdFocus.addListener(() {
      if (_pwdFocus.hasFocus) {
        _setAnim(_kContrasena);
      } else if (!_emailFocus.hasFocus) {
        _setAnim(_kIdle);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _emailFocus.dispose();
    _pwdFocus.dispose();
    super.dispose();
  }

  Future<void> _loadRive() async {
    try {
      final file = await RiveFile.asset('assets/rive/registro.riv');
      final art = file.artboardByName('registrarse') ?? file.mainArtboard;

      final controller = StateMachineController.fromArtboard(
        art,
        'register_maching',
      );

      if (controller != null) {
        art.addController(controller);
        _iAnim = controller.findInput<double>('animacion');
        _setAnim(_kIdle);
      }

      setState(() => _artboard = art);
    } catch (e) {
      debugPrint('Error cargando Rive registro: ${e.toString()}');
    }
  }

  void _setAnim(double value) {
    if (_iAnim == null) return;
    _iAnim!.value = value;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      _setAnim(_kNoRegistrado);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.register.formInvalid'.tr)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _pendingVerificationEmail = null;
    });

    try {
      final email = _emailCtrl.text.trim();
      final password = _pwdCtrl.text.trim();
      final fullName = _nameCtrl.text.trim();

      final user = await _auth.signUp(
        email: email,
        password: password,
        fullName: fullName.isEmpty ? null : fullName,
      );

      if (!mounted) return;

      _setAnim(_kRegistrado);
      final requiresVerification = !user.emailConfirmed;

      setState(() {
        _pendingVerificationEmail = requiresVerification ? email : null;
      });

      final message = requiresVerification
          ? 'Registro exitoso. Revisa tu correo para confirmar la cuenta.'
          : 'Registro exitoso.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      if (!requiresVerification) {
        await Future.delayed(const Duration(milliseconds: 1200));
        widget.circleNotifier.moveToBottom();
        if (mounted) Navigator.pop(context);
      }
    } on AppFailure catch (e) {
      if (!mounted) return;
      _setAnim(_kNoRegistrado);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      _setAnim(_kNoRegistrado);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.error.unexpected'.trParams({'error': e.toString()}))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    final email = _pendingVerificationEmail?.trim();
    if (email == null || email.isEmpty) return;
    if (_isResendingEmail) return;

    setState(() => _isResendingEmail = true);

    try {
      await _auth.resendConfirmationEmail(email: email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('auth.register.resendSuccess'.tr),
        ),
      );
    } on AppFailure catch (e) {
      if (!mounted) return;
      final message = e.message.isNotEmpty
          ? e.message
          : 'No se pudo reenviar el correo de verificacion.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.register.resendError'.trParams({'error': e.toString()}))),
      );
    } finally {
      if (mounted) {
        setState(() => _isResendingEmail = false);
      }
    }
  }

  void _onEmailChanged(String value) {
    _setAnim(_kCorreo);
    if (_pendingVerificationEmail != null) {
      setState(() => _pendingVerificationEmail = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final double riveHeight = size.height * 0.96;
    final double riveYOffset = 250;
    final double cardBottom = bottomInset + 200;

    return Scaffold(
      body: Stack(
        children: [
          const Background(animateCircle: true),
          if (_artboard != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: riveHeight,
              child: IgnorePointer(
                child: Transform.translate(
                  offset: Offset(0, riveYOffset),
                  child: Rive(artboard: _artboard!, fit: BoxFit.contain),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: cardBottom,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  width: size.width * 0.9,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 18,
                        offset: const Offset(4, 8),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'auth.register.title'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _label('auth.register.nameLabel'.tr),
                        const SizedBox(height: 8),
                        _textField(
                          controller: _nameCtrl,
                          hint: 'auth.register.nameHint'.tr,
                          onTapExtra: () => _setAnim(_kIdle),
                        ),
                        const SizedBox(height: 16),
                        _label('auth.register.emailLabel'.tr),
                        const SizedBox(height: 8),
                        _textField(
                          controller: _emailCtrl,
                          keyboard: TextInputType.emailAddress,
                          hint: 'auth.register.emailHint'.tr,
                          focusNode: _emailFocus,
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty)
                              return 'auth.register.emailRequired'.tr;
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'auth.register.emailInvalid'.tr;
                            }
                            return null;
                          },
                          onChangedExtra: _onEmailChanged,
                        ),
                        const SizedBox(height: 16),
                        _label('auth.register.passwordLabel'.tr),
                        const SizedBox(height: 8),
                        _textField(
                          controller: _pwdCtrl,
                          focusNode: _pwdFocus,
                          obscure: _obscurePwd,
                          hint: 'auth.register.passwordHint'.tr,
                          suffix: IconButton(
                            onPressed: () => setState(() {
                              _obscurePwd = !_obscurePwd;
                              _setAnim(_kContrasena);
                            }),
                            icon: Icon(
                              _obscurePwd
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          validator: (value) {
                            final pwd = value?.trim() ?? '';
                            if (pwd.isEmpty) return 'auth.register.passwordRequired'.tr;
                            if (pwd.length < 8) return 'auth.register.passwordHint'.tr;
                            return null;
                          },
                          onTapExtra: () => _setAnim(_kContrasena),
                          onChangedExtra: (_) => _setAnim(_kContrasena),
                        ),
                        const SizedBox(height: 20),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: _register,
                                child: Text(
                                  'auth.register.submit'.tr,
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                        const SizedBox(height: 10),
                        if (_pendingVerificationEmail != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: colorScheme.primary.withOpacity(0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'auth.register.pendingVerification'.trParams({
                                    'email': _pendingVerificationEmail!,
                                  }),
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _resendVerificationEmail,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colorScheme.primary,
                                  ),
                                  icon: _isResendingEmail
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation(
                                              colorScheme.primary,
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.mark_email_unread_outlined,
                                        ),
                                  label: Text(
                                    _isResendingEmail
                                        ? 'auth.register.resending'.tr
                                        : 'auth.register.resend'.tr,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextButton(
                          onPressed: () {
                            widget.circleNotifier.moveToBottom();
                            Navigator.pop(context);
                          },
                          child: Text('auth.register.hasAccount'.tr),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 15.5,
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
    FocusNode? focusNode,
    bool obscure = false,
    Widget? suffix,
    VoidCallback? onTapExtra,
    ValueChanged<String>? onChangedExtra,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboard,
      validator: validator,
      obscureText: obscure,
      style: TextStyle(color: cs.onSurface),
      cursorColor: cs.primary,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: cs.surface,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline.withOpacity(.35)),
        ),
      ),
      onTap: onTapExtra,
      onChanged: onChangedExtra,
    );
  }
}





