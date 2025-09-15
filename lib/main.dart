import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:get/get.dart';
import 'config/environment.dart';
import 'circle_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_page.dart';
import 'controllers/theme_controller.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa cliente de Appwrite
  Client client = Client()
    ..setEndpoint(
      Environment.appwritePublicEndpoint,
    ) // ej: "https://fra.cloud.appwrite.io/v1"
    ..setProject(Environment.appwriteProjectId); // tu Project ID

  Account account = Account(client);

  // Verificamos si hay sesión activa
  bool loggedIn = false;
  try {
    await account.get();
    loggedIn = true;
  } catch (_) {
    loggedIn = false;
  }

  runApp(MyApp(account: account, loggedIn: loggedIn));
}

class MyApp extends StatelessWidget {
  final Account account;
  final bool loggedIn;

  const MyApp({super.key, required this.account, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    final circleNotifier = CircleStateNotifier();

    final themeController = Get.put(ThemeController());

    return Obx(
      () => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Casa Segura',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeController.themeMode,
        home: loggedIn
            ? HomePage(account: account, circleNotifier: circleNotifier)
            : LoginScreen(circleNotifier: circleNotifier),
      ),
    );
  }
}
