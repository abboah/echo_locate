import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../services/mapping/room_geometry.dart';

part 'room_plan.freezed.dart';
part 'room_plan.g.dart';

/// What a room is for. Drives the fill colour, the glyph, and the legend the
/// renderer generates for itself.
///
/// Deliberately the vocabulary of a university wall board rather than a
/// building-code classification: a contributor tagging rooms has to pick one of
/// these while standing in a corridor, so the list is short and every entry is
/// something you can tell from the doorway.
enum RoomCategory {
  lectureHall,
  office,
  laboratory,
  auditorium,
  controlRoom,
  commonRoom,
  library,
  boardroom,
  washroom,
  staircase,
  elevator,
  corridor,
  balcony,
  other;

  static RoomCategory fromName(String? value) => RoomCategory.values.firstWhere(
    (c) => c.name == value,
    orElse: () => RoomCategory.other,
  );

  /// What a person calls this category — the legend's wording, and what an
  /// unnamed room is referred to as.
  ///
  /// On the model rather than in the palette because it is not a drawing
  /// concern: with room codes gone, this is the fallback *name* of a room
  /// nobody has labelled, which the renderer, the room list and guidance all
  /// need to say the same way.
  String get title => switch (this) {
    RoomCategory.lectureHall => 'Lecture hall',
    RoomCategory.office => 'Office',
    RoomCategory.laboratory => 'Laboratory',
    RoomCategory.auditorium => 'Auditorium',
    RoomCategory.controlRoom => 'Control room',
    RoomCategory.commonRoom => 'Common room',
    RoomCategory.library => 'Library',
    RoomCategory.boardroom => 'Boardroom',
    RoomCategory.washroom => 'Washroom',
    RoomCategory.staircase => 'Staircase',
    RoomCategory.elevator => 'Lift',
    RoomCategory.corridor => 'Corridor',
    RoomCategory.balcony => 'Balcony',
    RoomCategory.other => 'Other',
  };

  /// Circulation space — walked through rather than walked to.
  ///
  /// Routing treats these as the spine a walker follows and counts doors along
  /// them; the renderer leaves them unfilled so the plan reads as rooms with
  /// space between, not a solid block of colour.
  bool get isCirculation =>
      this == RoomCategory.corridor ||
      this == RoomCategory.staircase ||
      this == RoomCategory.elevator;

  /// How a spoken instruction names this kind of place when it has no label.
  String get spokenNoun => switch (this) {
    RoomCategory.lectureHall => 'lecture hall',
    RoomCategory.office => 'office',
    RoomCategory.laboratory => 'laboratory',
    RoomCategory.auditorium => 'auditorium',
    RoomCategory.controlRoom => 'control room',
    RoomCategory.commonRoom => 'common room',
    RoomCategory.library => 'library',
    RoomCategory.boardroom => 'boardroom',
    RoomCategory.washroom => 'washroom',
    RoomCategory.staircase => 'staircase',
    RoomCategory.elevator => 'lift',
    RoomCategory.corridor => 'corridor',
    RoomCategory.balcony => 'balcony',
    RoomCategory.other => 'room',
  };
}

/// One corner of a room polygon.
///
/// A model rather than a raw `Offset` because `Offset` has no JSON form and a
/// plan has to round-trip through Postgres unchanged — `room_directions_test`
/// pins that.
///
/// Named `RoomCorner`, not `PlanPoint`, because `plan_trace_bloc.dart` already
/// owns that name for something different: a *landmark* placed on a
/// photographed plan, held as (u, v) fractions of the image width. The two
/// coexist in the tracing screen, so they cannot share a name.
///
/// Frame: **+x east, +y north**, same as [MapNode]. Units are metres for a
/// captured plan and arbitrary for a traced one — see [RoomPlan.metresPerUnit].
/// See the header of `room_geometry.dart` for what breaks if the frame drifts.
@freezed
abstract class RoomCorner with _$RoomCorner {
  const factory RoomCorner({required double x, required double y}) =
      _RoomCorner;

  const RoomCorner._();

  factory RoomCorner.fromJson(Map<String, dynamic> json) =>
      _$RoomCornerFromJson(json);

  factory RoomCorner.of(Offset offset) =>
      RoomCorner(x: offset.dx, y: offset.dy);

  Offset get offset => Offset(x, y);
}

