import "package:flutter_dotenv/flutter_dotenv.dart";

class Environment {
  Environment._();

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get supabaseResetRedirect =>
      dotenv.env['SUPABASE_RESET_REDIRECT'] ?? 'casasegura://reset';
  static String get supabaseEmailRedirect =>
      dotenv.env['SUPABASE_EMAIL_REDIRECT'] ?? supabaseResetRedirect;

  static void ensureLoaded() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Supabase environment variables are missing. Check your .env file.',
      );
    }
  }
}
