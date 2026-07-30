part of 'auth_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Signed out. Carries transient form state (submission in flight, last
/// error message) so the sign-in/up pages can render it via BlocBuilder.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.inProgress = false, this.error});

  final bool inProgress;
  final String? error;

  @override
  List<Object?> get props => [inProgress, error];
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final AuthUser user;

  @override
  List<Object?> get props => [user];
}
