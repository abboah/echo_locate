part of 'profile_bloc.dart';

sealed class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
}

final class ProfileStarted extends ProfileEvent {
  const ProfileStarted();
}

/// The contributor renamed themselves.
final class ProfileNameChanged extends ProfileEvent {
  const ProfileNameChanged(this.fullName);

  final String fullName;

  @override
  List<Object?> get props => [fullName];
}
