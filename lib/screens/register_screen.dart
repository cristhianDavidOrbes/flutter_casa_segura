// lib/screens/register_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// Fondo animado + círculo
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
  // ---------- Form ----------
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _pwdFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePwd = true;

  // ---------- Appwrite ----------
  late final Client _client;
  late final Account _account;

  // ---------- Rive ----------
  Artboard? _artboard;
  StateMachineController? _sm;

  // Inputs (nombres EXACTOS en tu .riv)
  SMIInput<bool>? _iCorreo; // "correo"
  SMIInput<bool>? _iContrasena; // "contraseña"
  SMIInput<bool>? _iRegistrarse; // "registrarse"
  SMIInput<bool>? _iRegistrado; // "registrado"
  SMIInput<bool>? _iNoRegistrado; // "No_registrado"

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

    // Focos -> animaciones
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) {
        _setBool(_iCorreo, true);
        _setBool(_iContrasena, false);
      } else {
        _setBool(_iCorreo, false);
      }
    });

    _pwdFocus.addListener(() {
      if (_pwdFocus.hasFocus) {
        _setBool(_iContrasena, true);
        _setBool(_iCorreo, false);
      } else {
        _setBool(_iContrasena, false);
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

  // ---------- Rive ----------
  Future<void> _loadRive() async {
    try {
      // Asegúrate de tener este asset en pubspec.yaml
      final file = await RiveFile.asset('assets/rive/registro.riv');
      // Artboard y StateMachine EXACTOS
      final art = file.artboardByName('registrarse') ?? file.mainArtboard;

      final controller = StateMachineController.fromArtboard(
        art,
        'register_maching',
      );

      if (controller != null) {
        art.addController(controller);
        _sm = controller;

        _iCorreo = controller.findInput<bool>('correo');
        _iContrasena = controller.findInput<bool>('contraseña');
        _iRegistrarse = controller.findInput<bool>('registrarse');
        _iRegistrado = controller.findInput<bool>('registrado');
        _iNoRegistrado = controller.findInput<bool>('No_registrado');

        // Estado inicial
        _setBool(_iRegistrarse, true);
        _setBool(_iCorreo, false);
        _setBool(_iContrasena, false);
        _setBool(_iRegistrado, false);
        _setBool(_iNoRegistrado, false);
      }

      setState(() => _artboard = art);
    } catch (e) {
      debugPrint('Error cargando Rive registro: $e');
    }
  }

  void _setBool(SMIInput<bool>? i, bool v) {
    if (i == null) return;
    i.value = v;
  }

  Future<void> _pulse(SMIInput<bool>? i, {int ms = 1100}) async {
    if (i == null) return;
    i.value = true;
    await Future.delayed(Duration(milliseconds: ms));
    i.value = false;
  }

  // ---------- Registro ----------
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    // “Modo registrarse” activo para que la SM elija el flujo correcto
    _setBool(_iRegistrarse, true);

    setState(() => _isLoading = true);

    try {
      await _account.create(
        userId: ID.unique(),
        email: _emailCtrl.text.trim(),
        password: _pwdCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
      );

      if (!mounted) return;

      // Éxito: dispara “registrado”
      _pulse(_iRegistrado);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ Registro exitoso')));

      // Vuelve al login con la animación del círculo
      await Future.delayed(const Duration(milliseconds: 1200));
      widget.circleNotifier.moveToBottom();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      // Error: dispara “No_registrado”
      _pulse(_iNoRegistrado);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    // ====== KNOBS (ajusta a tu gusto) ======
    final double riveHeight = h * 0.62; // alto del área de Rive
    final double riveScale = 1.10; // zoom de la animación
    final double riveBottomOffset = -106; // NEGATIVO => más abajo
    final double liftAboveRive = 180; // cuánto sube la tarjeta

    // Mantener tarjeta y animación “alineadas”
    final double cardBottom = riveBottomOffset + riveHeight - liftAboveRive;

    return Scaffold(
      body: Stack(
        children: [
          Background(animateCircle: true),

          // Animación Rive pegada (o salida) al fondo
          if (_artboard != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: riveBottomOffset,
              height: riveHeight,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Transform.scale(
                    scale: riveScale,
                    child: Rive(
                      artboard: _artboard!,
                      fit: BoxFit
                          .contain, // prueba BoxFit.cover si quieres llenar más
                    ),
                  ),
                ),
              ),
            ),

          // Tarjeta por encima de la animación
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
                        ),
                        const SizedBox(height: 14),

                        _label('Correo electrónico:'),
                        _textField(
                          controller: _emailCtrl,
                          hint: 'tucorreo@ejemplo.com',
                          focusNode: _emailFocus,
                          keyboard: TextInputType.emailAddress,
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'Escribe tu correo';
                            if (!t.contains('@') || !t.contains('.')) {
                              return 'Correo no válido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        _label('Contraseña:'),
                        _textField(
                          controller: _pwdCtrl,
                          hint: 'Mínimo 6 caracteres',
                          focusNode: _pwdFocus,
                          obscure: _obscurePwd,
                          suffix: IconButton(
                            onPressed: () {
                              setState(() => _obscurePwd = !_obscurePwd);
                              // refuerza estado de “contraseña”
                              _setBool(_iContrasena, true);
                              _setBool(_iCorreo, false);
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

          // Botón de tema (arriba-derecha)
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

  // ---------- helpers UI ----------
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
      onTap: () {
        if (focusNode == _emailFocus) {
          _setBool(_iCorreo, true);
          _setBool(_iContrasena, false);
        } else if (focusNode == _pwdFocus) {
          _setBool(_iContrasena, true);
          _setBool(_iCorreo, false);
        }
      },
      onChanged: (_) {
        if (focusNode == _emailFocus) {
          _setBool(_iCorreo, true);
        } else if (focusNode == _pwdFocus) {
          _setBool(_iContrasena, true);
        }
      },
    );
  }
}
