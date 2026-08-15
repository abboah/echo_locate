// Squaring a whole floor at once — the pass `cleanupPolygon` cannot do.
//
// `room_cleanup.dart` cleans one room as it is closed, snapping it to the grid
// **that room's own walls vote for**. That is the right call at trace time: it
// is all the information available while a single polygon is being drawn, and
// it makes each room rectilinear on its own terms.
//
// The cost only shows up once a floor is finished. Thirty-five rooms cast
// thirty-five independent votes, so every room ends up square with itself and a
// fraction of a degree out of step with its neighbours. Walls that are one wall
// in the building end up as two lines a hair apart; rooms that share a wall
// leave a hairline gap or overlap. Nothing is wrong enough to see room by room
// and the floor reads as hand-drawn.
//
// This is the second pass: one vote across every wall on the floor, then a
// single shared grid that all the rooms snap to. Measured on a real traced
// floor (KNUST Library ground, 35 rooms), 170 traced corners collapsed onto 27
// vertical and 26 horizontal wall lines with no room lost.
//
// It rewrites geometry, so it is an action somebody takes and can undo — never
// something that runs on save.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../core/models/room_plan.dart';

/// How far apart two corners may be and still be the same corner, as a
/// fraction of the floor's longest side.
///
/// 1% of a 60 m floor is 60 cm — wider than the tracing error and narrower than
/// any real room, which is the window this has to sit in. Too tight and nothing
/// welds; too loose and two genuinely different walls merge into one and a room
/// loses its shape.
const double kWeldFraction = 0.010;

/// The floor's dominant wall bearing, in radians, folded into ±45°.
///
/// Every wall votes, weighted by its own length: a 20 m corridor wall fixes a
/// bearing far better than a 2 m cupboard wall, and an unweighted vote lets a
/// crowd of tiny edges outvote the walls that actually define the building.
///
/// The vote is taken on `4 * bearing` because a rectilinear building's walls
/// point four ways and all four mean the same grid — quadrupling the angle maps
/// 0°, 90°, 180° and 270° onto the same direction, so they reinforce instead of
/// cancelling.
double dominantSkew(RoomPlan plan) {
  var x = 0.0;
  var y = 0.0;
  for (final room in plan.rooms) {
    final corners = room.corners;
    if (corners.length < 2) continue;
    for (var i = 0; i < corners.length; i++) {
      final edge = corners[(i + 1) % corners.length] - corners[i];
      final length = edge.distance;
      if (length < 1e-9) continue;
      final bearing = math.atan2(edge.dy, edge.dx);
      x += length * math.cos(4 * bearing);
      y += length * math.sin(4 * bearing);
    }
  }
  if (x.abs() < 1e-12 && y.abs() < 1e-12) return 0;
  return math.atan2(y, x) / 4;
}

/// Rotates the floor onto its own grid, then welds its walls together.
///
/// Returns the plan unchanged when there is nothing to work with. Rooms whose
/// polygon would collapse below three corners keep their original geometry:
/// losing a room to a cleanup is far worse than leaving one unsquared, and a
/// room that collapses is the signal the tolerance is wrong for this floor.
///
/// Openings and centrelines are carried through the same transform, so doors
/// stay in the walls they were placed in and corridors keep their spines.
RoomPlan squareFloor(RoomPlan plan, {double weldFraction = kWeldFraction}) {
  final drawable = [for (final r in plan.rooms) if (r.corners.length >= 3) r];
  if (drawable.isEmpty) return plan;

  // --- rotate onto the grid ------------------------------------------------
  final skew = dominantSkew(plan);
  var cx = 0.0, cy = 0.0, n = 0;
  for (final room in drawable) {
    for (final c in room.corners) {
      cx += c.dx;
      cy += c.dy;
      n++;
    }
  }
  cx /= n;
  cy /= n;

  final cos = math.cos(-skew);
  final sin = math.sin(-skew);
  Offset rotate(Offset p) {
    final dx = p.dx - cx;
    final dy = p.dy - cy;
    return Offset(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos);
  }

  // --- one grid for the whole floor ---------------------------------------
  final xs = <double>[];
  final ys = <double>[];
  for (final room in drawable) {
    for (final c in room.corners) {
      final p = rotate(c);
      xs.add(p.dx);
      ys.add(p.dy);
    }
  }
  final span = math.max(
    xs.reduce(math.max) - xs.reduce(math.min),
    ys.reduce(math.max) - ys.reduce(math.min),
  );
  final tolerance = span * weldFraction;
  if (tolerance <= 0) return plan;

  final gridX = _cluster(xs, tolerance);
  final gridY = _cluster(ys, tolerance);
  Offset snap(Offset p) => Offset(
    _nearest(p.dx, gridX, tolerance),
    _nearest(p.dy, gridY, tolerance),
  );
  Offset place(Offset p) => snap(rotate(p));

  final rooms = [
    for (final room in plan.rooms)
      if (room.corners.length < 3)
        room.copyWith(
          centreline: [
            for (final p in room.centreline) RoomCorner.of(place(p.offset)),
          ],
        )
      else
        _squared(room, place),
  ];

  return plan.copyWith(
    storedRooms: rooms,
    storedOpenings: [
      for (final o in plan.openings)
        o.copyWith(at: RoomCorner.of(place(o.at.offset))),
    ],
  );
}

Room _squared(Room room, Offset Function(Offset) place) {
  final moved = [for (final c in room.corners) place(c)];

  // Corners the weld landed on top of each other are one corner now.
  final deduped = <Offset>[];
  for (var i = 0; i < moved.length; i++) {
    final previous = deduped.isEmpty ? moved.last : deduped.last;
    if ((moved[i] - previous).distance > 1e-9) deduped.add(moved[i]);
  }

  // Refuse rather than destroy — see the doc on [squareFloor].
  if (deduped.length < 3) return room;

  return room.copyWith(
    polygon: [for (final p in deduped) RoomCorner.of(p)],
    centreline: [
      for (final p in room.centreline) RoomCorner.of(place(p.offset)),
    ],
  );
}

/// Sorted single-linkage clustering: values within [tolerance] of the running
/// group join it, and each group collapses to its own mean.
///
/// The mean rather than the first value, so a wall does not drift towards
/// whichever of its corners happened to be traced first.
List<double> _cluster(List<double> values, double tolerance) {
  final sorted = [...values]..sort();
  final out = <double>[];
  var group = <double>[sorted.first];
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] - group.last <= tolerance) {
      group.add(sorted[i]);
    } else {
      out.add(group.reduce((a, b) => a + b) / group.length);
      group = [sorted[i]];
    }
  }
  out.add(group.reduce((a, b) => a + b) / group.length);
  return out;
}

/// The grid line [value] belongs to, or [value] itself when none is close
/// enough to claim it.
double _nearest(double value, List<double> grid, double tolerance) {
  var best = value;
  var bestDistance = double.infinity;
  for (final line in grid) {
    final d = (value - line).abs();
    if (d < bestDistance) {
      bestDistance = d;
      best = line;
    }
  }
  return bestDistance <= tolerance ? best : value;
}
