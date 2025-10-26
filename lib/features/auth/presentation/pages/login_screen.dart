import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rive/rive.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/background.dart';
import 'package:flutter_seguridad_en_casa/core/state/circle_state.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_seguridad_en_casa/core/errors/app_failure.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/forgot_password_screen.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/register_screen.dart';
import 'package:flutter_seguridad_en_casa/features/home/presentation/pages/home_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.circleNotifier});

  final CircleStateNotifier circleNotifier;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ===== Layout & Rive sizing =====
  final double _topShift = 0;
  final double _riveHeight = 350;
  final double _overlap = 150;
  final double _riveScale = 1.8;
  final BoxFit _riveFit = BoxFit.contain;

  // ===== Estado UI =====
  bool _isLoading = false;
  bool _obscurePassword = true;

  // ===== Controladores UI =====
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pwdFocus = FocusNode();

  // ===== Auth =====
  final AuthController _auth = Get.find<AuthController>();

  // ===== Rive =====
  Artboard? _artboard;
  StateMachineController? _riveController;
  SMIInput<double>? _iAnimacion;
  SMIInput<bool>? _iContrasena;
  SMIInput<bool>? _iUsuarioVerificado;
  SMIInput<bool>? _iUsuarioNoVerificado;

  Timer? _idleTimer;
  bool _lockIdle = false;

  static const List<int> _idleValues = [0, 2, 4, 4, 4];
  int _pickIdle() => _idleValues[Random().nextInt(_idleValues.length)];

  // ===== Animacion de salida hacia Registro =====
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

    _loadRive();
    _setupIdleTimer();

    _pwdFocus.addListener(() {
      final bool lostFocus = !_pwdFocus.hasFocus;
      _syncPasswordAnimation(forceIdle: lostFocus && !_passwordVisible);
      setState(() {});
    });

    _navCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    final curve = CurvedAnimation(
      parent: _navCtrl,
      curve: Curves.easeInOutCubic,
    );

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
    _riveController?.dispose();
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
        _iContrasena = controller.findInput<bool>('contrasena');
        _iUsuarioVerificado =
            controller.findInput<bool>('usuario_verificado');
        _iUsuarioNoVerificado =
            controller.findInput<bool>('usuario_no_verificado');

        if (kDebugMode) {
          for (final input in controller.inputs) {
            debugPrint('Rive input -> ${input.name}: ${input.runtimeType}');
          }
        }

        _setAnimacion(_pickIdle());
        _setResultState(null);
        _syncPasswordAnimation(forceIdle: true);
      }

      setState(() => _artboard = art);
    } catch (e) {
      debugPrint('Error cargando Rive: ${e.toString()}');
    }
  }

  void _setAnimacion(num value) {
    if (_iAnimacion == null) return;
    _iAnimacion!.value = value.toDouble();
    if (kDebugMode) debugPrint('animacion <- $value');
  }

  void _setupIdleTimer() {
    _idleTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_lockIdle) _randomIdle();
    });
  }

  void _randomIdle() => _setAnimacion(_pickIdle());

  // ===== Acciones UI =====
  bool get _passwordVisible => !_obscurePassword;

  void _syncPasswordAnimation({bool forceIdle = false}) {
    _iContrasena?.value = _passwordVisible;
    if (_isLoading) return;

    final bool hasFocus = _pwdFocus.hasFocus;
    final bool visible = _passwordVisible;

    if (visible) {
      _lockIdle = true;
      _setAnimacion(2);
      return;
    }

    if (hasFocus) {
      _lockIdle = true;
      _setAnimacion(1);
      return;
    }

    _lockIdle = false;
    if (forceIdle) {
      _randomIdle();
    }
  }

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
    _syncPasswordAnimation(forceIdle: !_passwordVisible && !_pwdFocus.hasFocus);
  }

  void _setResultState(bool? success) {
    _iUsuarioVerificado?.value = success == true;
    _iUsuarioNoVerificado?.value = success == false;
  }

  Future<void> _playSuccessSequence() async {
    _setResultState(true);
    _setAnimacion(4);
    await Future.delayed(const Duration(milliseconds: 3400));
  }

  Future<void> _playErrorSequence() async {
    _setResultState(false);
    _setAnimacion(4);
    await Future.delayed(const Duration(milliseconds: 3400));
    _setResultState(null);
    _randomIdle();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.login.fillFields'.tr)),
      );
      unawaited(_playErrorSequence());
      return;
    }

    setState(() {
      _isLoading = true;
      _lockIdle = true;
    });
    _setResultState(null);
    _setAnimacion(3);

    bool success = false;

    try {
      await _auth.signIn(email: email, password: password);
      success = true;
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('auth.error.unexpected'.trParams({'error': e.toString()}))),
        );
      }
    }
    if (!mounted) return;

    if (success) {
      await _playSuccessSequence();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _lockIdle = false;
      });
      _syncPasswordAnimation(forceIdle: true);
      widget.circleNotifier.moveToCenter();
      Get.offAll(() => HomePage(circleNotifier: widget.circleNotifier));
      return;
    } else {
      await _playErrorSequence();
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _lockIdle = false;
    });
    _randomIdle();
  }

  void _goToForgotPassword() {
    Get.to(() => const ForgotPasswordScreen());
  }

  Future<void> _onCreateAccountPressed() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    widget.circleNotifier.moveToCenter();

    try {
      await _navCtrl.forward();
      if (!mounted) return;

      await Get.to(() => RegisterScreen(circleNotifier: widget.circleNotifier));
      if (!mounted) return;

      widget.circleNotifier.moveToBottom();
      _navCtrl.reset();
    } finally {
      if (mounted) {
        setState(() => _leaving = false);
      }
    }
  }

  // ===== BUILD =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: widget.circleNotifier,
            builder: (_, showCircleCenter, __) =>
                Background(animateCircle: showCircleCenter),
          ),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _fadeText,
                    child: SlideTransition(
                      position: _formUp,
                      child: _buildLoginCard(context),
                    ),
                  ),
                  const SizedBox(height: 40),
                  FadeTransition(
                    opacity: _fadeText,
                    child: SlideTransition(
                      position: _ctaTextLeft,
                      child: Center(
                        child: Text(
                          'Todavia no te has registrado?',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
        ],
      ),
    );
  }

  Widget _buildLoginCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
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
              'auth.login.title'.tr,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 30,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'auth.login.emailLabel'.tr,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                          ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            cursorColor: Theme.of(context).colorScheme.primary,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'auth.login.passwordLabel'.tr,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            focusNode: _pwdFocus,
            obscureText: _obscurePassword,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            cursorColor: Theme.of(context).colorScheme.primary,
            onTap: _syncPasswordAnimation,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              suffixIcon: IconButton(
                onPressed: _togglePasswordVisibility,
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
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
              child: Text('auth.login.forgot'.tr),
            ),
          ),
          const SizedBox(height: 8),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
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
                    'auth.login.submit'.tr,
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}