/// Where one wing sits on the floor: a rotation about the origin, then a shift.
///
/// ## Why this exists at all
///
/// A large building cannot be captured in one AR session. ARCore's heading
/// error compounds with distance walked, and heading error is the kind that
/// ruins a plan rather than blurring it — spec §8 is explicit that a 20-room
/// floor spanning 80–100 m is exactly where it becomes visible. So a floor is
/// captured a **wing** at a time: one corridor and the rooms off it, short
/// enough that the drift inside it stays small.
///
/// Each session then starts with ARCore's origin wherever the phone was, so
/// wing two's coordinates say nothing about where it is relative to wing one.
/// This is what reconciles them, and a person sets it by dragging — spec §8
/// substitutes human-in-the-loop alignment for pose-graph optimisation, on the
/// grounds that the second is weeks of work and the first is a contributor who
/// can see the building.
@freezed
abstract class WingPlacement with _$WingPlacement {
  const factory WingPlacement({
    @Default(0) double dx,
    @Default(0) double dy,

    /// Radians, counter-clockwise, applied **before** the shift.
    @Default(0) double rotation,
  }) = _WingPlacement;

  const WingPlacement._();

  factory WingPlacement.fromJson(Map<String, dynamic> json) =>
      _$WingPlacementFromJson(json);

  /// Whether this wing has been left exactly where it was captured.
  bool get isIdentity => dx == 0 && dy == 0 && rotation == 0;

  Offset apply(Offset point) {
    if (rotation == 0) return Offset(point.dx + dx, point.dy + dy);
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    return Offset(
      point.dx * cos - point.dy * sin + dx,
      point.dx * sin + point.dy * cos + dy,
    );
  }

  /// [apply] undone: a point read off the drawing, back in the wing's own
  /// frame.
  ///
  /// What every edit to placed geometry has to go through before it is stored.
  /// The corners on screen are `apply`'d, so writing a dragged one straight back
  /// into [RoomPlan.storedRooms] saves a position that has the placement baked
  /// into it — and [RoomPlan.rooms] then applies the same placement again, so
  /// the whole wing jumps by its own offset the next time it is drawn.
  Offset unapply(Offset point) {
    final x = point.dx - dx;
    final y = point.dy - dy;
    if (rotation == 0) return Offset(x, y);
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    return Offset(x * cos + y * sin, -x * sin + y * cos);
  }

  /// The same inverse for a *difference* between two placed points.
  ///
  /// Separate from [unapply] because a delta carries no position, so the shift
  /// must not be subtracted from it — only the rotation undone. Passing a drag
  /// delta through [unapply] would move the room by the wing's offset on every
  /// frame of the drag.
  Offset unrotate(Offset delta) {
    if (rotation == 0) return delta;
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    return Offset(
      delta.dx * cos + delta.dy * sin,
      -delta.dx * sin + delta.dy * cos,
    );
  }

  WingPlacement movedBy(Offset delta) =>
      copyWith(dx: dx + delta.dx, dy: dy + delta.dy);

  WingPlacement rotatedBy(double radians) =>
      copyWith(rotation: rotation + radians);
}

/// A room as an area: the polygon, what it is for, and what it is called.
///
/// The landmark map models a room as a single point — the door you read the
/// sign on. That is enough to route *to* it and is what guidance speaks. It is
/// not enough to draw it, to say which side of a corridor it is on, or to
/// notice that two rooms share a wall with no door between them. This is the
/// area the point stands for.
@freezed
abstract class Room with _$Room {
  const factory Room({
    required String id,
    required String floorId,

    /// Auto-allocated, e.g. `'GF 14'`. Never typed by a contributor — see
    /// [RoomPlan.allocateCode].
    required String code,
    required RoomCategory category,

    /// Corners in metres, counter-clockwise. Always run through
    /// `cleanupPolygon` before construction; nothing downstream re-normalises.
    @Default(<RoomCorner>[]) List<RoomCorner> polygon,

    /// What the sign on the door says, when anybody has tagged it.
    String? label,

    /// The landmark this room's door corresponds to, joining the area map to
    /// the landmark map that guidance already runs on.
    String? landmarkId,

    /// Which capture session this room came from — see [WingPlacement].
    ///
    /// Null for a plan captured or traced in one go, which is the common case
    /// and needs no alignment.
    String? wingId,

    /// The line down the middle of a corridor, when it was drawn as a path.
    ///
    /// Empty for every ordinary room, and for a corridor traced as a bare
    /// polygon — which is why every plan saved before this existed still loads.
    ///
    /// A corridor is the one room whose *shape* is not what matters about it.
    /// What a walker needs is the line they follow, its direction at each point,
    /// and the real distance along it. A polygon supplies none of those: the
    /// direction has to be guessed from the longest wall, which is wrong the
    /// moment the corridor bends, and the distance between two doors is measured
    /// straight through the wall between them.
    ///
    /// So a corridor may instead be drawn as a path, and its [polygon] generated
    /// around it by [ribbonAround]. Both are stored: the polygon is what gets
    /// drawn and what door inference snaps to, the centreline is what routing
    /// and door counting run on.
    @Default(<RoomCorner>[]) List<RoomCorner> centreline,
  }) = _Room;

