// lib/main.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:appwrite/appwrite.dart';

import 'config/environment.dart';
import 'controllers/theme_controller.dart';
import 'theme/app_theme.dart';

import 'circle_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_page.dart';

// 👇 Servicio global que escucha los deep links
import 'services/deeplink_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Appwrite
  final client = Client()
    ..setEndpoint(Environment.appwritePublicEndpoint)
    ..setProject(Environment.appwriteProjectId);

  final account = Account(client);

  // ¿Hay sesión?
  bool loggedIn = false;
  try {
    await account.get();
    loggedIn = true;
  } catch (_) {
    loggedIn = false;
  }

  runApp(MyApp(account: account, loggedIn: loggedIn));
}

class MyApp extends StatefulWidget {
  final Account account;
  final bool loggedIn;

  const MyApp({super.key, required this.account, required this.loggedIn});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final CircleStateNotifier _circleNotifier;
  late final ThemeController _themeController;

  @override
  void initState() {
    super.initState();
    _circleNotifier = CircleStateNotifier();
    _themeController = Get.put(ThemeController(), permanent: true);

    // Importante: inicia el listener de deep links cuando ya existe el árbol de navegación
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeeplinkService().init(); // escucha casa_segura://reset?userId=&secret=
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Casa Segura',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeController.themeMode,
        home: widget.loggedIn
            ? HomePage(account: widget.account, circleNotifier: _circleNotifier)
            : LoginScreen(circleNotifier: _circleNotifier),
      ),
    );
  }
}
