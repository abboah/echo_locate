part of 'profile_bloc.dart';

enum ProfileStatus { initial, loading, success, saving, failure }

final class ProfileState extends Equatable {
  const ProfileState({
    this.status = ProfileStatus.initial,
    this.profile,
    this.error,
  });

  final ProfileStatus status;
  final UserProfile? profile;
  final String? error;

  ProfileState copyWith({
    ProfileStatus? status,
    UserProfile? profile,
    String? error,
  }) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      // Not sticky: an error from a failed rename must not outlive the retry
      // that worked, and the screen shows it once in a snackbar.
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, profile, error];
}
