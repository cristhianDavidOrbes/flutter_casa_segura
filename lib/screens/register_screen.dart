import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/background.dart';
import '../circle_state.dart';

import 'package:appwrite/appwrite.dart';
import '../config/environment.dart';
import '../controllers/theme_controller.dart';

class RegisterScreen extends StatefulWidget {
  final CircleStateNotifier circleNotifier;

  const RegisterScreen({super.key, required this.circleNotifier});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late Client client;
  late Account account;
  bool _isLoading = false;
  bool _obscureRegPassword = true;

  @override
  void initState() {
    super.initState();
    client = Client()
      ..setEndpoint(Environment.appwritePublicEndpoint)
      ..setProject(Environment.appwriteProjectId);
    account = Account(client);
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await account.create(
        userId: ID.unique(),
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("✅ Registro exitoso")));

        widget.circleNotifier.moveToBottom();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ Error: $e")));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          // Theme toggle button (top-right)
          Background(animateCircle: true),

          Center(
            child: SingleChildScrollView(
              child: Container(
                width: screenWidth * 0.85,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 10,
                      offset: Offset(4, 4),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Text(
                          "Crear Cuenta",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Nombre
                      _label("Nombre:"),
                      _inputField(_nameController, false, "Ingrese su nombre"),
                      const SizedBox(height: 20),

                      // Email
                      _label("Correo electrónico:"),
                      _inputField(
                        _emailController,
                        false,
                        "Ingrese un correo válido",
                      ),
                      const SizedBox(height: 20),

                      // Contraseña
                      _label("Contraseña:"),
                      _inputField(
                        _passwordController,
                        true,
                        "Mínimo 6 caracteres",
                      ),
                      const SizedBox(height: 30),

                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
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
                              onPressed: _register,
                              child: Text(
                                "Registrarse",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                              ),
                            ),
                      const SizedBox(height: 20),

                      TextButton(
                        onPressed: () {
                          widget.circleNotifier.moveToBottom();
                          Navigator.pop(context);
                        },
                        child: const Text(
                          "¿Ya tienes cuenta? Inicia sesión",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Theme toggle (top-right, always on top)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: IconButton(
                  tooltip: 'Cambiar tema',
                  onPressed: () => Get.find<ThemeController>().toggleTheme(),
                  icon: Icon(
                    Icons.brightness_6,
                    color: Theme.of(context).colorScheme.onPrimary,
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
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _inputField(
    TextEditingController controller,
    bool obscure,
    String errorText,
  ) {
    final isPassword = obscure;
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? _obscureRegPassword : false,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      cursorColor: Theme.of(context).colorScheme.primary,
      validator: (value) => (value == null || value.isEmpty) ? errorText : null,
      decoration: InputDecoration(
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        suffixIcon: isPassword
            ? IconButton(
                onPressed: () => setState(() {
                  _obscureRegPassword = !_obscureRegPassword;
                }),
                icon: Icon(
                  _obscureRegPassword ? Icons.visibility_off : Icons.visibility,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
