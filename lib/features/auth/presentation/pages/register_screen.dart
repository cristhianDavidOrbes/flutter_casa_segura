import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _pwdFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePwd = true;
  String? _pendingVerificationEmail;
  bool _isResendingEmail = false;
  String? _activeField;
  String? _intendedField;
  bool _showAnimation = true;
  bool _successLayout = false;

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

    void handleFocusChange() {
      final bool nameHasFocus = _nameFocus.hasFocus;
      final bool emailHasFocus = _emailFocus.hasFocus;
      final bool pwdHasFocus = _pwdFocus.hasFocus;

      String? nextField;
      if (nameHasFocus) {
        nextField = 'name';
        _intendedField = null;
      } else if (emailHasFocus) {
        nextField = 'email';
        _intendedField = null;
      } else if (pwdHasFocus) {
        nextField = 'password';
        _intendedField = null;
      } else if (_intendedField != null) {
        nextField = _intendedField;
      }

      final bool anyFocus = nameHasFocus || emailHasFocus || pwdHasFocus;

      if (!anyFocus && nextField == null) {
        _intendedField = null;
      }

      bool needsUpdate = false;
      if (_activeField != nextField) {
        _activeField = nextField;
        needsUpdate = true;
      }

      if (anyFocus && (_successLayout || !_showAnimation)) {
        _successLayout = false;
        _showAnimation = true;
        needsUpdate = true;
      }

      if (needsUpdate) {
        setState(() {});
      }
    }

    _nameFocus.addListener(handleFocusChange);
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) {
        _setAnim(_kCorreo);
      } else if (!_pwdFocus.hasFocus) {
        _setAnim(_kIdle);
      }
      handleFocusChange();
    });

    _pwdFocus.addListener(() {
      if (_pwdFocus.hasFocus) {
        _setAnim(_kContrasena);
      } else if (!_emailFocus.hasFocus) {
        _setAnim(_kIdle);
      }
      handleFocusChange();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _nameFocus.dispose();
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
      _intendedField = null;
      _activeField = null;
      _showAnimation = true;
      _successLayout = false;
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
      FocusScope.of(context).unfocus();
      final requiresVerification = !user.emailConfirmed;

      setState(() {
        _pendingVerificationEmail = requiresVerification ? email : null;
        _activeField = null;
        _intendedField = null;
        _successLayout = true;
        _showAnimation = true;
      });

      final message = requiresVerification
          ? 'Registro exitoso. Revisa tu correo para confirmar la cuenta.'
          : 'Registro exitoso.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      await Future.delayed(const Duration(milliseconds: 3200));
      if (!mounted) return;

      setState(() {
        _showAnimation = false;
        _successLayout = true;
      });

      _setAnim(_kIdle);
      widget.circleNotifier.moveToCenter();

      if (!requiresVerification) {
        widget.circleNotifier.moveToBottom();
        if (mounted) Navigator.pop(context);
      }
    } on AppFailure catch (e) {
      if (!mounted) return;
      _setAnim(_kNoRegistrado);
      setState(() {
        _successLayout = false;
        _showAnimation = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      _setAnim(_kNoRegistrado);
      setState(() {
        _successLayout = false;
        _showAnimation = true;
      });
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

  void _cycleToNextField() {
    String? next;
    if (_nameFocus.hasFocus || _activeField == 'name') {
      next = 'email';
    } else if (_emailFocus.hasFocus || _activeField == 'email') {
      next = 'password';
    } else if (_pwdFocus.hasFocus || _activeField == 'password') {
      next = null;
    }

    if (next == null) {
      setState(() {
        _intendedField = null;
        _activeField = null;
      });
      _pwdFocus.unfocus();
      return;
    }

    setState(() {
      _intendedField = next;
      _activeField = next;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (next) {
        case 'email':
          FocusScope.of(context).requestFocus(_emailFocus);
          break;
        case 'password':
          FocusScope.of(context).requestFocus(_pwdFocus);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final size = media.size;
    final bottomPadding = media.padding.bottom;
    final keyboardInset = media.viewInsets.bottom;
    final bool keyboardVisible = keyboardInset > 0;
    final bool showCompact = keyboardVisible && _activeField != null;
    final bool successLayout = _successLayout && !_showAnimation && !keyboardVisible;

    double compactBottom = keyboardInset - 48;
    if (compactBottom < bottomPadding + 32) {
      compactBottom = bottomPadding + 32;
    }

    double cardBottom;
    if (successLayout) {
      final double successBottom = math.max(bottomPadding + 80, 72);
      cardBottom = successBottom;
    } else if (showCompact) {
      cardBottom = compactBottom;
    } else {
      cardBottom = bottomPadding + 180;
    }

    return Scaffold(
      body: Stack(
        children: [
          const Background(animateCircle: true),
          if (_artboard != null && _showAnimation)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height: size.height * (keyboardVisible ? 0.92 : 1.02),
              child: IgnorePointer(
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  offset: Offset(0, keyboardVisible ? 0.28 : 0.38),
                  child: Rive(artboard: _artboard!, fit: BoxFit.contain),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: cardBottom,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: size.width * 0.9,
                  padding: successLayout
                      ? const EdgeInsets.fromLTRB(24, 24, 24, 20)
                      : showCompact
                          ? const EdgeInsets.symmetric(horizontal: 18, vertical: 16)
                          : const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(4, 8),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: _buildFullForm(colorScheme, showCompact),
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
    ValueChanged<String>? onSubmittedExtra,
    bool enableSuggestions = true,
    bool autocorrect = true,
    TextInputAction? textInputAction,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboard,
      textInputAction: textInputAction ?? (obscure ? TextInputAction.done : TextInputAction.next),
      validator: validator,
      obscureText: obscure,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      smartDashesType: obscure ? SmartDashesType.disabled : SmartDashesType.enabled,
      smartQuotesType: obscure ? SmartQuotesType.disabled : SmartQuotesType.enabled,
      obscuringCharacter: '*',
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
          borderSide: BorderSide(color: cs.outline.withValues(alpha: .35)),
        ),
      ),
      onTap: onTapExtra,
      onChanged: onChangedExtra,
      onFieldSubmitted: onSubmittedExtra,
    );
  }

  Widget _buildFullForm(ColorScheme colorScheme, bool compact) {
    final bool showName = !compact || _activeField == 'name';
    final bool showEmail = !compact || _activeField == 'email';
    final bool showPassword = !compact || _activeField == 'password';

    Widget section({
      required bool visible,
      required Widget child,
    }) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Visibility(
          visible: visible,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: child,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: compact
              ? const SizedBox.shrink()
              : Text(
                  'auth.register.title'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        if (!compact) const SizedBox(height: 18),
        section(
          visible: showName,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('auth.register.nameLabel'.tr),
              const SizedBox(height: 8),
              _textField(
                controller: _nameCtrl,
                hint: 'auth.register.nameHint'.tr,
                focusNode: _nameFocus,
                onTapExtra: () => _setAnim(_kIdle),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) {
                    return 'Por favor ingresa tu nombre completo.';
                  }
                  if (name.length < 3) {
                    return 'Ingresa un nombre valido.';
                  }
                  return null;
                },
                onSubmittedExtra: (_) => _cycleToNextField(),
              ),
              SizedBox(height: compact ? 12 : 16),
            ],
          ),
        ),
        section(
          visible: showEmail,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('auth.register.emailLabel'.tr),
              const SizedBox(height: 8),
              _textField(
                controller: _emailCtrl,
                keyboard: TextInputType.emailAddress,
                hint: 'auth.register.emailHint'.tr,
                focusNode: _emailFocus,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) {
                    return 'auth.register.emailRequired'.tr;
                  }
                  if (!email.contains('@') || !email.contains('.')) {
                    return 'auth.register.emailInvalid'.tr;
                  }
                  return null;
                },
                onChangedExtra: _onEmailChanged,
                onSubmittedExtra: (_) => _cycleToNextField(),
              ),
              SizedBox(height: compact ? 12 : 16),
            ],
          ),
        ),
        section(
          visible: showPassword,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('auth.register.passwordLabel'.tr),
              const SizedBox(height: 8),
              _textField(
                controller: _pwdCtrl,
                focusNode: _pwdFocus,
                keyboard: TextInputType.visiblePassword,
                obscure: _obscurePwd,
                hint: 'auth.register.passwordHint'.tr,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                suffix: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: child,
                  ),
                  child: IconButton(
                    key: ValueKey<bool>(_obscurePwd),
                    tooltip: _obscurePwd
                        ? 'Mostrar contrasena'
                        : 'Ocultar contrasena',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _obscurePwd = !_obscurePwd;
                      });
                      _setAnim(_kContrasena);
                      if (!_pwdFocus.hasFocus) {
                        _pwdFocus.requestFocus();
                      }
                    },
                    icon: Icon(
                      _obscurePwd ? Icons.visibility_off : Icons.visibility,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
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
                onSubmittedExtra: (_) => _cycleToNextField(),
              ),
              SizedBox(height: compact ? 12 : 20),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: compact
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                  ],
                ),
        ),
        if (!compact && _pendingVerificationEmail != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.35),
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
                            valueColor:
                                AlwaysStoppedAnimation(colorScheme.primary),
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
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: compact
              ? const SizedBox.shrink()
              : TextButton(
                  onPressed: () {
                    widget.circleNotifier.moveToBottom();
                    Navigator.pop(context);
                  },
                  child: Text('auth.register.hasAccount'.tr),
                ),
        ),
      ],
    );
  }
}





