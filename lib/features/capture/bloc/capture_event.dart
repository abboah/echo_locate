part of 'capture_bloc.dart';

sealed class CaptureEvent extends Equatable {
  const CaptureEvent();

  @override
  List<Object?> get props => [];
}

/// Begin recording a walk through [buildingId].
final class CaptureStarted extends CaptureEvent {
  const CaptureStarted({
    required this.buildingId,
    required this.floorId,
    this.stride = StrideProfile.fallback,
    this.knownLandmarks = const [],
  });

  final String buildingId;
  final String floorId;

  /// The contributor's own step length — the number that turns their count
  /// into the metres everybody else's phone will read back.
  final StrideProfile stride;

  /// Landmarks already recorded in this building, so a sign that has been
  /// captured before is proposed under the name it already has.
  final List<Landmark> knownLandmarks;

  @override
  List<Object?> get props => [buildingId, floorId, stride, knownLandmarks];
}

/// The contributor confirms they are standing at a landmark.
final class CaptureLandmarkAccepted extends CaptureEvent {
  const CaptureLandmarkAccepted({
    required this.labelText,
    required this.displayName,
    required this.kind,
    this.aliases = const [],
  });

  /// What the camera should read here, e.g. '204'.
  final String labelText;

  /// What guidance will say, e.g. 'Reading Hall door'.
  final String displayName;

  final LandmarkKind kind;
  final List<String> aliases;

  @override
  List<Object?> get props => [labelText, displayName, kind, aliases];
}

/// How the leg just walked went: the turn taken into it, and what to say.
final class CaptureLegDescribed extends CaptureEvent {
  const CaptureLegDescribed({
    required this.turnDeg,
    required this.instruction,
    this.distanceM,
  });

  /// 0 straight · ±90 left/right · ±135 sharp. Tapped, never sensed.
  final int turnDeg;

  final String instruction;

  /// Overrides the step-counted distance. The only distance there is on a
  /// phone with no counter, where the contributor paces or measures it.
  final double? distanceM;

  @override
  List<Object?> get props => [turnDeg, instruction, distanceM];
}

/// Upload the capture, ending at the room the last landmark opens onto.
final class CaptureFinished extends CaptureEvent {
  const CaptureFinished({required this.destinationRoomId});

  final String destinationRoomId;

  @override
  List<Object?> get props => [destinationRoomId];
}

/// Internal: text lines seen in one camera frame.
final class _ReadsArrived extends CaptureEvent {
  const _ReadsArrived(this.lines);

  final List<String> lines;

  @override
  List<Object?> get props => [lines];
}

/// Internal: steps counted since the last landmark.
final class _StepsTicked extends CaptureEvent {
  const _StepsTicked(this.steps);

  final int steps;

  @override
  List<Object?> get props => [steps];
}
