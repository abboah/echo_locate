part of 'room_trace_bloc.dart';

/// Where the contributor is in the trace.
enum RoomTraceStage { photo, trace, saving, saved }

/// What a tap means right now.
///
/// Two modes rather than one clever gesture: tracing a corner and placing a
/// door are different intents on the same pixel, and guessing between them
/// silently produces the wrong one. The mode is on screen at all times.
enum RoomTraceMode {
  /// Tap the board's four corners to undo the angle it was photographed at.
  ///
  /// Optional, and worth doing first: it is the largest systematic error in
  /// tracing and every room placed before it would have to be redone.
  board,

  /// Tap two points a known distance apart, and say how far.
  scale,

  rooms,

  /// Tap along the middle of a hallway to draw it as a path.
  ///
  /// Separate from [rooms] because it is a different *shape* of thing to draw,
  /// not a different label on the same thing: four corners versus a line, and
  /// the line is what routing follows. See [Room.centreline].
  corridor,

  doors,

  /// One tap marks a staircase or a lift.
  ///
  /// Stairs could be traced as rooms — they are already a category — but nobody
  /// does, because a stairwell on a wall board is a small hatched box and
  /// tracing four corners of it is four times the work for a shape that does
  /// not matter. What matters is *where* they are, and that they connect to the
  /// corridor outside them, which one tap can say.
  stairs;

  /// Whether taps in this mode build up a shape in `draft`.
  bool get isDrawing =>
      this == RoomTraceMode.rooms || this == RoomTraceMode.corridor;
}

class RoomTraceState extends Equatable {
  const RoomTraceState({
    this.stage = RoomTraceStage.photo,
    this.mode = RoomTraceMode.rooms,
    this.buildingId = '',
    this.floorId = '',
    this.floors = const [],
    this.photoPath,
    this.photoAspect,
    this.cameraReady = false,
    this.plan = RoomPlan.empty,
    this.draft = const [],
    this.selectedRoomId,
    this.boardCorners = const [],
    this.rectification = Homography.identity,
    this.scalePoints = const [],
    this.warning,
    this.error,
  });

  final RoomTraceStage stage;
  final RoomTraceMode mode;
  final String buildingId;
  final String floorId;
  final List<BuildingFloor> floors;

  /// The wall board being traced against, or null when tracing on a blank grid.
  final String? photoPath;

  /// Width ÷ height of [photoPath].
  ///
  /// The tracing surface is given exactly this shape, which is what keeps the
  /// photograph and the rooms drawn over it locked together — see
  /// `PlanPhotoService.aspectOf`. Falls back to [defaultAspect] for a blank
  /// grid or a photo whose header could not be read.
  final double? photoAspect;

  /// The shape of the tracing surface when there is no photo to take it from.
  ///
  /// Landscape, because a floor plan posted on a wall is; and it only decides
  /// how much of the screen the grid covers, since the coordinates stored are
  /// fractions of the width either way.
  static const double defaultAspect = 4 / 3;

  double get surfaceAspect => photoAspect ?? defaultAspect;

  final bool cameraReady;

  /// Everything traced so far. The single source of truth — the renderer, the
  /// graph and the save all read this, so what is on screen is what is stored.
  final RoomPlan plan;

  /// Corners of the room currently being traced, in plan space, in tap order.
  ///
  /// Kept raw. `cleanupPolygon` runs once, on close, rather than on every tap:
  /// snapping a three-corner polygon to a grid it has not established yet makes
  /// corners jump under the contributor's finger while they are still placing
  /// them.
  final List<Offset> draft;

  final String? selectedRoomId;

  /// Board corners tapped so far, in photo coordinates.
  final List<Offset> boardCorners;

  /// The perspective correction, or the identity when the board has not been
  /// squared up.
  ///
  /// Applied to every tap after it is set — see the header of
  /// `board_rectification.dart` for what it removes and what it leaves behind.
  final Homography rectification;

