part of 'room_capture_cubit.dart';

enum RoomCaptureStage {
  /// Working out whether this phone can scan at all.
  checking,

  /// Live session — corners can be placed.
  capturing,

  /// This device is not ARCore-certified, or the session would not start.
  /// A normal destination, not a failure: the screen offers photo tracing.
  unavailable,

  saving,
  saved,
}

/// What a tap on the camera means right now.
///
/// Two modes rather than one clever gesture, matching the tracing flow:
/// placing a corner and placing a door are different intents on the same
/// pixel, and guessing between them silently produces the wrong one.
enum RoomCaptureMode { rooms, doors }

class RoomCaptureState extends Equatable {
  const RoomCaptureState({
    this.stage = RoomCaptureStage.checking,
    this.mode = RoomCaptureMode.rooms,
    this.availability = ArCoreAvailability.unknown,
    this.buildingId = '',
    this.floorId = '',
    this.wingId,
    this.floors = const [],
    this.plan = RoomPlan.empty,
    this.draft = const [],
    this.tracking = CaptureTracking.stopped,
    this.issue = CaptureTrackingIssue.none,
    this.planeLocked = false,
    this.preview,
    this.previewQuarterTurns = 1,
    this.hint,
    this.error,
  });

  final RoomCaptureStage stage;
  final RoomCaptureMode mode;
  final ArCoreAvailability availability;
  final String buildingId;
  final String floorId;

  /// The wing this session is capturing into, or null before it opens.
  final String? wingId;

  final List<BuildingFloor> floors;

  /// Rooms already on this floor from an earlier session.
  ///
  /// Shown so a contributor can see they are extending a floor rather than
  /// starting one — and so the count on screen is not mistaken for what they
  /// captured today.
  int get roomsFromEarlierSessions => [
    for (final room in plan.drawableRooms)
      if (room.wingId != wingId) room,
  ].length;

  /// Whether this session is adding to a floor somebody already captured.
  bool get isExtendingFloor => roomsFromEarlierSessions > 0;

  /// Whether anything has been captured into this session's wing yet.
  ///
  /// Once it has, the floor is fixed: a plan belongs to one floor, so switching
  /// would either throw the work away or file the rooms somewhere they are not.
  bool get wingHasRooms =>
      plan.drawableRooms.any((room) => room.wingId == wingId);

  /// Everything captured so far. The same [RoomPlan] the tracing flow builds,
  /// so everything downstream is shared.
  final RoomPlan plan;

  /// Corners of the room being captured, in tap order.
  ///
  /// Kept raw and in metres. Cleanup runs once, on close — snapping a
  /// three-corner polygon to a grid it has not established yet makes corners
  /// jump while the user is still placing them.
  final List<CapturedCorner> draft;

  final CaptureTracking tracking;
  final CaptureTrackingIssue issue;

  /// Whether a floor plane is locked for the room in progress.
  final bool planeLocked;

  /// Last camera frame received. Held between throttled updates.
  final Uint8List? preview;

  /// Quarter turns the preview needs to appear upright. The sensor image is
  /// landscape on essentially every phone while the phone is held portrait.
  /// Affects only how it looks — taps are mapped by ARCore, not by this.
  final int previewQuarterTurns;

  /// Transient guidance — "aim at the floor", "move more slowly".
  final String? hint;

  final String? error;

  bool get isCapturing => draft.isNotEmpty;

  bool get canCloseRoom => draft.length >= 3;

  bool get canSave => plan.drawableRooms.isNotEmpty;

  /// Whether corners can be placed right now.
  bool get canPlace =>
      stage == RoomCaptureStage.capturing && tracking.canCapture;

  /// Points captured while the plane was not being actively tracked.
  ///
  /// Surfaced rather than averaged away: a room built mostly from these is
  /// worth recapturing, and the §10 report should be able to say so.
  int get lowConfidenceCorners =>
      draft.where((corner) => corner.confidence < 1).length;

  /// Rooms with no door on them at all.
  ///
  /// The **actionable** measure, and the one the screen leads with: the fix is
  /// to walk to that room's doorway and tap, which can only be done while still
  /// in the building. Until any doors are placed this is every room — precisely
  /// the state a capture sits in, and the difference between a picture of a
  /// floor and a map of one.
  List<Room> get roomsWithoutDoors => [
    for (final room in plan.drawableRooms)
      if (plan.openingsOn(room.id).isEmpty) room,
  ];

