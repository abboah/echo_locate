part of 'sonar_bloc.dart';

/// starting → unavailable (no mic/audio engine) | idle (ready, or holding
/// the last result) → measuring (mid-ping) | calibrating → idle again.
enum SonarStatus { starting, unavailable, idle, measuring, calibrating }

final class SonarState extends Equatable {
  const SonarState({
    this.status = SonarStatus.starting,
    this.lastMeasurement,
    this.headingDegrees,
    this.error,
    this.isCalibrated = false,
  });

  final SonarStatus status;
  final ToFResult? lastMeasurement;

  /// Whether a clutter profile has been captured. Until it has, the
  /// speaker's own ringing masks anything closer than ~0.6m.
  final bool isCalibrated;

  /// Uncompensated (no tilt correction) magnetometer heading in degrees,
  /// 0–360. Null until the first reading arrives.
  final double? headingDegrees;

  final String? error;

  SonarState copyWith({
    SonarStatus? status,
    ToFResult? lastMeasurement,
    double? headingDegrees,
    String? error,
    bool? isCalibrated,
  }) {
    return SonarState(
      status: status ?? this.status,
      lastMeasurement: lastMeasurement ?? this.lastMeasurement,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      error: error ?? this.error,
      isCalibrated: isCalibrated ?? this.isCalibrated,
    );
  }

  @override
  List<Object?> get props => [
    status,
    lastMeasurement,
    headingDegrees,
    error,
    isCalibrated,
  ];
}
