import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/config/environment.dart';
import 'controllers/theme_controller.dart';
import 'controllers/locale_controller.dart';
import 'theme/app_theme.dart';
import 'core/state/circle_state.dart';
import 'features/auth/infrastructure/auth_binding.dart';
import 'features/auth/infrastructure/deeplink_service.dart';
import 'features/auth/presentation/pages/login_screen.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'data/hive/ai_comment.dart';
import 'data/hive/ai_comment_store.dart';
import 'screens/splash_screen.dart';
import 'features/security/domain/security_event.dart';
import 'features/security/data/security_event_store.dart';
import 'features/security/application/notification_service.dart';
import 'features/security/application/push_notification_service.dart';
import 'features/ai/domain/security_chat_message.dart';
import 'features/ai/data/security_chat_store.dart';
import 'core/localization/app_translations.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await dotenv.load(fileName: '.env');
  Environment.ensureLoaded();

  await GetStorage.init();
  await Hive.initFlutter();
  Hive.registerAdapter(AiCommentAdapter());
  Hive.registerAdapter(SecurityEventAdapter());
  Hive.registerAdapter(SecurityChatMessageAdapter());
  await AiCommentStore.init();
  await SecurityEventStore.init();
  await SecurityChatStore.init();
  await NotificationService.instance.init();

  await Supabase.initialize(
    url: Environment.supabaseUrl,
    anonKey: Environment.supabaseAnonKey,
  );

  final pushService = Get.put(PushNotificationService(), permanent: true);
  try {
    await pushService.init();
  } catch (e, st) {
    debugPrint('PushNotificationService init failed: $e\n$st');
    rethrow;
  }

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
  late final LocaleController _localeController;

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
    _localeController = Get.put(LocaleController(), permanent: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeeplinkService().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'app.name'.tr,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeController.themeMode,
        translations: AppTranslations(),
        locale: _localeController.locale.value,
        fallbackLocale: const Locale('es', 'ES'),
        supportedLocales: _localeController.locales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SplashScreen(
          nextPage: widget.loggedIn
              ? HomePage(circleNotifier: _circleNotifier)
              : LoginScreen(circleNotifier: _circleNotifier),
        ),
      ),
    );
  }
}