  const Room._();

  factory Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);

  /// A room known to exist but never traced.
  ///
  /// Created for a door counted on a corridor wall that nobody went through —
  /// floorplan spec §6.3. It must be **in the graph**, because "the second door
  /// on your left" is only correct if every door on that wall is counted, and
  /// it must be **absent from the render**, because there is no polygon to
  /// draw. [isStub] is what tells the two apart, and every consumer of geometry
  /// checks it: a stub's centroid is meaningless, not merely imprecise.
  factory Room.stub({
    required String id,
    required String floorId,
    required String code,
  }) =>
      Room(id: id, floorId: floorId, code: code, category: RoomCategory.other);

  /// True when this room has no traced area — see [Room.stub].
  bool get isStub => polygon.length < 3;

  /// The name a person entered when they closed this room, if they did.
  ///
  /// Empty labels are treated as absent so a stray space cannot become a
  /// room's name, and so [isNamed] means what it says everywhere.
  String? get name {
    final trimmed = label?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Whether anybody has told us what this room actually is.
  ///
  /// The test for whether a room can be a destination: guidance can send
  /// somebody to "Room 4" or "Dean's office", but "Office" names a category
  /// and a floor may hold twenty of them.
  bool get isNamed => name != null;

  /// What to show for this room. Never a code.
  ///
  /// Rooms used to be allocated sequential codes — `GF 1`, `GF 2` — in trace
  /// order, and those numbers went on the drawing and into guidance's mouth
  /// via the landmark bridge. They looked like the numbers on the doors and
  /// were nothing of the kind: a room's position in one contributor's tracing
  /// order. Somebody sent to "GF 7" would have been sent to a number that
  /// exists nowhere in the building.
  ///
  /// So the fallback is the category, which is at least true. It is not a
  /// name, which is why [isNamed] exists to keep it out of navigation.
  String get displayName => name ?? category.title;

  List<Offset> get corners => [for (final p in polygon) p.offset];

  /// The centreline as plain points — see [centreline].
  List<Offset> get spine => [for (final p in centreline) p.offset];

  /// Whether this room was drawn as a path rather than as an outline.
  bool get hasSpine => centreline.length >= 2;

  /// Where to put the label and where routing treats the room as being.
  ///
  /// [interiorPoint], not the raw area centroid: an L-shaped room's centroid
  /// sits in the missing corner, outside the room, and would put the label in
  /// the corridor and the route's waypoint through a wall.
  ///
  /// A corridor drawn as a path answers from the middle of the path instead.
  /// For an L that is a point on the walk; [interiorPoint] would pick a point
  /// on the widest scanline, which for a mitred ribbon is near a bend.
  Offset get centre => hasSpine
      ? pointAlongPolyline(spine, polylineLength(spine) / 2)
      : interiorPoint(corners);

  Rect get bounds => boundsOf(corners);

  double get areaSqM => areaOf(corners);

  /// Long-to-short extent ratio — how corridor-shaped this room is.
  double get elongation {
    final box = bounds;
    final short = box.shortestSide;
    if (short < 1e-6) return double.infinity;
    return box.longestSide / short;
  }

  bool get isCirculation => category.isCirculation;

  /// What guidance calls this room out loud.
  ///
  /// The code is gone from here deliberately. This used to say
  /// "`${category.spokenNoun} $code`" — "office GF 7" — which sounded like the
  /// sign on the door and was a tracing-order number that matched nothing in
  /// the building. Now an unnamed room is spoken as what it is, "an office",
  /// which is honest and is why [isNamed] gates it out of being a destination.
  String get spokenName => name ?? category.spokenNoun;
}

