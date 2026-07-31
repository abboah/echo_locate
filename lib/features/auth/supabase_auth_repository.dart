import 'package:google_sign_in/google_sign_in.dart';
// Supabase also exports an `AuthUser`; ours (the app model) wins.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/config/app_config.dart';
import '../../core/models/auth_user.dart';
import '../../data/repository_mixin.dart';
import 'auth_repository.dart';

/// Supabase-backed auth. Registered instead of [MockAuthRepository] when
/// `AppConfig.hasSupabase` is true — the Blocs/pages never know the
/// difference. Sessions persist across restarts via supabase_flutter.
///
/// Email and Google are both live. Apple stays "coming soon": it needs a
/// paid Apple Developer account, and the thesis is demoed on Android.
class SupabaseAuthRepository with RepositoryMixin implements AuthRepository {
  SupabaseAuthRepository(this._client, {GoogleSignIn? googleSignIn})
      : _google = googleSignIn ?? GoogleSignIn.instance;

  final SupabaseClient _client;
  final GoogleSignIn _google;
  bool _googleReady = false;

  AuthUser? _map(User? user) {
    if (user == null) return null;
    final email = user.email ?? '';
    final name = user.userMetadata?['full_name'] as String? ??
        (email.contains('@') ? email.split('@').first : 'Mapper');
    return AuthUser(id: user.id, fullName: name, email: email);
  }

  @override
  AuthUser? get currentUser => _map(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges =>
      _client.auth.onAuthStateChange.map((e) => _map(e.session?.user));

  @override
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  }) {
    return runOperation('sign_in_email', () async {
      try {
        final res = await _client.auth
            .signInWithPassword(email: email.trim(), password: password);
        return _map(res.user)!;
      } on AuthException catch (e) {
        throw OperationFailure(_friendly(e));
      }
    });
  }

  @override
  Future<AuthUser> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) {
    return runOperation('sign_up_email', () async {
      if (fullName.trim().isEmpty) {
        throw const OperationFailure('Enter your full name');
      }
      // Same rule (and message) as the design's error state.
      if (password.length < 8) {
        throw const OperationFailure('Use at least 8 characters');
      }
      try {
        final res = await _client.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'full_name': fullName.trim()},
        );
        if (res.session == null) {
          // "Confirm email" is enabled on the Supabase project.
          throw const OperationFailure(
            'Check your email to confirm your account, then sign in.',
          );
        }
        return _map(res.user)!;
      } on AuthException catch (e) {
        throw OperationFailure(_friendly(e));
      }
    });
  }

  /// Native Google sign-in: the Android Credential Manager sheet returns an
  /// ID token, which Supabase verifies (signature, expiry, and audience
  /// against the client IDs configured on the Google provider) and exchanges
  /// for a session. No browser redirect, so no deep-link setup.
  ///
  /// No nonce is requested, so Google omits the claim and Supabase skips that
  /// check — leave "Skip nonce checks" OFF in the dashboard regardless.
  @override
  Future<AuthUser> signInWithGoogle() {
    return runOperation('sign_in_google', () async {
      if (!AppConfig.hasGoogleSignIn) {
        throw const OperationFailure(
          'Google sign-in is not configured on this build',
        );
      }

      final GoogleSignInAccount account;
      try {
        if (!_googleReady) {
          await _google.initialize(
            serverClientId: AppConfig.googleWebClientId,
          );
          _googleReady = true;
        }
        account = await _google.authenticate();
      } on GoogleSignInException catch (e) {
        throw OperationFailure(_friendlyGoogle(e));
      }

      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const OperationFailure(
          'Google did not return a sign-in token. Please try again.',
        );
      }

      try {
        final res = await _client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );
        return _map(res.user)!;
      } on AuthException catch (e) {
        throw OperationFailure(_friendly(e));
      }
    });
  }

  String _friendlyGoogle(GoogleSignInException e) => switch (e.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted =>
          'Google sign-in cancelled',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google sign-in is not set up correctly for this app',
        _ => 'Could not sign in with Google. Please try again.',
      };

  @override
  Future<AuthUser> signInWithApple() async {
    throw const OperationFailure(
      'Apple sign-in is coming soon — use email for now',
    );
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    RepositoryMixin.clearEphemeralCache();
  }

  String _friendly(AuthException e) {
    // Network-level failure (no route, DNS, refused): gotrue wraps the raw
    // ClientException/SocketException text in a retryable AuthException —
    // never show that to a person.
    if (e is AuthRetryableFetchException) {
      return 'Could not reach the server. '
          'Check your internet connection and try again.';
    }
    return switch (e.message) {
      // Same 400 for wrong password AND unknown account (anti-enumeration).
      'Invalid login credentials' => 'Wrong email or password',
      _ => e.message,
    };
  }
}
