// login_screen.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'widgets/background.dart';
import 'register_screen.dart';
import 'circle_state.dart';

// 👇 Appwrite
import 'package:appwrite/appwrite.dart';
import '../config/environment.dart';
import 'HomePage.dart';

class LoginScreen extends StatefulWidget {
  final CircleStateNotifier circleNotifier;
  const LoginScreen({super.key, required this.circleNotifier});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool animate = false;
  bool hideWidgets = false;
  bool _isLoading = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late Client client;
  late Account account;

  @override
  void initState() {
    super.initState();
    client = Client()
      ..setEndpoint(Environment.appwritePublicEndpoint)
      ..setProject(Environment.appwriteProjectId);
    account = Account(client);
  }

  void _onCreateAccountPressed() {
    setState(() {
      animate = true;
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      setState(() {
        hideWidgets = true;
      });

      widget.circleNotifier.moveToCenter();

      Future.delayed(const Duration(milliseconds: 800), () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                RegisterScreen(circleNotifier: widget.circleNotifier),
          ),
        ).then((_) {
          setState(() {
            animate = false;
            hideWidgets = false;
          });
          widget.circleNotifier.moveToBottom();
        });
      });
    });
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);

    try {
      await account.createEmailPasswordSession(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Sesión iniciada con éxito")),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomePage(
              account: account,
              circleNotifier: widget.circleNotifier,
            ),
          ),
        );
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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: widget.circleNotifier,
            builder: (context, showCircleCenter, _) {
              return Background(animateCircle: showCircleCenter);
            },
          ),

          if (!hideWidgets) ...[
            AnimatedPositioned(
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOut,
              bottom: animate ? screenHeight * 1.5 : 300,
              left: screenWidth * 0.1,
              child: Container(
                width: screenWidth * 0.8,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 10,
                      offset: const Offset(4, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        "Inicio de sesión",
                        style: TextStyle(
                          color: Color.fromARGB(255, 202, 202, 202),
                          fontSize: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Correo electrónico:",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Contraseña:",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 50,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            onPressed: _login,
                            child: const Text(
                              "Iniciar Sesión",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOut,
              bottom: 210,
              left: animate ? -screenWidth : 90,
              child: const Text(
                "¿Todavía no te has registrado?",
                style: TextStyle(color: Colors.black87, fontSize: 16),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOut,
              bottom: 140,
              right: animate ? -screenWidth : 123,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Colors.deepPurple),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _onCreateAccountPressed,
                child: const Text(
                  "Crear una cuenta",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOut,
              bottom: animate ? -screenHeight * 2 : 20,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Row(
                    children: const [
                      Expanded(child: Divider(thickness: 1)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          "O inicia sesión con",
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                      ),
                      Expanded(child: Divider(thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _socialCircle(
                        const FaIcon(
                          FontAwesomeIcons.google,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 20),
                      _socialCircle(
                        const FaIcon(
                          FontAwesomeIcons.github,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 20),
                      _socialCircle(
                        const FaIcon(
                          FontAwesomeIcons.facebook,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _socialCircle(Widget icon) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black,
          blurRadius: 6,
          offset: const Offset(2, 2),
        ),
      ],
    ),
    child: icon,
  );
}
