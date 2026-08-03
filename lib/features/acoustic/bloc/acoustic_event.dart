part of 'acoustic_bloc.dart';

sealed class AcousticEvent extends Equatable {
  const AcousticEvent();

  @override
  List<Object?> get props => [];
}

/// Bring up the mic/speaker.
final class AcousticStarted extends AcousticEvent {
  const AcousticStarted();
}

/// Emit one chirp, listen to the room fall quiet, and name the space.
final class AcousticMeasureRequested extends AcousticEvent {
  const AcousticMeasureRequested();
}
