part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Subscribe to the repository's auth stream; fired once at app start.
final class AuthSubscriptionRequested extends AuthEvent {
  const AuthSubscriptionRequested();
}

final class AuthSignInSubmitted extends AuthEvent {
  const AuthSignInSubmitted({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

final class AuthSignUpSubmitted extends AuthEvent {
  const AuthSignUpSubmitted({
    required this.fullName,
    required this.email,
    required this.password,
  });

  final String fullName;
  final String email;
  final String password;

  @override
  List<Object?> get props => [fullName, email, password];
}

final class AuthGoogleRequested extends AuthEvent {
  const AuthGoogleRequested();
}

final class AuthAppleRequested extends AuthEvent {
  const AuthAppleRequested();
}

final class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// Internal: repository stream emitted a new user (or null).
final class _AuthUserChanged extends AuthEvent {
  const _AuthUserChanged(this.user);

  final AuthUser? user;

  @override
  List<Object?> get props => [user];
}