/// A door or archway joining two rooms — or a room and the outdoors.
@freezed
abstract class Opening with _$Opening {
  const factory Opening({
    required String id,
    required String roomAId,

    /// Null for an exterior door. Routing skips these; the renderer draws them,
    /// because "this is the way out" is worth seeing.
    String? roomBId,

    /// Midpoint of the opening in the wall, in metres.
    required RoomCorner at,
    @Default(0.9) double widthM,

    /// False for an open archway. Changes the phrasing — "through the archway"
    /// rather than "through the door" — and nothing else.
    @Default(true) bool isDoor,
  }) = _Opening;

  const Opening._();

  factory Opening.fromJson(Map<String, dynamic> json) =>
      _$OpeningFromJson(json);

  Offset get position => at.offset;

  bool get isExterior => roomBId == null;

  bool touches(String roomId) => roomAId == roomId || roomBId == roomId;

  /// The room on the other side of this opening from [roomId], or null when
  /// it leads outside.
  String? otherSideOf(String roomId) => roomAId == roomId ? roomBId : roomAId;

  String get spokenNoun => isDoor ? 'door' : 'archway';
}

/// One floor, as rooms and the openings between them.
///
/// The area counterpart to `FloorGraph`, which holds the same floor as
/// landmarks and corridors. Both are kept: the landmark graph is what guidance
/// runs on and needs no ARCore, and this is what gets drawn and what makes
/// door-counting possible. `room_graph.dart` is where they meet.
@freezed
abstract class RoomPlan with _$RoomPlan {
  const factory RoomPlan({
    required String buildingId,
    required String floorId,

    /// Prefix for auto-allocated room codes, e.g. `'GF'`.
    required String codePrefix,

    /// Rooms **as captured**, before their wing's placement is applied.
    ///
    /// Read [rooms] instead unless you are editing a wing's alignment. The
    /// JSON key is still `rooms`, so plans saved before wings existed load
    /// unchanged.
    @JsonKey(name: 'rooms') @Default(<Room>[]) List<Room> storedRooms,
    @JsonKey(name: 'openings')
    @Default(<Opening>[])
    List<Opening> storedOpenings,

    /// Wing id → where that wing sits on the floor.
    ///
    /// A wing is one capture session: one corridor and the rooms off it. Each
    /// AR session starts with ARCore's origin wherever the phone happened to
    /// be, so a second session's coordinates mean nothing relative to the
    /// first — the placement here is what reconciles them.
    ///
    /// Empty for a plan captured or traced in one go, which is why every
    /// existing plan and every test carries on working: no wings means no
    /// transform, and [rooms] returns exactly what was stored.
    @Default(<String, WingPlacement>{}) Map<String, WingPlacement> wings,

    /// Corridor id → how many doors the contributor counted on its walls.
    ///
    /// The one number a mapper is asked to type, and the guard on the most
    /// dangerous failure in the system — see [corridorIsComplete].
    @Default(<String, int>{}) Map<String, int> declaredDoorCounts,

    /// How many metres one plan unit is, when anything knows.
    ///
    /// Null for a plan traced off a photographed wall board, which is the
    /// common case and costs nothing: A* compares edge lengths against each
    /// other, so scaling every room by the same unknown constant picks exactly
    /// the same route. Set for a plan captured in AR, where the coordinates
    /// really are metres.
    ///
    /// What it *does* change is speech. `RoomDirections` refuses to say "walk
    /// twelve metres" from a plan whose units nobody has measured — a
    /// confidently wrong number is worse in a blind user's ear than no number.
    /// Same reasoning, and the same field, as [TracedPlan.metresPerUnit].
    double? metresPerUnit,
  }) = _RoomPlan;

  const RoomPlan._();

  factory RoomPlan.fromJson(Map<String, dynamic> json) =>
      _$RoomPlanFromJson(json);

  static const RoomPlan empty = RoomPlan(
    buildingId: '',
    floorId: '',
    codePrefix: '',
  );

  /// Whether any wing has actually been moved.
  ///
  /// The fast path everything else leans on: a single-session plan answers
  /// false and [rooms] hands back the stored list untouched, so wings cost
  /// nothing until somebody uses them.
  bool get hasWingPlacements =>
      wings.values.any((placement) => !placement.isIdentity);

  /// Rooms with their wing's placement applied — what to draw, route and
  /// measure.
  ///
  /// Everything downstream reads this rather than [storedRooms], which is what
  /// keeps the graph, the renderer and the directions layer unaware that wings
  /// exist at all.
  List<Room> get rooms {
    if (!hasWingPlacements) return storedRooms;
    return [for (final room in storedRooms) _place(room)];
  }

