// Turning tapped corners into architecture — floorplan spec §4.
//
// Corners arrive from a finger on a photograph or a tap on an AR floor plane.
// Neither is precise: a 4 m wall comes back 3.94 m, a right angle comes back
// 87°, and a slipped finger leaves a 4 cm edge nobody meant to draw. Rendered
// raw, the plan reads as hand-drawn and — worse — the near-parallel walls stop
// the "is there a door between these two rooms?" check in the editor from ever
// firing.
//
// The fix is the one piece of prior knowledge this problem actually gives you:
// **institutional buildings are rectilinear.** Lecture halls, offices and
// corridors meet at right angles because that is how they were poured. So the
// cleanup does not smooth or fit curves; it snaps to a grid the polygon itself
// declares, and rebuilds the corners from the snapped walls.
//
// Order matters, and it is the order below:
//   1. drop edges too short to be a wall (they are slips, and they carry
//      meaningless bearings that would corrupt the dominant-axis vote)
//   2. merge runs of near-collinear edges (three taps along one wall are one
//      wall, and left separate they each get snapped independently)
//   3. snap the survivors to the dominant grid and re-intersect
//
// Doing 3 before 1 lets a 4 cm slip rotate a whole wall. Doing 3 before 2 can
// snap one physical wall two different ways and put a step in it.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'room_geometry.dart';

/// How far off a right angle a wall may be and still be treated as one.
///
/// 8° is the spec's starting value and it is a genuine trade-off, not a
/// constant to forget about: too tight and nothing snaps, too loose and a
/// deliberately splayed lecture theatre gets squared into a box it is not.
/// Tune against real captures — see `test/room_cleanup_test.dart`, which pins
/// the behaviour either side of the threshold.
const double kSnapToleranceDeg = 8;

/// Two edges whose bearings differ by less than this are one wall.
const double kCollinearToleranceDeg = 5;

/// Edges shorter than this are finger slips, not walls. 30 cm is narrower than
/// any real doorway, so nothing load-bearing is ever dropped.
const double kMinEdgeMetres = 0.30;

/// Raw tapped corners in, clean rectilinear room out.
///
/// Always returns counter-clockwise winding — see [normaliseWinding] for why
/// that is not optional. Polygons with fewer than three surviving corners are
/// returned as-is: there is no shape to clean and the caller has a capture to
/// reject, which it can see for itself from the length.
List<Offset> cleanupPolygon(
  List<Offset> raw, {
  double snapToleranceDeg = kSnapToleranceDeg,
  double collinearToleranceDeg = kCollinearToleranceDeg,
  double minEdgeMetres = kMinEdgeMetres,
}) {
  if (raw.length < 3) return List<Offset>.of(raw);

  var polygon = dropShortEdges(raw, minEdgeMetres);
  if (polygon.length < 3) return normaliseWinding(polygon);

  polygon = mergeCollinear(polygon, collinearToleranceDeg);
  if (polygon.length < 3) return normaliseWinding(polygon);

  polygon = snapRightAngles(polygon, snapToleranceDeg);
  return normaliseWinding(polygon);
}

/// Drops vertices that sit less than [minMetres] from the previous survivor.
///
/// Walks the ring keeping a running anchor rather than comparing neighbouring
/// pairs: a wall tapped as five points 10 cm apart is one slip five times over,
/// and pairwise comparison would keep every one of them because each is only
/// 10 cm from the *last kept* — which is the behaviour we want — but the naive
/// version compares against the original neighbour and keeps them all.
///
/// The closing edge is checked too: a final tap landing on top of the first
/// corner is the most common way to end a trace, and it leaves a zero-length
/// edge that makes the bearing at that corner `atan2(0, 0)`.
List<Offset> dropShortEdges(List<Offset> polygon, double minMetres) {
  if (polygon.length < 3) return List<Offset>.of(polygon);

  final kept = <Offset>[polygon.first];
  for (var i = 1; i < polygon.length; i++) {
    if ((polygon[i] - kept.last).distance >= minMetres) kept.add(polygon[i]);
  }

  // The ring has to close as well as run.
  while (kept.length > 3 && (kept.last - kept.first).distance < minMetres) {
    kept.removeLast();
  }

  return kept.length < 3 ? List<Offset>.of(polygon) : kept;
}

