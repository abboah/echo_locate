// Supabase also exports an `AuthUser`; ours (the app model) wins.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/models/auth_user.dart';
import '../../data/repository_mixin.dart';
import 'auth_repository.dart';

/// Supabase-backed auth. Registered instead of [MockAuthRepository] when
/// `AppConfig.hasSupabase` is true — the Blocs/pages never know the
/// difference. Sessions persist across restarts via supabase_flutter.
///
/// Google/Apple stay "coming soon" for now: native OAuth needs per-platform
/// console setup that isn't worth the deadline budget; email covers the
/// thesis.
class SupabaseAuthRepository with RepositoryMixin implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

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

  @override
  Future<AuthUser> signInWithGoogle() async {
    throw const OperationFailure(
      'Google sign-in is coming soon — use email for now',
    );
  }

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

  String _friendly(AuthException e) => switch (e.message) {
        'Invalid login credentials' => 'Wrong email or password',
        _ => e.message,
      };
}