  /// Openings with their wing's placement applied.
  ///
  /// A door takes the placement of the room it is recorded against, so a door
  /// between two wings moves with the first of them. That is a real limitation
  /// of aligning by hand rather than solving: joining two wings leaves the
  /// shared door correct for one side and approximate for the other, and the
  /// error is exactly the misalignment the contributor left behind.
  List<Opening> get openings {
    if (!hasWingPlacements) return storedOpenings;
    // Indexed once. Looking each room up by scanning the list made this
    // quadratic in the number of rooms, on a getter the renderer calls every
    // frame.
    final wingOf = {for (final room in storedRooms) room.id: room.wingId};
    return [
      for (final opening in storedOpenings)
        opening.copyWith(
          at: RoomCorner.of(
            (wings[wingOf[opening.roomAId]] ?? const WingPlacement()).apply(
              opening.position,
            ),
          ),
        ),
    ];
  }

  Room _place(Room room) {
    final placement = wings[room.wingId];
    if (placement == null || placement.isIdentity) return room;
    return room.copyWith(
      polygon: [
        for (final corner in room.polygon)
          RoomCorner.of(placement.apply(corner.offset)),
      ],
      // Moved with the polygon it generated, or a realigned wing's corridors
      // would route down lines still sitting where they were captured.
      centreline: [
        for (final corner in room.centreline)
          RoomCorner.of(placement.apply(corner.offset)),
      ],
    );
  }

  /// Rooms belonging to one wing, unplaced — what the editor drags.
  List<Room> roomsInWing(String wingId) => [
    for (final room in storedRooms)
      if (room.wingId == wingId) room,
  ];

  /// Wing ids present, in the order their first room was captured.
  List<String> get wingIds {
    final seen = <String>[];
    for (final room in storedRooms) {
      final id = room.wingId;
      if (id != null && !seen.contains(id)) seen.add(id);
    }
    return seen;
  }

  /// Moves one wing, leaving every other alone.
  RoomPlan placeWing(String wingId, WingPlacement placement) =>
      copyWith(wings: {...wings, wingId: placement});

