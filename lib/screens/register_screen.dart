// lib/screens/register_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// Fondo + círculo
import '../widgets/background.dart';
import '../circle_state.dart';

// Appwrite
import 'package:appwrite/appwrite.dart';
import '../config/environment.dart';

// Tema
import '../controllers/theme_controller.dart';

// Rive
import 'package:rive/rive.dart';

class RegisterScreen extends StatefulWidget {
  final CircleStateNotifier circleNotifier;
  const RegisterScreen({super.key, required this.circleNotifier});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // -------- Form --------
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _pwdFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePwd = true;

  // -------- Appwrite --------
  late final Client _client;
  late final Account _account;

  // -------- Rive --------
  Artboard? _artboard;
  StateMachineController? _sm;
  SMIInput<double>? _iAnim; // único input numérico: "animacion"

  // Estados (deben coincidir con tu .riv)
  static const double kIdle = 0;
  static const double kCorreo = 1;
  static const double kContrasena = 2;
  static const double kNoRegistrado = 3;
  static const double kRegistrado = 4;

  @override
  void initState() {
    super.initState();

    // Appwrite
    _client = Client()
      ..setEndpoint(Environment.appwritePublicEndpoint)
      ..setProject(Environment.appwriteProjectId);
    _account = Account(_client);

    // Rive
    _loadRive();

    // Focos -> animación
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) {
        _setAnim(kCorreo);
      } else if (!_pwdFocus.hasFocus) {
        _setAnim(kIdle);
      }
    });

    _pwdFocus.addListener(() {
      if (_pwdFocus.hasFocus) {
        _setAnim(kContrasena);
      } else if (!_emailFocus.hasFocus) {
        _setAnim(kIdle);
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

  // -------- Rive --------
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
        _sm = controller;
        _iAnim = controller.findInput<double>('animacion');

        // Estado inicial: idle (0)
        _setAnim(kIdle);
      }

      setState(() => _artboard = art);
    } catch (e) {
      debugPrint('Error cargando Rive registro: $e');
    }
  }

  void _setAnim(double v) {
    if (_iAnim == null) return;
    _iAnim!.value = v;
  }

  // -------- Registro --------
  Future<void> _register() async {
    // Si el form es inválido, disparar 3 (no registrado) y no llamar API
    if (!_formKey.currentState!.validate()) {
      _setAnim(kNoRegistrado);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Revisa los campos del formulario.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _account.create(
        userId: ID.unique(),
        email: _emailCtrl.text.trim(),
        password: _pwdCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
      );

      if (!mounted) return;

      // Éxito → 4
      _setAnim(kRegistrado);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ Registro exitoso')));

      // Pequeña pausa para ver la animación
      await Future.delayed(const Duration(milliseconds: 1200));

      widget.circleNotifier.moveToBottom();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      // Fallo → 3
      _setAnim(kNoRegistrado);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Más grande y más abajo
    final double riveHeight = h * 0.96; // ocupa casi toda la altura
    final double riveYOffset = 250; // empuja la animación hacia abajo
    final double cardBottom = bottomInset + 200; // tarjeta muy cerca del borde

    return Scaffold(
      body: Stack(
        children: [
          Background(animateCircle: true),

          // Animación pegada al borde inferior y aún más abajo
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

          // Tarjeta – lo más abajo posible
          Positioned(
            left: 0,
            right: 0,
            bottom: cardBottom,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  width: w * 0.9,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.45),
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
                            color: cs.onSurface,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),

                        _label('Nombre:'),
                        _textField(
                          controller: _nameCtrl,
                          hint: 'Ingrese su nombre',
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Escribe tu nombre'
                              : null,
                          // No tocamos animación para nombre → permanece 0
                        ),
                        const SizedBox(height: 14),

                        _label('Correo electrónico:'),
                        _textField(
                          controller: _emailCtrl,
                          focusNode: _emailFocus,
                          keyboard: TextInputType.emailAddress,
                          hint: 'tucorreo@ejemplo.com',
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'Escribe tu correo';
                            if (!t.contains('@') || !t.contains('.')) {
                              return 'Correo no válido';
                            }
                            return null;
                          },
                          onTapExtra: () => _setAnim(kCorreo),
                          onChangedExtra: (_) => _setAnim(kCorreo),
                        ),
                        const SizedBox(height: 14),

                        _label('Contraseña:'),
                        _textField(
                          controller: _pwdCtrl,
                          focusNode: _pwdFocus,
                          hint: 'Mínimo 6 caracteres',
                          obscure: _obscurePwd,
                          suffix: IconButton(
                            onPressed: () {
                              setState(() => _obscurePwd = !_obscurePwd);
                              _setAnim(kContrasena);
                            },
                            icon: Icon(
                              _obscurePwd
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: cs.onSurface.withOpacity(.7),
                            ),
                          ),
                          validator: (v) {
                            final t = v ?? '';
                            if (t.isEmpty) return 'Escribe una contraseña';
                            if (t.length < 6) return 'Mínimo 6 caracteres';
                            return null;
                          },
                          onTapExtra: () => _setAnim(kContrasena),
                          onChangedExtra: (_) => _setAnim(kContrasena),
                        ),
                        const SizedBox(height: 20),

                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
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
                                    color: cs.onPrimary,
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
                          child: const Text('¿Ya tienes cuenta? Inicia sesión'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Toggle de tema
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: IconButton(
                  tooltip: 'Cambiar tema',
                  onPressed: () => Get.find<ThemeController>().toggleTheme(),
                  icon: Icon(Icons.brightness_6, color: cs.onPrimary),
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
      onTap: () => onTapExtra?.call(),
      onChanged: (v) => onChangedExtra?.call(v),
    );
  }
}
