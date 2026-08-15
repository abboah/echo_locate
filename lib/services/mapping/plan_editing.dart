// Changing geometry that has already been traced.
//
// Everything before this was add-and-delete: the tracer appends rooms, doors
// and corridors, the editor removes whole ones. Nothing anywhere could alter a
// shape, so a corridor traced twenty metres too long could only be deleted —
// taking every door onto it, and the work of placing them, with it.
//
// These are pure functions over a [RoomPlan] so the rules live in one place and
// can be tested without a canvas. Each returns the new plan together with the
// number of doors it had to drop, because an edit that silently removes doors
// is an edit nobody can trust.
//
// Three rules are constant throughout:
//
//   * **Refuse rather than destroy.** An edit that would leave a room with
//     fewer than three corners, a corridor with fewer than two points, or a
//     room whose walls cross, returns the plan unchanged. The caller can see
//     nothing happened and the contributor still has their floor.
//   * **Openings follow their room.** A door onto a stretch of corridor that no
//     longer exists cannot route anywhere, so it goes — and is counted.
//   * **Edits are read placed and written stored.** Points arrive from a canvas
//     drawing [RoomPlan.rooms], which has each wing's [WingPlacement] applied;
//     they are saved into [RoomPlan.storedRooms], which does not. So every
//     incoming position goes through [WingPlacement.unapply] first, and every
//     comparison happens in one frame. Skipping that stores a corner with the
//     placement baked in, and the next read applies it a second time — a wing
//     that jumps by its own offset the moment anybody drags a corner of it.

import 'dart:ui' show Offset, Rect;

import '../../core/models/room_plan.dart';
import 'room_geometry.dart';

/// A plan after an edit, and what the edit cost.
typedef EditedPlan = ({RoomPlan plan, int doorsDropped});

/// How far a door may sit from its room's geometry before the edit is treated
/// as having removed the wall it was in, as a fraction of the floor's longest
/// side.
///
/// Generous on purpose. A door nudged slightly by a corner move is still that
/// door; only one left stranded by a trimmed-away section should be dropped.
const double kOrphanFraction = 0.04;

/// Moves one point of a corridor's centreline, rebuilding the band around it.
///
/// [to] is where the finger is, in the placed frame the canvas draws.
EditedPlan moveCorridorPoint(
  RoomPlan plan,
  String roomId,
  int index,
  Offset to,
) {
  final local = plan.placementOfRoom(roomId).unapply(to);
  return _editCorridor(plan, roomId, (points) {
    if (index < 0 || index >= points.length) return null;
    final next = [...points];
    next[index] = local;
    return next;
  }, dropOrphans: false);
}

/// Removes one point from a corridor's centreline.
EditedPlan deleteCorridorPoint(RoomPlan plan, String roomId, int index) =>
    _editCorridor(plan, roomId, (points) {
      if (index < 0 || index >= points.length) return null;
      final next = [...points]..removeAt(index);
      return next;
    });

/// Drops everything past [index], keeping the run up to and including it.
///
/// The fix for a corridor traced further than the building goes: the tail is
/// removed and the doors along the part that survives are untouched.
EditedPlan trimCorridorAfter(RoomPlan plan, String roomId, int index) =>
    _editCorridor(plan, roomId, (points) {
      if (index < 0 || index >= points.length) return null;
      return points.sublist(0, index + 1);
    });

/// Drops everything before [index], keeping the run from it onwards.
EditedPlan trimCorridorBefore(RoomPlan plan, String roomId, int index) =>
    _editCorridor(plan, roomId, (points) {
      if (index < 0 || index >= points.length) return null;
      return points.sublist(index);
    });

/// Moves one corner of a room.
///
/// [to] is where the finger is, in the placed frame the canvas draws.
EditedPlan moveRoomCorner(
  RoomPlan plan,
  String roomId,
  int index,
  Offset to,
) {
  final local = plan.placementOfRoom(roomId).unapply(to);
  return _editRoomPolygon(plan, roomId, (corners) {
    if (index < 0 || index >= corners.length) return null;
    final next = [...corners];
    next[index] = local;
    return next;
  }, dropOrphans: false);
}

