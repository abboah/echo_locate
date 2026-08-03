part of 'sonar_bloc.dart';

sealed class SonarEvent extends Equatable {
  const SonarEvent();

  @override
  List<Object?> get props => [];
}

final class SonarStarted extends SonarEvent {
  const SonarStarted();
}

final class SonarMeasureRequested extends SonarEvent {
  const SonarMeasureRequested();
}

/// Capture this device's fixed acoustic signature so echoes can be told
/// apart from the speaker's own ringing. Must be run with nothing in front
/// of the phone.
final class SonarCalibrateRequested extends SonarEvent {
  const SonarCalibrateRequested();
}

/// Internal: the magnetometer stream produced a new heading.
final class _HeadingChanged extends SonarEvent {
  const _HeadingChanged(this.degrees);

  final double degrees;

  @override
  List<Object?> get props => [degrees];
}