  /// The two ends of a span whose real length the contributor is about to give.
  final List<Offset> scalePoints;

  /// Something worth saying but not an error — a self-intersecting trace, a
  /// door that matched nothing.
  final String? warning;

  final String? error;

  bool get isTracing => draft.isNotEmpty;

  /// Three corners is the least that encloses anything.
  bool get canCloseRoom => draft.length >= 3;

  /// Two taps is the least that makes a line to walk down.
  bool get canCloseCorridor => draft.length >= 2;

  /// Staircases and lifts marked on this floor, in the order they were placed.
  ///
  /// What "know where all the stairs are" resolves to: one list, so the screen
  /// can say how many there are and the evaluation harness can check them
  /// against the board.
  List<Room> get verticalLinks => [
    for (final room in plan.drawableRooms)
      if (room.category == RoomCategory.staircase ||
          room.category == RoomCategory.elevator)
        room,
  ];

  bool get canSave => plan.drawableRooms.isNotEmpty;

  /// Corridors whose declared door count does not match what has been placed.
  ///
  /// Saving is allowed anyway — a half-traced floor is still worth keeping, and
  /// refusing to save loses a contributor's afternoon. What it costs is spoken
  /// ordinals: `RoomDirections` checks the same thing and stays quiet about
  /// "the second door on your left" until it adds up.
  Map<String, int> get incompleteCorridors => plan.incompleteCorridors;

  bool get ordinalsAreSafe => plan.isRoutable;

  /// Whether the photo's angle has been corrected.
  bool get isRectified => !rectification.isIdentity;

  /// Whether the plan has a real-world scale, and so whether anything may
  /// speak a distance from it.
  bool get hasScale => plan.isMetric;

  /// How far off square the photograph was, once the board has been outlined.
  double get boardSkewDegrees =>
      boardCorners.length == 4 ? Homography.skewDegreesOf(boardCorners) : 0;

  /// Rooms that have no door at all — traced, drawn, and unreachable.
  List<Room> get roomsWithoutDoors => [
    for (final room in plan.drawableRooms)
      if (plan.openingsOn(room.id).isEmpty) room,
  ];

  RoomTraceState copyWith({
    RoomTraceStage? stage,
    RoomTraceMode? mode,
    String? buildingId,
    String? floorId,
    List<BuildingFloor>? floors,
    String? photoPath,
    double? photoAspect,
    bool? cameraReady,
    RoomPlan? plan,
    List<Offset>? draft,
    String? selectedRoomId,
    bool clearSelection = false,
    List<Offset>? boardCorners,
    Homography? rectification,
    List<Offset>? scalePoints,
    String? warning,
    String? error,
  }) => RoomTraceState(
    stage: stage ?? this.stage,
    mode: mode ?? this.mode,
    buildingId: buildingId ?? this.buildingId,
    floorId: floorId ?? this.floorId,
    floors: floors ?? this.floors,
    photoPath: photoPath ?? this.photoPath,
    photoAspect: photoAspect ?? this.photoAspect,
    cameraReady: cameraReady ?? this.cameraReady,
    plan: plan ?? this.plan,
    draft: draft ?? this.draft,
    selectedRoomId: clearSelection
        ? null
        : (selectedRoomId ?? this.selectedRoomId),
    boardCorners: boardCorners ?? this.boardCorners,
    rectification: rectification ?? this.rectification,
    scalePoints: scalePoints ?? this.scalePoints,
    // Neither is sticky: a warning from one tap must not outlive the next,
    // or the screen accuses the contributor of a mistake they already fixed.
    warning: warning,
    error: error,
  );

  @override
  List<Object?> get props => [
    stage,
    mode,
    buildingId,
    floorId,
    floors,
    photoPath,
    photoAspect,
    cameraReady,
    plan,
    draft,
    selectedRoomId,
    boardCorners,
    rectification,
    scalePoints,
    warning,
    error,
  ];
}
