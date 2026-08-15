import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/auth_user.dart';
import '../../../data/repository_mixin.dart';
import '../auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// App-wide auth state. The router's redirect reads [state] synchronously
/// (via `refreshListenable`) to swap between guest and user route trees.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repository)
    : super(
        _repository.currentUser == null
            ? const AuthUnauthenticated()
            : AuthAuthenticated(_repository.currentUser!),
      ) {
    on<AuthSubscriptionRequested>(_onSubscriptionRequested);
    on<AuthSignInSubmitted>(_onSignIn);
    on<AuthSignUpSubmitted>(_onSignUp);
    on<AuthGoogleRequested>(
      (e, emit) => _social(emit, _repository.signInWithGoogle),
    );
    on<AuthAppleRequested>(
      (e, emit) => _social(emit, _repository.signInWithApple),
    );
    on<AuthSignOutRequested>(_onSignOut);
    on<_AuthUserChanged>(_onUserChanged);

    add(const AuthSubscriptionRequested());
  }

  final AuthRepository _repository;
  StreamSubscription<AuthUser?>? _subscription;

  Future<void> _onSubscriptionRequested(
    AuthSubscriptionRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = _repository.authStateChanges.listen(
      (user) => add(_AuthUserChanged(user)),
    );
  }

  Future<void> _onSignIn(
    AuthSignInSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthUnauthenticated(inProgress: true));
    try {
      await _repository.signInWithEmail(
        email: event.email,
        password: event.password,
      );
      // Success lands via _AuthUserChanged from the repository stream.
    } catch (error) {
      // Broad on purpose: an AuthException or a dropped socket used to
      // escape, leaving the sign-in button spinning with no way back.
      emit(AuthUnauthenticated(error: OperationFailure.from(error).message));
    }
  }

  Future<void> _onSignUp(
    AuthSignUpSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthUnauthenticated(inProgress: true));
    try {
      await _repository.signUpWithEmail(
        fullName: event.fullName,
        email: event.email,
        password: event.password,
      );
    } catch (error) {
      // Broad on purpose: an AuthException or a dropped socket used to
      // escape, leaving the sign-in button spinning with no way back.
      emit(AuthUnauthenticated(error: OperationFailure.from(error).message));
    }
  }

  Future<void> _social(
    Emitter<AuthState> emit,
    Future<AuthUser> Function() signIn,
  ) async {
    emit(const AuthUnauthenticated(inProgress: true));
    try {
      await signIn();
    } catch (error) {
      // Broad on purpose: an AuthException or a dropped socket used to
      // escape, leaving the sign-in button spinning with no way back.
      emit(AuthUnauthenticated(error: OperationFailure.from(error).message));
    }
  }

  Future<void> _onSignOut(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _repository.signOut();
  }

  void _onUserChanged(_AuthUserChanged event, Emitter<AuthState> emit) {
    emit(
      event.user == null
          ? const AuthUnauthenticated()
          : AuthAuthenticated(event.user!),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
