import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/config/environment.dart';
import 'controllers/theme_controller.dart';
import 'theme/app_theme.dart';
import 'core/state/circle_state.dart';
import 'features/auth/infrastructure/auth_binding.dart';
import 'features/auth/infrastructure/deeplink_service.dart';
import 'features/auth/presentation/pages/login_screen.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'data/hive/ai_comment.dart';
import 'data/hive/ai_comment_store.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await dotenv.load(fileName: '.env');
  Environment.ensureLoaded();

  await Hive.initFlutter();
  Hive.registerAdapter(AiCommentAdapter());
  await AiCommentStore.init();

  await Supabase.initialize(
    url: Environment.supabaseUrl,
    anonKey: Environment.supabaseAnonKey,
  );

  AuthBinding.ensureInitialized();

  final supabase = Supabase.instance.client;
  final loggedIn = supabase.auth.currentSession != null;

  runApp(MyApp(loggedIn: loggedIn));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.loggedIn});

  final bool loggedIn;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final CircleStateNotifier _circleNotifier;
  late final ThemeController _themeController;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<CircleStateNotifier>()) {
      _circleNotifier = Get.find<CircleStateNotifier>();
    } else {
      _circleNotifier = Get.put<CircleStateNotifier>(
        CircleStateNotifier(),
        permanent: true,
      );
    }
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
              ? HomePage(circleNotifier: _circleNotifier)
              : LoginScreen(circleNotifier: _circleNotifier),
        ),
      ),
    );
  }
}
