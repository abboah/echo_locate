import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-level configuration, read from the gitignored `.env` file
/// (see `.env.example` for setup — paste your Supabase URL + publishable
/// key there). While the values are empty the app runs fully on mock
/// repositories.
///
/// Note: `.env` keeps the key out of the git repo; it is still bundled in
/// the APK like any config. That's fine — the Supabase publishable key is
/// designed to be public, and row-level security protects the data.
class AppConfig {
  AppConfig._();

  static String get supabaseUrl => dotenv.maybeGet('SUPABASE_URL') ?? '';
  static String get supabaseKey => dotenv.maybeGet('SUPABASE_KEY') ?? '';

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Web OAuth client ID, used on Android as `serverClientId` so Google
  /// issues an ID token addressed to the client Supabase verifies against.
  static String get googleWebClientId =>
      dotenv.maybeGet('GOOGLE_WEB_CLIENT_ID') ?? '';

  static bool get hasGoogleSignIn => googleWebClientId.isNotEmpty;
}
