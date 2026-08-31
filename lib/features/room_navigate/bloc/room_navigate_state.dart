part of 'room_navigate_cubit.dart';

enum RoomNavigateStatus { loading, ready, empty }

class RoomNavigateState extends Equatable {
  const RoomNavigateState({
    this.status = RoomNavigateStatus.loading,
    this.buildingId = '',
    this.floorId = '',
    this.plan,
    this.fromRoomId,
    this.toRoomId,
    this.strideCalibrated = true,
    this.error,
  });

  final RoomNavigateStatus status;
  final String buildingId;
  final String floorId;
  final RoomPlan? plan;
  final String? fromRoomId;
  final String? toRoomId;

  /// Whether the user has measured their own step.
  ///
  /// Defaults to true so the prompt is never shown on a screen that has not
  /// checked — an unanswered question is not a reason to nag.
  final bool strideCalibrated;

  final String? error;

  /// Rooms worth navigating between, named and sorted.
  ///
  /// Circulation is excluded as a *destination* — nobody navigates to a
  /// corridor — but kept as a starting point, because standing in one is
  /// exactly where somebody sets off from.
  List<Room> get destinations => [
    for (final room in _sorted)
      if (!room.isCirculation) room,
  ];

  List<Room> get origins => _sorted;

  List<Room> get _sorted {
    final rooms = plan?.drawableRooms.toList() ?? const <Room>[];
    return rooms..sort((a, b) => a.spokenName.compareTo(b.spokenName));
  }

  /// Whether to offer step measurement.
  ///
  /// Only on a floor that has a scale: without one no distance is spoken at
  /// all, so measuring a step would change nothing and the offer would be
  /// noise. This is the moment it matters and the first screen that knows.
  bool get shouldOfferStride => !strideCalibrated && (plan?.isMetric ?? false);

  /// The walk itself, for drawing.
  RoomRoute? get route {
    final current = plan;
    if (current == null || fromRoomId == null || toRoomId == null) return null;
    if (fromRoomId == toRoomId) return null;
    return RoomNavGraph.build(
      current,
    ).route(fromRoomId: fromRoomId!, toRoomId: toRoomId!);
  }

  /// What will be spoken, shown before setting off.
  ///
  /// Worth seeing on screen even though guidance says it aloud: a sighted
  /// contributor checking a floor they mapped needs to read the instructions
  /// against the building, and "the second door on your left" is exactly the
  /// sentence to check.
  List<RoomInstruction> get preview {
    final current = plan;
    final walk = route;
    if (current == null || walk == null) return const [];
    return RoomDirections.forPlan(
      current,
    ).describe(RoomNavGraph.build(current), walk);
  }

  bool get hasRoute => route != null;

  /// True when the two rooms exist and simply are not joined.
  bool get isUnreachable =>
      status == RoomNavigateStatus.ready &&
      fromRoomId != null &&
      toRoomId != null &&
      fromRoomId != toRoomId &&
      route == null;

  /// Whether spoken door counts are trustworthy on this route.
  ///
  /// False means a corridor it passes through has doors declared and not
  /// placed, so ordinals are being withheld — the route is still walkable, it
  /// just will not say which door.
  bool get ordinalsAreSafe {
    final current = plan;
    final walk = route;
    if (current == null || walk == null) return true;
    return walk.roomsPassed
        .map(current.roomOf)
        .whereType<Room>()
        .where((room) => room.isCirculation)
        .every((room) => current.corridorIsComplete(room.id));
  }

  RoomNavigateState copyWith({
    RoomNavigateStatus? status,
    String? buildingId,
    String? floorId,
    RoomPlan? plan,
    String? fromRoomId,
    String? toRoomId,
    bool? strideCalibrated,
    String? error,
  }) => RoomNavigateState(
    status: status ?? this.status,
    buildingId: buildingId ?? this.buildingId,
    floorId: floorId ?? this.floorId,
    plan: plan ?? this.plan,
    fromRoomId: fromRoomId ?? this.fromRoomId,
    toRoomId: toRoomId ?? this.toRoomId,
    strideCalibrated: strideCalibrated ?? this.strideCalibrated,
    error: error,
  );

  @override
  List<Object?> get props => [
    status,
    buildingId,
    floorId,
    plan,
    fromRoomId,
    toRoomId,
    strideCalibrated,
    error,
  ];
}
