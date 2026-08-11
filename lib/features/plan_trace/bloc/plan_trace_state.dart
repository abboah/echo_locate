part of 'plan_trace_bloc.dart';

/// Where the contributor is in the trace.
///
/// Two steps, not three: photograph the plan, then tap landmarks onto it.
///
/// There is deliberately **no scale step**. Asking a contributor how many
/// metres lie between two points on a plan is the same unanswerable question as
/// asking a user to tap when they have walked ten metres — they do not know,
/// and no amount of rewording fixes that. Nothing needs the answer: A* compares
/// edge lengths with each other, so a map in arbitrary units routes identically
/// to one in metres, and guidance names landmarks rather than distances.
enum PlanTraceStage { photo, trace, saving, saved }

/// A landmark placed on the photographed plan, before the plan has a scale.
///
/// Held in *plan units* rather than metres or pixels: [u] and [v] are both
/// fractions of the displayed plan's **width**, so the pair keeps the image's
/// aspect ratio and survives the widget being laid out at any size. One scalar
/// then converts both axes to metres, which is what makes the scale a single
/// number the contributor can supply by tapping two points.
class PlanPoint extends Equatable {
  const PlanPoint({
    required this.ref,
    required this.u,
    required this.v,
    required this.kind,
    required this.labelText,
    required this.displayName,
    this.roomId,
  });

  final String ref;
  final double u;
  final double v;
  final LandmarkKind kind;
  final String labelText;
  final String displayName;
  final String? roomId;

  double distanceTo(PlanPoint other) {
    final du = u - other.u;
    final dv = v - other.v;
    return math.sqrt(du * du + dv * dv);
  }

  @override
  List<Object?> get props => [ref, u, v, kind, labelText, displayName, roomId];
}

/// A join between two placed points, in plan units.
class PlanLink extends Equatable {
  const PlanLink(this.fromRef, this.toRef);

  final String fromRef;
  final String toRef;

  bool connects(String a, String b) =>
      (fromRef == a && toRef == b) || (fromRef == b && toRef == a);

  @override
  List<Object?> get props => [fromRef, toRef];
}

class PlanTraceState extends Equatable {
  const PlanTraceState({
    this.stage = PlanTraceStage.photo,
    this.buildingId = '',
    this.floorId = 'floor-g',
    this.photoPath,
    this.cameraReady = false,
    this.floors = const [],
    this.points = const [],
    this.links = const [],
    this.selectedRef,
    this.error,
  });

  final PlanTraceStage stage;
  final String buildingId;

  /// Which floor the points being placed belong to. Changing it mid-trace is
  /// how one plan spans a building: place the ground-floor stairwell, switch
  /// floor, place the landing, and join them.
  final String floorId;

  /// Null when tracing on a blank grid — no camera, or the photo was skipped.
  final String? photoPath;
  final bool cameraReady;

  /// The building's real floors, so [floorId] is a database id rather than
  /// something the screen made up.
  final List<BuildingFloor> floors;

  final List<PlanPoint> points;
  final List<PlanLink> links;

  /// The point waiting to be joined to the next one tapped.
  final String? selectedRef;

  final String? error;

  /// A single landmark is a map: somewhere the camera can confirm you are.
  bool get canSave => points.isNotEmpty;

  PlanPoint? pointOf(String? ref) {
    if (ref == null) return null;
    for (final point in points) {
      if (point.ref == ref) return point;
    }
    return null;
  }

  bool linked(String a, String b) => links.any((l) => l.connects(a, b));

  PlanTraceState copyWith({
    PlanTraceStage? stage,
    String? buildingId,
    String? floorId,
    String? photoPath,
    bool clearPhoto = false,
    bool? cameraReady,
    List<BuildingFloor>? floors,
    List<PlanPoint>? points,
    List<PlanLink>? links,
    String? selectedRef,
    bool clearSelection = false,
    String? error,
  }) =>
      PlanTraceState(
        stage: stage ?? this.stage,
        buildingId: buildingId ?? this.buildingId,
        floorId: floorId ?? this.floorId,
        photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
        cameraReady: cameraReady ?? this.cameraReady,
        floors: floors ?? this.floors,
        points: points ?? this.points,
        links: links ?? this.links,
        selectedRef: clearSelection ? null : (selectedRef ?? this.selectedRef),
        // Never sticky: a message from a refused save must not outlive the
        // save that worked.
        error: error,
      );

  @override
  List<Object?> get props => [
        stage,
        buildingId,
        floorId,
        photoPath,
        cameraReady,
        floors,
        points,
        links,
        selectedRef,
        error,
      ];
}
