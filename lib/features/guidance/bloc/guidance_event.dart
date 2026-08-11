part of 'guidance_bloc.dart';

sealed class GuidanceEvent extends Equatable {
  const GuidanceEvent();

  @override
  List<Object?> get props => [];
}

/// Begin guiding [session]. Brings up the camera, sign reading and the step
/// counter; whichever of them is unavailable simply lowers the rung of the
/// fallback ladder guidance runs on.
final class GuidanceStarted extends GuidanceEvent {
  const GuidanceStarted(this.session);

  final GuidanceSession session;

  @override
  List<Object?> get props => [session];
}

final class GuidanceVoiceToggled extends GuidanceEvent {
  const GuidanceVoiceToggled();
}

/// "I'm at the landmark" — the manual equivalent of an OCR confirmation, for
/// a phone with no working camera and for a user who knows better than the
/// phone does.
final class GuidanceLandmarkConfirmed extends GuidanceEvent {
  const GuidanceLandmarkConfirmed();
}

/// "I'm lost." Starts the recovery sweep (spec §7 B5 rung 3); raised again
/// while already recovering, it drops to asking a person (rung 4).
final class GuidanceLostReported extends GuidanceEvent {
  const GuidanceLostReported();
}

/// Internal: steps counted since the last landmark.
final class _StepsTicked extends GuidanceEvent {
  const _StepsTicked(this.steps);

  final int steps;

  @override
  List<Object?> get props => [steps];
}

/// Internal: text lines seen in one camera frame.
final class _ReadsArrived extends GuidanceEvent {
  const _ReadsArrived(this.lines);

  final List<String> lines;

  @override
  List<Object?> get props => [lines];
}

/// Internal: obstacles seen in one camera frame.
final class _ObstaclesArrived extends GuidanceEvent {
  const _ObstaclesArrived(this.obstacles);

  final List<DetectedObstacle> obstacles;

  @override
  List<Object?> get props => [obstacles];
}
