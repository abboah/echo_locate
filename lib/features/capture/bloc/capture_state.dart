part of 'capture_bloc.dart';

/// preparing → sighting → walking ⇄ describing → saving → saved | failed.
enum CaptureStatus {
  /// Bringing up the camera and the step counter.
  preparing,

  /// Waiting for the opening landmark: the contributor is standing at the
  /// start pointing the camera at a directory board.
  sighting,

  /// Walking between landmarks, counting steps.
  walking,

  /// A landmark has just been sighted; the leg that led here needs its turn
  /// and its wording before the walk continues.
  describing,

  saving,
  saved,
  failed,
}

/// A line of text the camera read, offered as a landmark.
class CaptureProposal extends Equatable {
  const CaptureProposal({required this.text, this.existing});

  final String text;

  /// The landmark this read already matches, when the building has one.
  ///
  /// Accepting it under the recorded [Landmark.displayName] is what makes the
  /// upload merge with the existing landmark rather than adding a second one
  /// a metre away — the server keys them on display name.
  final Landmark? existing;

  @override
  List<Object?> get props => [text, existing];
}

final class CaptureState extends Equatable {
  const CaptureState({
    this.status = CaptureStatus.preparing,
    this.buildingId = '',
    this.floorId = '',
    this.stride = StrideProfile.fallback,
    this.proposals = const [],
    this.landmarks = const [],
    this.steps = const [],
    this.stepsThisLeg = 0,
    this.pendingLandmark,
    this.pendingSteps = 0,
    this.stepCounting = false,
    this.signReading = false,
    this.savedRouteId,
    this.error,
  });

  final CaptureStatus status;
  final String buildingId;
  final String floorId;
  final StrideProfile stride;

  /// What the camera is currently reading, newest first.
  final List<CaptureProposal> proposals;

  final List<DraftLandmark> landmarks;
  final List<DraftStep> steps;

  /// Steps since the last confirmed landmark.
  final int stepsThisLeg;

  /// Sighted but not yet joined to the route by a described leg.
  final DraftLandmark? pendingLandmark;

  /// The count frozen at the moment [pendingLandmark] was sighted, so the
  /// steps taken while typing an instruction do not lengthen the leg.
  final int pendingSteps;

  final bool stepCounting;
  final bool signReading;

  final String? savedRouteId;
  final String? error;

  /// Metres walked so far, as they will be stored.
  double get totalDistanceM =>
      steps.fold(0, (sum, step) => sum + step.distanceM);

  /// Whether the contributor has to type this leg's distance.
  ///
  /// True with no step counter, and also when a counter that is supposedly
  /// working counted nothing — a phone carried in a bag, a broken sensor, a
  /// contributor pushed in a wheelchair. Storing the zero it reported would
  /// put two landmarks at the same point and collapse the map.
  bool get needsManualDistance =>
      pendingLandmark != null && (!stepCounting || pendingSteps <= 0);

  bool get canFinish => steps.isNotEmpty;

  CaptureState copyWith({
    CaptureStatus? status,
    String? buildingId,
    String? floorId,
    StrideProfile? stride,
    List<CaptureProposal>? proposals,
    List<DraftLandmark>? landmarks,
    List<DraftStep>? steps,
    int? stepsThisLeg,
    DraftLandmark? pendingLandmark,
    int? pendingSteps,
    bool? stepCounting,
    bool? signReading,
    String? savedRouteId,
    String? error,
    bool clearPending = false,
    bool clearError = false,
  }) =>
      CaptureState(
        status: status ?? this.status,
        buildingId: buildingId ?? this.buildingId,
        floorId: floorId ?? this.floorId,
        stride: stride ?? this.stride,
        proposals: proposals ?? this.proposals,
        landmarks: landmarks ?? this.landmarks,
        steps: steps ?? this.steps,
        stepsThisLeg: stepsThisLeg ?? this.stepsThisLeg,
        pendingLandmark:
            clearPending ? null : pendingLandmark ?? this.pendingLandmark,
        pendingSteps: pendingSteps ?? this.pendingSteps,
        stepCounting: stepCounting ?? this.stepCounting,
        signReading: signReading ?? this.signReading,
        savedRouteId: savedRouteId ?? this.savedRouteId,
        error: clearError ? null : error ?? this.error,
      );

  @override
  List<Object?> get props => [
        status,
        buildingId,
        floorId,
        stride,
        proposals,
        landmarks,
        steps,
        stepsThisLeg,
        pendingLandmark,
        pendingSteps,
        stepCounting,
        signReading,
        savedRouteId,
        error,
      ];
}
