import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rive/rive.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/background.dart';
import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
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
        const SnackBar(content: Text('Revisa los campos del formulario.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = await _auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _pwdCtrl.text.trim(),
        fullName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      );

      if (!mounted) return;

      _setAnim(_kRegistrado);
      final message = user.emailConfirmed
          ? 'Registro exitoso.'
          : 'Registro exitoso. Revisa tu correo para confirmar la cuenta.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      await Future.delayed(const Duration(milliseconds: 1200));

      widget.circleNotifier.moveToBottom();
      if (mounted) Navigator.pop(context);
    } on AppFailure catch (e) {
      if (!mounted) return;
      _setAnim(_kNoRegistrado);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      _setAnim(_kNoRegistrado);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error inesperado: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                          'Crear Cuenta',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _label('Nombre:'),
                        const SizedBox(height: 8),
                        _textField(
                          controller: _nameCtrl,
                          hint: 'Nombre completo',
                          onTapExtra: () => _setAnim(_kIdle),
                        ),
                        const SizedBox(height: 16),
                        _label('Correo electronico:'),
                        const SizedBox(height: 8),
                        _textField(
                          controller: _emailCtrl,
                          keyboard: TextInputType.emailAddress,
                          hint: 'correo@ejemplo.com',
                          focusNode: _emailFocus,
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return 'Escribe un correo valido';
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Correo no valido';
                            }
                            return null;
                          },
                          onChangedExtra: (_) => _setAnim(_kCorreo),
                        ),
                        const SizedBox(height: 16),
                        _label('Contrasena:'),
                        const SizedBox(height: 8),
                        _textField(
                          controller: _pwdCtrl,
                          focusNode: _pwdFocus,
                          obscure: _obscurePwd,
                          hint: 'Minimo 8 caracteres',
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
                            if (pwd.isEmpty) return 'Escribe una contrasena';
                            if (pwd.length < 8) return 'Minimo 8 caracteres';
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
                                  'Registrarse',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            widget.circleNotifier.moveToBottom();
                            Navigator.pop(context);
                          },
                          child: const Text('Ya tienes cuenta? Inicia sesion'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: ThemeToggleButton(
                  color: colorScheme.onPrimary,
                  padding: EdgeInsets.zero,
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