  /// Rooms that have doors but still cannot be walked to from the rest.
  ///
  /// The subtler failure [roomsWithoutDoors] cannot see: a floor captured as
  /// two islands, each internally connected and joined to each other by
  /// nothing. Every room has a door, so nothing looks wrong, and half the
  /// building is unroutable.
  ///
  /// Measured from the first room, so it is empty when the whole floor is one
  /// connected map.
  List<Room> get strandedRooms {
    final rooms = plan.drawableRooms.toList();
    if (rooms.length < 2) return const [];
    final reachable = RoomNavGraph.build(plan).reachableRooms(rooms.first.id);
    return [
      for (final room in rooms)
        if (!reachable.contains(room.id) && plan.openingsOn(room.id).isNotEmpty)
          room,
    ];
  }

  /// Corridors whose declared door count is not yet met.
  Map<String, int> get incompleteCorridors => plan.incompleteCorridors;

  bool get ordinalsAreSafe => plan.isRoutable;

  /// Widest extent of everything captured so far, in metres.
  ///
  /// The proxy for accumulated drift: ARCore heading error compounds with
  /// distance walked, so a session that has covered a lot of building has
  /// earned less trust than one that has not. See
  /// [RoomCaptureCubit.driftWarningSpanMetres].
  double get capturedSpanMetres {
    final rooms = plan.drawableRooms.toList();
    if (rooms.isEmpty) return 0;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final room in rooms) {
      final box = room.bounds;
      if (box.left < minX) minX = box.left;
      if (box.top < minY) minY = box.top;
      if (box.right > maxX) maxX = box.right;
      if (box.bottom > maxY) maxY = box.bottom;
    }
    return (maxX - minX) > (maxY - minY) ? maxX - minX : maxY - minY;
  }

  /// What the screen tells the user to do next.
  String get guidance {
    if (hint != null) return hint!;
    if (!tracking.canCapture) return issue.advice;

    if (mode == RoomCaptureMode.doors) {
      if (plan.drawableRooms.length < 2) {
        return 'Capture at least two rooms, then stand in the doorway between them.';
      }
      return 'Stand in a doorway and tap the floor to record the door.';
    }

    if (draft.isEmpty) {
      return planeLocked
          ? 'Tap the floor at the base of each corner.'
          : 'Point at the floor and move slowly until it is detected.';
    }
    return '${draft.length} corner${draft.length == 1 ? "" : "s"} placed. '
        'Tap the next, or close the room.';
  }

  RoomCaptureState copyWith({
    RoomCaptureStage? stage,
    String? wingId,
    RoomCaptureMode? mode,
    ArCoreAvailability? availability,
    String? buildingId,
    String? floorId,
    List<BuildingFloor>? floors,
    RoomPlan? plan,
    List<CapturedCorner>? draft,
    CaptureTracking? tracking,
    CaptureTrackingIssue? issue,
    bool? planeLocked,
    Uint8List? preview,
    int? previewQuarterTurns,
    String? hint,
    String? error,
  }) => RoomCaptureState(
    stage: stage ?? this.stage,
    wingId: wingId ?? this.wingId,
    mode: mode ?? this.mode,
    availability: availability ?? this.availability,
    buildingId: buildingId ?? this.buildingId,
    floorId: floorId ?? this.floorId,
    floors: floors ?? this.floors,
    plan: plan ?? this.plan,
    draft: draft ?? this.draft,
    tracking: tracking ?? this.tracking,
    issue: issue ?? this.issue,
    planeLocked: planeLocked ?? this.planeLocked,
    preview: preview ?? this.preview,
    previewQuarterTurns: previewQuarterTurns ?? this.previewQuarterTurns,
    // Neither is sticky: a hint about a tap that missed must not outlive
    // the tap that worked, or the screen keeps correcting a mistake the
    // user already fixed.
    hint: hint,
    error: error,
  );

  /// [draft] compares by identity through Equatable, since [CapturedCorner] is
  /// a plain class — which is fine and intended: every change to it replaces
  /// the list, so a new list is exactly the signal to rebuild on.
  @override
  List<Object?> get props => [
    stage,
    wingId,
    mode,
    availability,
    buildingId,
    floorId,
    floors,
    plan,
    draft,
    tracking,
    issue,
    planeLocked,
    preview,
    previewQuarterTurns,
    hint,
    error,
  ];
}