/// Removes a corner whose two edges run within [toleranceDeg] of each other.
///
/// Three taps along one wall are one wall. Left in, the middle corner gets its
/// own bearing vote in [snapRightAngles] and can be snapped a different way
/// from its neighbours, putting a phantom step in a flat wall.
///
/// Iterates to a fixed point: removing one corner can bring the two either
/// side into line, and a wall tapped six times should collapse to two corners,
/// not five.
List<Offset> mergeCollinear(List<Offset> polygon, double toleranceDeg) {
  var current = List<Offset>.of(polygon);
  final tolerance = toleranceDeg * math.pi / 180;

  var changed = true;
  while (changed && current.length > 3) {
    changed = false;
    for (var i = 0; i < current.length; i++) {
      final previous = current[(i - 1 + current.length) % current.length];
      final vertex = current[i];
      final next = current[(i + 1) % current.length];

      final incoming = vertex - previous;
      final outgoing = next - vertex;
      if (incoming.distanceSquared < 1e-12 ||
          outgoing.distanceSquared < 1e-12) {
        current.removeAt(i);
        changed = true;
        break;
      }

      // The turn at this corner. Near zero means the wall carries straight on.
      if (signedTurnRad(incoming, outgoing).abs() <= tolerance) {
        current.removeAt(i);
        changed = true;
        break;
      }
    }
  }

  return current;
}

/// Snaps every wall to the polygon's own grid, then rebuilds the corners.
///
/// Snapping bearings alone would leave the walls no longer meeting — each one
/// rotates about its own midpoint and the corners come apart. So the snapped
/// bearings define *lines* through the original edge midpoints, and each new
/// corner is the intersection of consecutive lines. That is what makes the
/// output a closed rectilinear polygon rather than a pinwheel.
List<Offset> snapRightAngles(List<Offset> polygon, double toleranceDeg) {
  if (polygon.length < 3) return List<Offset>.of(polygon);

  final grid = dominantBearing(polygon);
  const quarter = math.pi / 2;
  final lines = <_Line>[];

  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final edge = b - a;
    if (edge.distanceSquared < 1e-12) {
      lines.add(_Line(a, const Offset(1, 0)));
      continue;
    }

    var bearing = math.atan2(edge.dy, edge.dx);
    final nearest = grid + ((bearing - grid) / quarter).round() * quarter;
    // Compared as an angle difference, not a raw subtraction: a wall at 179°
    // and a grid line at -179° are 2° apart, not 358°.
    if (_angleGap(nearest, bearing) * 180 / math.pi <= toleranceDeg) {
      bearing = nearest;
    }

    final midpoint = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    lines.add(_Line(midpoint, Offset(math.cos(bearing), math.sin(bearing))));
  }

  final out = <Offset>[];
  for (var i = 0; i < lines.length; i++) {
    final previous = lines[(i - 1 + lines.length) % lines.length];
    // Parallel neighbours have no corner to compute — which happens when a
    // collinear pair survived the merge. Keeping the original vertex is the
    // conservative answer: slightly uncleaned beats teleported to infinity.
    out.add(_intersectLines(previous, lines[i]) ?? polygon[i]);
  }

  // A snap that moved a corner further than the room is wide has gone wrong —
  // near-parallel lines intersecting far away. Fall back rather than ship it.
  final diagonal = boundsOf(polygon).longestSide;
  for (var i = 0; i < out.length; i++) {
    if ((out[i] - polygon[i]).distance > diagonal) return polygon;
  }

  return out;
}

/// The bearing of the building grid this polygon belongs to, in (-π/2, π/2].
///
/// Taken from the longest wall, and taken modulo 90° because a rectangle's
/// four walls all describe the same grid. The longest wall wins because it is
/// the best-measured: two taps 12 m apart fix a bearing far more tightly than
/// two taps 1 m apart, where a 3 cm slip is a 2° error.
double dominantBearing(List<Offset> polygon) {
  var best = 0.0;
  var bestLength = -1.0;

  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final length = (b - a).distance;
    if (length > bestLength) {
      bestLength = length;
      best = math.atan2(b.dy - a.dy, b.dx - a.dx);
    }
  }

  const quarter = math.pi / 2;
  // Dart's % returns a non-negative result for a positive divisor, so this
  // lands in [0, π/2) for any input including negative bearings.
  return best % quarter;
}

/// Smallest absolute angle between two bearings, in radians.
double _angleGap(double a, double b) {
  var gap = (a - b) % (math.pi * 2);
  if (gap > math.pi) gap -= math.pi * 2;
  if (gap < -math.pi) gap += math.pi * 2;
  return gap.abs();
}

/// An infinite line: a point on it and a unit direction.
class _Line {
  const _Line(this.point, this.direction);

  final Offset point;
  final Offset direction;
}

/// Where two infinite lines meet, or null when they are parallel.
Offset? _intersectLines(_Line a, _Line b) {
  final denominator =
      a.direction.dx * b.direction.dy - a.direction.dy * b.direction.dx;
  if (denominator.abs() < 1e-9) return null;

  final t =
      ((b.point.dx - a.point.dx) * b.direction.dy -
          (b.point.dy - a.point.dy) * b.direction.dx) /
      denominator;
  return a.point + Offset(a.direction.dx * t, a.direction.dy * t);
}
