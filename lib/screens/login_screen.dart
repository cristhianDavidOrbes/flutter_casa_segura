// lib/screens/login_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// UI propia
import '../widgets/background.dart';
import 'register_screen.dart';
import '../circle_state.dart';
import '../widgets/theme_toggle_button.dart';

// Appwrite
import 'package:appwrite/appwrite.dart';
import '../config/environment.dart';
import 'home_page.dart';

// Rive
import 'package:rive/rive.dart';

// Recuperación
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final CircleStateNotifier circleNotifier;
  const LoginScreen({super.key, required this.circleNotifier});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ===== Layout & Rive sizing =====
  final double _topShift = 0;
  double _riveHeight = 350;
  double _overlap = 150;
  double _riveScale = 1.8;
  BoxFit _riveFit = BoxFit.contain;

  // ===== Estado UI =====
  bool _isLoading = false;
  bool _obscurePassword = true;

  // ===== Controladores UI =====
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pwdFocus = FocusNode();

  // ===== Appwrite =====
  late final Client client;
  late final Account account;

  // ===== Rive =====
  Artboard? _artboard;
  StateMachineController? _riveController;
  SMIInput<double>? _iAnimacion; // 0/2/4 idles + 1 (focus) + 3 (cargando)
  SMIInput<bool>? _iContrasena;

  Timer? _idleTimer;
  bool _lockIdle = false;

  static const List<int> _idleValues = [0, 2, 4, 4, 4];
  int _pickIdle() => _idleValues[Random().nextInt(_idleValues.length)];

  // ===== Animación de salida hacia Registro (más lejos + fade) =====
  late final AnimationController _navCtrl;
  late final Animation<Offset> _riveUp;
  late final Animation<Offset> _formUp;
  late final Animation<Offset> _ctaTextLeft;
  late final Animation<Offset> _ctaBtnRight;
  late final Animation<double> _fadeTop;
  late final Animation<double> _fadeText;
  late final Animation<double> _fadeBtn;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();

    client = Client()
      ..setEndpoint(Environment.appwritePublicEndpoint)
      ..setProject(Environment.appwriteProjectId);
    account = Account(client);

    // Rive
    _loadRive();
    _setupIdleTimer();

    // Focus contraseña -> animaciones de ojo
    _pwdFocus.addListener(() {
      if (_pwdFocus.hasFocus) {
        _lockIdle = true;
        _setAnimacion(1);
        _iContrasena?.value = _obscurePassword;
      } else {
        _lockIdle = false;
        _randomIdle();
      }
      setState(() {});
    });

    // Controller y Tweens para la animación de salida
    _navCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    final curve = CurvedAnimation(
      parent: _navCtrl,
      curve: Curves.easeInOutCubic,
    );

    // Mover MUY lejos (2.6–2.8 veces su tamaño) + desvanecer
    _riveUp = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -2.6),
    ).animate(curve);
    _formUp = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -2.6),
    ).animate(curve);
    _ctaTextLeft = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-2.8, 0),
    ).animate(curve);
    _ctaBtnRight = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(2.8, 0),
    ).animate(curve);

    _fadeTop = Tween<double>(begin: 1, end: 0).animate(curve);
    _fadeText = Tween<double>(begin: 1, end: 0).animate(curve);
    _fadeBtn = Tween<double>(begin: 1, end: 0).animate(curve);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pwdFocus.dispose();
    _idleTimer?.cancel();
    _navCtrl.dispose();
    super.dispose();
  }

  // ===== Rive =====
  Future<void> _loadRive() async {
    try {
      final file = await RiveFile.asset('assets/rive/camara.riv');
      final art =
          file.artboardByName('Camara_interactiva') ?? file.mainArtboard;

      final controller = StateMachineController.fromArtboard(
        art,
        'loginMaching',
      );

      if (controller != null) {
        art.addController(controller);
        _riveController = controller;

        _iAnimacion = controller.findInput<double>('animacion');
        _iContrasena = controller.findInput<bool>('contraseña');

        if (kDebugMode) {
          for (final i in controller.inputs) {
            debugPrint('Rive input -> ${i.name}: ${i.runtimeType}');
          }
        }

        _setAnimacion(_pickIdle());
      }

      setState(() => _artboard = art);
    } catch (e) {
      debugPrint('Error cargando Rive: $e');
    }
  }

  void _setAnimacion(num v) {
    if (_iAnimacion == null) return;
    _iAnimacion!.value = v.toDouble();
    if (kDebugMode) debugPrint('animacion <- $v');
  }

  void _setupIdleTimer() {
    _idleTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_lockIdle) _randomIdle();
    });
  }

  void _randomIdle() => _setAnimacion(_pickIdle());

  // ===== Acciones UI =====
  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
    _iContrasena?.value = _obscurePassword;
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _lockIdle = true;
    });
    _setAnimacion(3); // cargando

    try {
      await account.createEmailPasswordSession(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      Get.offAll(
        () => HomePage(account: account, circleNotifier: widget.circleNotifier),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _lockIdle = false;
        });
        _randomIdle();
      }
    }
  }

  void _goToForgotPassword() {
    Get.to(() => const ForgotPasswordScreen());
  }

  Future<void> _onCreateAccountPressed() async {
    if (_leaving) return;
    setState(() => _leaving = true);

    // Mueve el círculo al centro mientras sale la UI
    widget.circleNotifier.moveToCenter();

    try {
      await _navCtrl.forward();
    } finally {
      if (!mounted) return;

      await Get.to(() => RegisterScreen(circleNotifier: widget.circleNotifier));

      // Al volver del registro, regresa todo a su posición
      widget.circleNotifier.moveToBottom();
      if (!mounted) return;
      _navCtrl.reset();
      setState(() => _leaving = false);
    }
  }

  // ===== BUILD =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fondo con círculos
          ValueListenableBuilder<bool>(
            valueListenable: widget.circleNotifier,
            builder: (_, showCircleCenter, __) =>
                Background(animateCircle: showCircleCenter),
          ),

          // Animación Rive arriba (slide up MUY lejos + fade)
          if (_artboard != null)
            Positioned(
              top: _topShift,
              left: 0,
              right: 0,
              height: 20 + _riveHeight,
              child: FadeTransition(
                opacity: _fadeTop,
                child: SlideTransition(
                  position: _riveUp,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Transform.scale(
                        scale: _riveScale,
                        child: Rive(artboard: _artboard!, fit: _riveFit),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Contenido
          SafeArea(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                (_riveHeight + 30 + _topShift - _overlap).clamp(
                  0,
                  double.infinity,
                ),
                16,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tarjeta de login (slide up MUY lejos + fade)
                  FadeTransition(
                    opacity: _fadeTop,
                    child: SlideTransition(
                      position: _formUp,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(4, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                'Inicio de sesión',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 30,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Email
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Correo electrónico:',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              cursorColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Password
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Contraseña:',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passwordController,
                              focusNode: _pwdFocus,
                              obscureText: _obscurePassword,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              cursorColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              onTap: () {
                                _setAnimacion(1);
                                _iContrasena?.value = _obscurePassword;
                              },
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                suffixIcon: IconButton(
                                  onPressed: _togglePasswordVisibility,
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _goToForgotPassword,
                                child: const Text('¿Olvidaste tu contraseña?'),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Botón login
                            _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 50,
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                    ),
                                    onPressed: _login,
                                    child: Text(
                                      'Iniciar Sesión',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // CTA inferior: texto a la izquierda (MUY lejos) + fade
                  FadeTransition(
                    opacity: _fadeText,
                    child: SlideTransition(
                      position: _ctaTextLeft,
                      child: Center(
                        child: Text(
                          '¿Todavía no te has registrado?',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onBackground,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botón a la derecha (MUY lejos) + fade
                  FadeTransition(
                    opacity: _fadeBtn,
                    child: SlideTransition(
                      position: _ctaBtnRight,
                      child: Center(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: _onCreateAccountPressed,
                          child: Text(
                            'Crear una cuenta',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Botón de tema – siempre arriba a la derecha
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: ThemeToggleButton(
                  color: Theme.of(context).colorScheme.onPrimary,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