/// Slides a whole room — polygon, centreline and its doors — by [by].
///
/// [by] is a movement of the finger across the drawing, so only the wing's
/// rotation is undone and not its offset: a delta says how far, not where.
///
/// The doors go along with it. A door is in a wall, and a wall that moves takes
/// its door with it; leaving them behind would strand every one of them the
/// moment somebody nudged a room a hand's width, which is the common case —
/// a room traced slightly off where the board shows it.
EditedPlan moveRoom(RoomPlan plan, String roomId, Offset by) {
  final room = plan.storedRoomOf(roomId);
  if (room == null) return (plan: plan, doorsDropped: 0);

  final local = plan.placementOfRoom(roomId).unrotate(by);
  if (local == Offset.zero) return (plan: plan, doorsDropped: 0);

  // No validity check, and none is needed: a translation cannot cross a room's
  // own walls or flatten it. It is the one edit here that can never be refused.
  final moved = room.copyWith(
    polygon: [for (final c in room.polygon) RoomCorner.of(c.offset + local)],
    centreline: [
      for (final c in room.centreline) RoomCorner.of(c.offset + local),
    ],
  );

  return (
    plan: plan.copyWith(
      storedRooms: [
        for (final r in plan.storedRooms) if (r.id == roomId) moved else r,
      ],
      storedOpenings: [
        for (final o in plan.storedOpenings)
          if (o.touches(roomId))
            o.copyWith(
              // In the frame the opening is stored in, which is its room A's —
              // see [RoomPlan.openings]. For a door joining two wings that is
              // not the moved room's frame, so the delta is turned into the
              // door's own before it is added.
              at: RoomCorner.of(
                o.at.offset + plan.placementOfRoom(o.roomAId).unrotate(by),
              ),
            )
          else
            o,
      ],
    ),
    doorsDropped: 0,
  );
}

/// Removes one corner of a room.
EditedPlan deleteRoomCorner(RoomPlan plan, String roomId, int index) =>
    _editRoomPolygon(plan, roomId, (corners) {
      if (index < 0 || index >= corners.length) return null;
      final next = [...corners]..removeAt(index);
      return next;
    });

/// Adds a corner on the wall running from [afterIndex] to the next corner.
///
/// Halfway along by default, which is where somebody who wants to pull a wall
/// into an L is about to drag it.
EditedPlan insertRoomCorner(
  RoomPlan plan,
  String roomId,
  int afterIndex, {
  Offset? at,
}) {
  final local = at == null ? null : plan.placementOfRoom(roomId).unapply(at);
  return _editRoomPolygon(plan, roomId, (corners) {
    if (afterIndex < 0 || afterIndex >= corners.length) return null;
    final a = corners[afterIndex];
    final b = corners[(afterIndex + 1) % corners.length];
    final next = [...corners]..insert(afterIndex + 1, local ?? (a + b) / 2);
    return next;
  });
}

// ---------------------------------------------------------------------------

EditedPlan _editCorridor(
  RoomPlan plan,
  String roomId,
  List<Offset>? Function(List<Offset>) change, {
  bool dropOrphans = true,
}) {
  final room = plan.storedRoomOf(roomId);
  if (room == null || !room.hasSpine) return (plan: plan, doorsDropped: 0);

  final points = change(room.spine);
  // A corridor is a line: two points is the least that still has a direction,
  // and direction is what "turn left" is computed from.
  if (points == null || points.length < 2) return (plan: plan, doorsDropped: 0);

  final band = ribbonAround(points, _corridorHalfWidth(plan, room.wingId));
  if (band.length < 3) return (plan: plan, doorsDropped: 0);

  final edited = room.copyWith(
    centreline: [for (final p in points) RoomCorner.of(p)],
    polygon: [for (final p in band) RoomCorner.of(p)],
  );
  return _replace(plan, edited, dropOrphans: dropOrphans);
}

EditedPlan _editRoomPolygon(
  RoomPlan plan,
  String roomId,
  List<Offset>? Function(List<Offset>) change, {
  bool dropOrphans = true,
}) {
  final room = plan.storedRoomOf(roomId);
  if (room == null || room.corners.length < 3) {
    return (plan: plan, doorsDropped: 0);
  }

  final corners = change(room.corners);
  if (corners == null || corners.length < 3) {
    return (plan: plan, doorsDropped: 0);
  }
  // Refused rather than cleaned: a bowtie has no meaningful centroid, and
  // silently straightening what somebody just dragged takes the edit away from
  // them. They can see it did not move and drag somewhere else.
  if (selfIntersects(corners)) return (plan: plan, doorsDropped: 0);

  // A corner dragged exactly onto another one collapses the room to a spike
  // with no area, which `selfIntersects` does not report — the walls never
  // cross, they fold flat. Left in, the room keeps a polygon, draws as a line
  // and routes as a destination nobody can stand in.
  if (areaOf(corners) <= 1e-9) return (plan: plan, doorsDropped: 0);

  return _replace(
    plan,
    room.copyWith(polygon: [for (final p in corners) RoomCorner.of(p)]),
    dropOrphans: dropOrphans,
  );
}

