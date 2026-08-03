part of 'acoustic_bloc.dart';

/// starting → unavailable (no mic) | idle → listening (mid-capture) → idle.
enum AcousticStatus { starting, unavailable, idle, listening }

final class AcousticState extends Equatable {
  const AcousticState({
    this.status = AcousticStatus.starting,
    this.lastClassification,
    this.error,
  });

  final AcousticStatus status;

  /// The most recent verdict, kept between measurements so the screen holds a
  /// result rather than blanking. Present even when the type is
  /// [RoomType.unknown] — the reverberation figures inside it explain why.
  final RoomClassification? lastClassification;

  final String? error;

  /// The acoustics behind [lastClassification], if any were measurable.
  ReverbFeatures? get features => lastClassification?.features;

  AcousticState copyWith({
    AcousticStatus? status,
    RoomClassification? lastClassification,
    String? error,
  }) {
    return AcousticState(
      status: status ?? this.status,
      lastClassification: lastClassification ?? this.lastClassification,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, lastClassification, error];
}
