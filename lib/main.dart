// lib/main.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:appwrite/appwrite.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'config/environment.dart';
import 'controllers/theme_controller.dart';
import 'theme/app_theme.dart';
import 'circle_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_page.dart';
import 'services/deeplink_service.dart';
import 'data/hive/ai_comment.dart';
import 'data/hive/ai_comment_store.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(AiCommentAdapter());
  await AiCommentStore.init();

  final client = Client()
    ..setEndpoint(Environment.appwritePublicEndpoint)
    ..setProject(Environment.appwriteProjectId);
  final account = Account(client);

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeeplinkService().init();
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
        home: SplashScreen(
          nextPage: widget.loggedIn
              ? HomePage(
                  account: widget.account,
                  circleNotifier: _circleNotifier,
                )
              : LoginScreen(circleNotifier: _circleNotifier),
        ),
      ),
    );
  }
}