  /// A room as it is *stored* — the frame edits are written back into.
  ///
  /// [roomOf] hands back the placed room, which is right for drawing and
  /// routing and wrong for editing: an edit has to change the numbers that are
  /// saved, not the numbers that were drawn.
  Room? storedRoomOf(String id) {
    for (final room in storedRooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  /// Where [roomId]'s wing has been put, or the identity for a room in no wing.
  WingPlacement placementOfRoom(String roomId) =>
      wings[storedRoomOf(roomId)?.wingId] ?? const WingPlacement();

  /// Placements dropped for wings that no longer have any rooms.
  ///
  /// A wing is a set of rooms captured in one frame, so an entry naming one
  /// that nothing belongs to places nothing — but it is not inert. `wingIds` is
  /// derived from the rooms, so an empty floor of wings makes
  /// `RoomTraceBloc._lastWingIn` fall back to `wing-1`, and if `wing-1` is the
  /// stale entry then everything traced next is silently minted into a wing
  /// parked half a floor away. That is the same stranding twice over: once for
  /// the work that was parked, and again for the work that replaces it after
  /// somebody deletes the first lot and tries again.
  RoomPlan get withoutEmptyWings {
    final live = wingIds.toSet();
    if (wings.keys.every(live.contains)) return this;
    return copyWith(wings: {
      for (final entry in wings.entries)
        if (live.contains(entry.key)) entry.key: entry.value,
    });
  }

  /// Every wing flattened into the floor's own frame.
  ///
  /// Placement stops being a separate layer and becomes the geometry: what was
  /// drawn is now what is stored, and [wings] is emptied so nothing applies it a
  /// second time. For operations that legitimately work across wings at once —
  /// squaring the whole floor onto one grid — where keeping the placements would
  /// mean writing placed coordinates under a transform that still fires.
  RoomPlan get baked => copyWith(
    storedRooms: rooms,
    storedOpenings: openings,
    wings: const {},
  );

  /// Extent of everything already placed — where a new wing has to go around.
  Rect get bounds {
    final drawable = drawableRooms.toList();
    if (drawable.isEmpty) return Rect.zero;
    var box = drawable.first.bounds;
    for (final room in drawable.skip(1)) {
      box = box.expandToInclude(room.bounds);
    }
    return box;
  }

  /// Highest number used at the end of any room or opening id.
  ///
  /// Ids are minted as `room-4`, `door-11`. A session continuing a saved plan
  /// has to carry on past what is already there — restarting at 1 hands out ids
  /// that already exist, and two rooms sharing an id silently merge into one
  /// when the graph indexes them.
  int get highestIdSuffix {
    var highest = 0;
    for (final id in [
      ...storedRooms.map((r) => r.id),
      ...storedOpenings.map((o) => o.id),
    ]) {
      final n = int.tryParse(id.split('-').last);
      if (n != null && n > highest) highest = n;
    }
    return highest;
  }

  bool get isEmpty => storedRooms.isEmpty;

  /// Whether this plan's coordinates really are metres, and so whether anything
  /// may speak a distance from it aloud. See [metresPerUnit].
  bool get isMetric => metresPerUnit != null;

  /// Estimates how many metres one plan unit represents based on standard
  /// architectural dimensions (standard office/classroom is ~6.0m on its longest side).
  double get estimatedMetresPerUnit {
    if (metresPerUnit != null && metresPerUnit! > 0) return metresPerUnit!;

    final drawable = drawableRooms.where((r) => !r.isCirculation && r.corners.length >= 3).toList();
    if (drawable.isNotEmpty) {
      final roomSpans = drawable.map((r) => r.bounds.longestSide).where((s) => s > 0).toList();
      if (roomSpans.isNotEmpty) {
        roomSpans.sort();
        final medianSpan = roomSpans[roomSpans.length ~/ 2];
        if (medianSpan > 0) {
          return 6.0 / medianSpan;
        }
      }
    }

    final totalBox = bounds;
    final totalSpan = totalBox.longestSide;
    if (totalSpan > 0) {
      return 40.0 / totalSpan;
    }

    return 1.0;
  }

  /// Returns the measured scale if present, or the architecturally estimated scale.
  double get effectiveMetresPerUnit => metresPerUnit ?? estimatedMetresPerUnit;

  Room? roomOf(String id) {
    for (final room in rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  Iterable<Room> get drawableRooms => rooms.where((r) => !r.isStub);

  Iterable<Opening> openingsOn(String roomId) =>
      openings.where((o) => o.touches(roomId));

  /// The next free room code, e.g. `'GF 15'`.
  ///
  /// Derived from what is already allocated rather than held as a counter, so
  /// it survives the plan being reloaded from Postgres — a counter in memory
  /// would restart at 1 and hand out codes that already exist.
  String allocateCode() {
    var highest = 0;
    final pattern = RegExp('^${RegExp.escape(codePrefix)}\\s*(\\d+)\$');
    for (final room in rooms) {
      final match = pattern.firstMatch(room.code);
      final n = match == null ? null : int.tryParse(match.group(1)!);
      if (n != null && n > highest) highest = n;
    }
    return '$codePrefix ${highest + 1}';
  }

  /// Whether every door on [corridorId]'s walls has been tagged.
  ///
  /// **This is the guard on the worst bug the system can have.** "Your
  /// destination is the second door on your left" is only true if the map knows
  /// about every door on that wall, including doors to rooms nobody traced.
  /// Map five rooms off a hallway that has eight doors and the app sends a
  /// blind user confidently to the wrong one, with no error state and no
  /// hesitation in its voice.
  ///
  /// So the mapper counts doors by eye and types the number, and the capture
  /// flow refuses to mark the corridor done until the tagged openings match.
  /// Returns false when no count was declared: not knowing is not the same as
  /// being complete.
  bool corridorIsComplete(String corridorId) {
    final declared = declaredDoorCounts[corridorId];
    if (declared == null) return false;
    return openingsOn(corridorId).length == declared;
  }

  /// Corridors whose door count does not add up, with the shortfall.
  ///
  /// Drives the capture flow's blocking prompt, and is worth surfacing in the
  /// editor too — a plan that silently lost a door is one that gives wrong
  /// directions forever after.
  Map<String, int> get incompleteCorridors => {
    for (final room in rooms)
      if (room.isCirculation && declaredDoorCounts.containsKey(room.id))
        if (openingsOn(room.id).length != declaredDoorCounts[room.id])
          room.id: declaredDoorCounts[room.id]! - openingsOn(room.id).length,
  };

  /// Whether the whole plan is safe to generate door-counting directions from.
  bool get isRoutable => incompleteCorridors.isEmpty;
}
