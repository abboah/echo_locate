part of 'plan_editor_cubit.dart';

enum PlanEditorStatus { loading, ready, empty, saving, saved }

class PlanEditorState extends Equatable {
  const PlanEditorState({
    this.status = PlanEditorStatus.loading,
    this.buildingId = '',
    this.floorId = '',
    this.floors = const [],
    this.plan = RoomPlan.empty,
    this.original = RoomPlan.empty,
    this.selectedWingId,
    this.selectedRoomId,
    this.hint,
    this.error,
  });

  final PlanEditorStatus status;
  final String buildingId;
  final String floorId;

  /// The building's floors, so one above the ground can be edited.
  final List<BuildingFloor> floors;

  /// The plan as edited.
  final RoomPlan plan;

  /// The plan as loaded, so a wing can be put back where it was.
  final RoomPlan original;

  final String? selectedWingId;
  final String? selectedRoomId;
  final String? hint;
  final String? error;

  bool get hasWings => plan.wingIds.length > 1;

  bool get isDirty => plan != original;

  WingPlacement placementOf(String wingId) =>
      plan.wings[wingId] ?? const WingPlacement();

  Room? get selectedRoom =>
      selectedRoomId == null ? null : plan.roomOf(selectedRoomId!);

  /// Rooms belonging to the selected wing, placed — what the editor highlights.
  List<Room> get selectedWingRooms {
    final wingId = selectedWingId;
    if (wingId == null) return const [];
    return [
      for (final room in plan.drawableRooms)
        if (room.wingId == wingId) room,
    ];
  }

  /// Rooms drawn on the plan that cannot be walked to from the rest.
  ///
  /// The measure that says whether aligning the wings has actually finished the
  /// job: two wings can sit perfectly side by side on screen and still have no
  /// door joining them, which routes exactly as badly as if they were miles
  /// apart. Geometry is not connectivity.
  List<Room> get strandedRooms {
    final rooms = plan.drawableRooms.toList();
    if (rooms.length < 2) return const [];
    final reachable = RoomNavGraph.build(plan).reachableRooms(rooms.first.id);
    return [
      for (final room in rooms)
        if (!reachable.contains(room.id)) room,
    ];
  }

  /// Pairs of rooms sharing a long stretch of wall with no door between them.
  ///
  /// After two wings are pushed together this is where the join should be, so
  /// it doubles as "you have aligned them — now connect them".
  List<({String roomA, String roomB, Offset near})> get missingConnections {
    final rooms = {for (final room in plan.rooms) room.id: room};
    return [
      for (final pair in RoomNavGraph.build(plan).missingConnections(
        // In plan units. A traced plan is in image fractions and a captured one
        // in metres, so the threshold is scaled off the floor's own size rather
        // than hard-coded into one of the two and wrong in the other.
        minSharedWallM: _unit * 1.0,
        toleranceM: _unit * 0.4,
      ))
        if (_isMissingDoor(rooms[pair.roomA], rooms[pair.roomB])) pair,
    ];
  }

  /// Whether a shared wall with no door is actually a door somebody forgot.
  ///
  /// Only when one side is circulation. Two rooms sharing a wall is the normal
  /// case in an institutional building — a row of offices along a corridor
  /// shares a wall at every boundary and has a door onto the corridor and
  /// nowhere else. Suggesting a door at each of those boundaries proposed
  /// dozens of doorways that are not in the building, and taking the
  /// suggestion would route somebody straight through a wall.
  ///
  /// The wing-join case this was written for still fires: wings meet where one
  /// side's corridor runs up against the other's.
  static bool _isMissingDoor(Room? a, Room? b) =>
      a != null && b != null && (a.isCirculation || b.isCirculation);

  /// One "metre" in this plan's units.
  ///
  /// Captured plans really are metres. Traced plans are fractions of an image
  /// width, where the same building spans about 1.0 — so a metre is roughly a
  /// fiftieth of that. Deriving it from the plan's own extent keeps the editor's
  /// tolerances meaningful in both without either being told which it is.
  double get _unit {
    if (plan.isMetric) return 1;
    final box = plan.bounds;
    final span = box.longestSide;
    return span <= 0 ? 1 : span / 50;
  }

  /// The rotation that would square [wingId]'s longest corridor against the
  /// nearest corridor on another wing, or null when nothing is close enough.
  ///
  /// Compared modulo 90°, because two corridors meeting at right angles are as
  /// aligned as two running parallel — a wing that wants a quarter turn is
  /// still a wing somebody dragged roughly into place.
  double? snapCorrectionFor(String wingId) {
    final mine = _dominantCorridorBearing([
      for (final room in plan.drawableRooms)
        if (room.wingId == wingId) room,
    ]);
    final theirs = _dominantCorridorBearing([
      for (final room in plan.drawableRooms)
        if (room.wingId != wingId) room,
    ]);
    if (mine == null || theirs == null) return null;

    const quarter = math.pi / 2;
    var delta = (theirs - mine) % quarter;
    if (delta > quarter / 2) delta -= quarter;

    const tolerance = PlanEditorCubit.snapToleranceDeg * math.pi / 180;
    return delta.abs() <= tolerance ? delta : null;
  }

  /// Bearing of the longest circulation space among [rooms].
  ///
  /// Corridors, not rooms: a corridor's axis is the building's grid, and it is
  /// the thing two wings have to agree about. A square office has no axis worth
  /// aligning to.
  double? _dominantCorridorBearing(List<Room> rooms) {
    double? best;
    var bestLength = 0.0;
    for (final room in rooms) {
      if (!room.isCirculation) continue;
      final length = room.bounds.longestSide;
      if (length > bestLength) {
        bestLength = length;
        best = math.atan2(
          longestEdgeDirection(room.corners).dy,
          longestEdgeDirection(room.corners).dx,
        );
      }
    }
    return best;
  }

  PlanEditorState copyWith({
    PlanEditorStatus? status,
    String? buildingId,
    String? floorId,
    List<BuildingFloor>? floors,
    RoomPlan? plan,
    RoomPlan? original,
    String? selectedWingId,
    bool clearSelection = false,
    String? selectedRoomId,
    bool clearRoomSelection = false,
    String? hint,
    String? error,
  }) => PlanEditorState(
    status: status ?? this.status,
    buildingId: buildingId ?? this.buildingId,
    floorId: floorId ?? this.floorId,
    floors: floors ?? this.floors,
    plan: plan ?? this.plan,
    original: original ?? this.original,
    selectedWingId: clearSelection
        ? null
        : (selectedWingId ?? this.selectedWingId),
    selectedRoomId: clearRoomSelection
        ? null
        : (selectedRoomId ?? this.selectedRoomId),
    // Neither is sticky: a hint from one nudge must not outlive the next.
    hint: hint,
    error: error,
  );

  @override
  List<Object?> get props => [
    status,
    buildingId,
    floorId,
    floors,
    plan,
    original,
    selectedWingId,
    selectedRoomId,
    hint,
    error,
  ];
}
