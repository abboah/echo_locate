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

  /// Forces the mock repositories even when `.env` is populated:
  ///
  /// ```
  /// flutter run --dart-define=FORCE_MOCKS=true
  /// ```
  ///
  /// For demonstrating the app where there is no usable network — a lecture
  /// theatre, an emulator with no DNS — and for exercising the UI against the
  /// seeded KNUST Library route without a round trip. A compile-time constant,
  /// so a release build cannot be talked into it at runtime.
  static const bool forceMocks = bool.fromEnvironment('FORCE_MOCKS');

  static bool get hasSupabase =>
      !forceMocks && supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Web OAuth client ID, used on Android as `serverClientId` so Google
  /// issues an ID token addressed to the client Supabase verifies against.
  static String get googleWebClientId =>
      dotenv.maybeGet('GOOGLE_WEB_CLIENT_ID') ?? '';

  static bool get hasGoogleSignIn => googleWebClientId.isNotEmpty;
}
