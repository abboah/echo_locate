import 'dart:async';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../core/models/auth_user.dart';
import '../../data/repository_mixin.dart';

/// Auth identity + session. Mock implementation for Phase 1; a Supabase
/// implementation replaces [MockAuthRepository] behind this same interface
/// when credentials are wired up.
abstract class AuthRepository {
  /// The signed-in user, or null. Synchronously readable so the router
  /// redirect can decide guest vs user without awaiting.
  AuthUser? get currentUser;

  /// Emits on every sign-in/sign-out. Drives [AuthBloc].
  Stream<AuthUser?> get authStateChanges;

  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthUser> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
  });

  Future<AuthUser> signInWithGoogle();

  Future<AuthUser> signInWithApple();

  Future<void> signOut();
}

/// Hive-persisted mock: accepts any well-formed credentials, keeps the
/// session across restarts, and enforces the same validation rules the
/// Supabase implementation will (so the error UI is real).
class MockAuthRepository with RepositoryMixin implements AuthRepository {
  MockAuthRepository(this._box) {
    final raw = _box.get(_userKey);
    if (raw != null) {
      try {
        _user = AuthUser.fromJson(Map<String, dynamic>.from(raw as Map));
      } catch (_) {
        _user = null; // stale session format — treat as signed out
      }
    }
  }

  /// Same box name the settings used to live in, so an existing mock
  /// session survives the settings move to shared_preferences.
  static const boxName = 'settings';

  static const _userKey = 'auth_user';
  static const _latency = Duration(milliseconds: 600);

  final Box _box;
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  }) {
    return runOperation('sign_in_email', () async {
      _validateEmail(email);
      _validatePassword(password);
      await Future<void>.delayed(_latency);
      final name = email.split('@').first;
      return _setUser(
        AuthUser(
          id: 'mock-${email.hashCode}',
          fullName: name.isEmpty ? 'Mapper' : _titleCase(name),
          email: email,
        ),
      );
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
      _validateEmail(email);
      _validatePassword(password);
      await Future<void>.delayed(_latency);
      return _setUser(
        AuthUser(
          id: 'mock-${email.hashCode}',
          fullName: fullName.trim(),
          email: email,
        ),
      );
    });
  }

  @override
  Future<AuthUser> signInWithGoogle() {
    return runOperation('sign_in_google', () async {
      await Future<void>.delayed(_latency);
      return _setUser(
        const AuthUser(
          id: 'mock-google',
          fullName: 'John Doe',
          email: 'johndoe@knust.edu.gh',
        ),
      );
    });
  }

  @override
  Future<AuthUser> signInWithApple() {
    return runOperation('sign_in_apple', () async {
      await Future<void>.delayed(_latency);
      return _setUser(
        const AuthUser(
          id: 'mock-apple',
          fullName: 'John Doe',
          email: 'johndoe@knust.edu.gh',
        ),
      );
    });
  }

  @override
  Future<void> signOut() async {
    _user = null;
    await _box.delete(_userKey);
    RepositoryMixin.clearEphemeralCache();
    _controller.add(null);
  }

  Future<AuthUser> _setUser(AuthUser user) async {
    _user = user;
    await _box.put(_userKey, user.toJson());
    _controller.add(user);
    return user;
  }

  void _validateEmail(String email) {
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
    if (!ok) throw const OperationFailure('Enter a valid email address');
  }

  void _validatePassword(String password) {
    // Matches the sign-up error state in the Figma design (7:963).
    if (password.length < 8) {
      throw const OperationFailure('Use at least 8 characters');
    }
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