/// Swaps [edited] into the plan, dropping any door the change orphaned.
///
/// [dropOrphans] is false while a point is being *dragged*. A drag emits a
/// new plan on every frame, so scanning for orphans there would delete a
/// door the moment the finger passed a far-away position and never bring it
/// back when the finger came home — the shape recovers, the doors do not.
/// Removal belongs to the discrete acts: deleting a point, trimming a run.
EditedPlan _replace(RoomPlan plan, Room edited, {bool dropOrphans = true}) {
  final rooms = [
    for (final room in plan.storedRooms)
      if (room.id == edited.id) edited else room,
  ];

  final placement = plan.placementOfRoom(edited.id);
  final limit = _orphanLimit(plan, edited.wingId);
  final kept = <Opening>[];
  var dropped = 0;
  for (final opening in plan.storedOpenings) {
    if (!opening.touches(edited.id)) {
      kept.add(opening);
      continue;
    }
    // Both sides of the comparison in the edited room's own frame. A door is
    // stored in *its* room A's frame, which for a door between two wings is a
    // different one — measured raw, every such door reads as miles away and is
    // dropped the first time anybody deletes a corner near it.
    final at = placement.unapply(
      plan.placementOfRoom(opening.roomAId).apply(opening.at.offset),
    );
    if (!dropOrphans || _distanceTo(edited, at) <= limit) {
      kept.add(opening);
    } else {
      dropped++;
    }
  }

  return (
    plan: plan.copyWith(storedRooms: rooms, storedOpenings: kept),
    doorsDropped: dropped,
  );
}

/// How far [point] sits from the room — its centreline for a corridor, its
/// walls for anything else.
double _distanceTo(Room room, Offset point) {
  final path = room.hasSpine ? room.spine : room.corners;
  if (path.length < 2) return double.infinity;

  var best = double.infinity;
  final closed = !room.hasSpine;
  for (var i = 0; i + 1 < path.length + (closed ? 1 : 0); i++) {
    final a = path[i];
    final b = path[(i + 1) % path.length];
    final d = projectOntoSegment(a, b, point).distance;
    if (d < best) best = d;
  }
  return best;
}

double _orphanLimit(RoomPlan plan, String? wingId) =>
    _spanOfWing(plan, wingId) * kOrphanFraction;

/// Corridors are drawn as a fixed fraction of the floor, matching the width the
/// tracer gives one — see `RoomTraceBloc.corridorWidthUnits`. Derived from the
/// plan rather than imported so a metric plan and a traced one both get a band
/// that looks like a corridor.
double _corridorHalfWidth(RoomPlan plan, String? wingId) =>
    _spanOfWing(plan, wingId) * 0.02 / 2;

/// How large the floor is, measured in the frame the edit is happening in.
///
/// One wing's own stored extent rather than [RoomPlan.bounds], which is the
/// extent of everything *placed*. A newly traced wing is parked clear of the
/// building — half a floor away by `RoomTraceBloc.parkingGapUnits` — so the
/// placed bounds of a two-wing floor are roughly double the building, and both
/// tolerances derived from it come out twice as generous as they read: a
/// corridor edited on such a floor is rebuilt at double width, visibly fatter
/// than the one the tracer drew.
///
/// Falls back to the whole floor for a plan whose rooms are in no wing at all,
/// where the two are the same measurement anyway.
double _spanOfWing(RoomPlan plan, String? wingId) {
  Rect? box;
  for (final room in plan.storedRooms) {
    if (room.isStub || room.wingId != wingId) continue;
    box = box == null ? room.bounds : box.expandToInclude(room.bounds);
  }
  final span = box?.longestSide ?? 0;
  if (span > 0) return span;
  final whole = plan.bounds.longestSide;
  return whole <= 0 ? 1 : whole;
}
