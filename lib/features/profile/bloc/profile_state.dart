part of 'profile_bloc.dart';

enum ProfileStatus { initial, loading, success, failure }

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
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, profile, error];
}
