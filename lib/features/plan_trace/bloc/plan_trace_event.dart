part of 'plan_trace_bloc.dart';

sealed class PlanTraceEvent extends Equatable {
  const PlanTraceEvent();

  @override
  List<Object?> get props => const [];
}

/// Opens the camera and loads whatever the building was traced with before, so
/// a second contributor extends the plan rather than starting it again.
class PlanTraceStarted extends PlanTraceEvent {
  const PlanTraceStarted(this.buildingId, {this.floorId = 'floor-g'});

  final String buildingId;
  final String floorId;

  @override
  List<Object?> get props => [buildingId, floorId];
}

class PlanFloorChanged extends PlanTraceEvent {
  const PlanFloorChanged(this.floorId);

  final String floorId;

  @override
  List<Object?> get props => [floorId];
}

class PlanPhotoTaken extends PlanTraceEvent {
  const PlanPhotoTaken();
}

/// Drops the photo and re-opens the camera. Taps already placed are kept —
/// re-shooting the plan is usually about a bad angle, not a wrong trace.
class PlanPhotoRetaken extends PlanTraceEvent {
  const PlanPhotoRetaken();
}

/// Skips the photo entirely and traces on a blank grid. The fallback when the
/// camera is unavailable, and the path device-less testing takes.
class PlanPhotoSkipped extends PlanTraceEvent {
  const PlanPhotoSkipped();
}

class PlanNodeAdded extends PlanTraceEvent {
  const PlanNodeAdded({
    required this.u,
    required this.v,
    required this.kind,
    required this.labelText,
    required this.displayName,
    this.roomId,
  });

  final double u;
  final double v;
  final LandmarkKind kind;
  final String labelText;
  final String displayName;
  final String? roomId;

  @override
  List<Object?> get props => [u, v, kind, labelText, displayName, roomId];
}

/// Selecting nothing clears the selection; selecting a second node joins or
/// unjoins it to the first.
class PlanNodeTapped extends PlanTraceEvent {
  const PlanNodeTapped(this.ref);

  final String ref;

  @override
  List<Object?> get props => [ref];
}

class PlanSelectionCleared extends PlanTraceEvent {
  const PlanSelectionCleared();
}

class PlanNodeRemoved extends PlanTraceEvent {
  const PlanNodeRemoved(this.ref);

  final String ref;

  @override
  List<Object?> get props => [ref];
}

class PlanTraceSaved extends PlanTraceEvent {
  const PlanTraceSaved();
}
