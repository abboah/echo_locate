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
// Two rules are constant throughout:
//
//   * **Refuse rather than destroy.** An edit that would leave a room with
//     fewer than three corners, a corridor with fewer than two points, or a
//     room whose walls cross, returns the plan unchanged. The caller can see
//     nothing happened and the contributor still has their floor.
//   * **Openings follow their room.** A door onto a stretch of corridor that no
//     longer exists cannot route anywhere, so it goes — and is counted.

import 'dart:ui' show Offset;

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
EditedPlan moveCorridorPoint(
  RoomPlan plan,
  String roomId,
  int index,
  Offset to,
) => _editCorridor(plan, roomId, (points) {
  if (index < 0 || index >= points.length) return null;
  final next = [...points];
  next[index] = to;
  return next;
}, dropOrphans: false);

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
EditedPlan moveRoomCorner(
  RoomPlan plan,
  String roomId,
  int index,
  Offset to,
) => _editRoomPolygon(plan, roomId, (corners) {
  if (index < 0 || index >= corners.length) return null;
  final next = [...corners];
  next[index] = to;
  return next;
}, dropOrphans: false);

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
}) => _editRoomPolygon(plan, roomId, (corners) {
  if (afterIndex < 0 || afterIndex >= corners.length) return null;
  final a = corners[afterIndex];
  final b = corners[(afterIndex + 1) % corners.length];
  final next = [...corners]..insert(afterIndex + 1, at ?? (a + b) / 2);
  return next;
});

// ---------------------------------------------------------------------------

EditedPlan _editCorridor(
  RoomPlan plan,
  String roomId,
  List<Offset>? Function(List<Offset>) change, {
  bool dropOrphans = true,
}) {
  final room = _roomIn(plan, roomId);
  if (room == null || !room.hasSpine) return (plan: plan, doorsDropped: 0);

  final points = change(room.spine);
  // A corridor is a line: two points is the least that still has a direction,
  // and direction is what "turn left" is computed from.
  if (points == null || points.length < 2) return (plan: plan, doorsDropped: 0);

  final band = ribbonAround(points, _corridorHalfWidth(plan));
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
  final room = _roomIn(plan, roomId);
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
    for (final room in plan.rooms) if (room.id == edited.id) edited else room,
  ];

  final limit = _orphanLimit(plan);
  final kept = <Opening>[];
  var dropped = 0;
  for (final opening in plan.openings) {
    if (!opening.touches(edited.id)) {
      kept.add(opening);
      continue;
    }
    if (!dropOrphans || _distanceTo(edited, opening.at.offset) <= limit) {
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

double _orphanLimit(RoomPlan plan) {
  final span = plan.bounds.longestSide;
  return (span <= 0 ? 1 : span) * kOrphanFraction;
}

/// Corridors are drawn as a fixed fraction of the floor, matching the width the
/// tracer gives one — see `RoomTraceBloc.corridorWidthUnits`. Derived from the
/// plan rather than imported so a metric plan and a traced one both get a band
/// that looks like a corridor.
double _corridorHalfWidth(RoomPlan plan) {
  final span = plan.bounds.longestSide;
  return (span <= 0 ? 1 : span) * 0.02 / 2;
}

Room? _roomIn(RoomPlan plan, String roomId) {
  for (final room in plan.rooms) {
    if (room.id == roomId) return room;
  }
  return null;
}
