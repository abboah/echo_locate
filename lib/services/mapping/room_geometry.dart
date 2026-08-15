// Polygon primitives for room-shaped floor plans — floorplan spec §0 and §4.
//
// The landmark map (`route_layout.dart`, `floor_graph.dart`) models a floor as
// *points and corridors between them*. That is enough to route, and it is what
// guidance speaks. It cannot say how wide a room is, where its door sits along
// a corridor wall, or what colour to fill it — so it cannot draw the schematic
// people actually read off a wall board. This file adds the missing half:
// rooms as areas.
//
// ## Coordinate frame — read this before touching anything below
//
// **+x is east, +y is north, in metres.** Identical to [MapNode], deliberately:
// a room polygon and a landmark node are drawn on the same canvas by the same
// viewport, and two frames in one renderer is how a plan comes out mirrored.
// `PlanViewport.toCanvasY` already flips y for the canvas, and it is tested.
//
// The floorplan spec writes its geometry in a *canvas* frame instead (y down,
// `plan.y = arcore.z`), which is the mirror of this one. Every orientation
// predicate — cross product sign, winding, left vs right — inverts between the
// two. The spec's own §0 warns about exactly this and then ships a constant
// whose doc comment contradicts its test. Rather than import that confusion:
//
//   **this file is a right-handed y-north frame, so a positive cross product
//   means counter-clockwise, which means LEFT.**
//
// That is the ordinary mathematical convention, it needs no calibration
// constant, and [signedTurnRad] is the single place it is encoded. Anything
// that needs "which way do I turn" calls that function; nothing re-derives it
// from a cross product of its own. See `room_directions.dart`, which converts
// once into the repo's existing degrees-positive-is-right convention so the
// codebase speaks one language rather than two.

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Twice the signed area, positive when [polygon] winds counter-clockwise in
/// the y-north frame.
double signedArea(List<Offset> polygon) {
  if (polygon.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum / 2;
}

/// Unsigned area in square metres.
double areaOf(List<Offset> polygon) => signedArea(polygon).abs();

/// Forces counter-clockwise winding.
///
/// **The single most dangerous invariant in this file.** Side-of-path
/// determination — "the second door on your *left*" — reads its answer from a
/// cross product whose sign depends on winding. Mixed winding across a floor
/// does not invert left and right everywhere, which would at least be obvious;
/// it inverts them *for some rooms only*, which walking one route will not
/// catch. Normalise on the way in, never at the point of use.
List<Offset> normaliseWinding(List<Offset> polygon) =>
    signedArea(polygon) < 0 ? polygon.reversed.toList() : polygon;

/// Whether any two non-adjacent edges cross — a bowtie, and never a room.
///
/// Traced by finger or tapped in AR, a polygon crosses itself the moment
/// somebody puts a corner down out of order. Caught here, it is a "that shape
/// is not a room" prompt; uncaught, it produces a negative-area room whose
/// centroid lands somewhere arbitrary and whose winding cannot be normalised.
bool selfIntersects(List<Offset> polygon) {
  final n = polygon.length;
  if (n < 4) return false;

  for (var i = 0; i < n; i++) {
    for (var j = i + 2; j < n; j++) {
      // The first and last edges share a vertex like any other adjacent pair.
      if (i == 0 && j == n - 1) continue;
      if (_segmentsCross(
        polygon[i],
        polygon[(i + 1) % n],
        polygon[j],
        polygon[(j + 1) % n],
      )) {
        return true;
      }
    }
  }
  return false;
}

bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
  double cross(Offset o, Offset p, Offset q) =>
      (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);

  final d1 = cross(c, d, a);
  final d2 = cross(c, d, b);
  final d3 = cross(a, b, c);
  final d4 = cross(a, b, d);
  return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
}

/// Whether the segment a→b enters [polygon] at all.
///
/// Used to catch a corridor drawn straight through a room. Both cases count:
/// a segment that cuts across the room crosses its walls, and a segment lying
/// wholly inside it crosses nothing — so the midpoint is checked as well.
bool segmentEntersPolygon(List<Offset> polygon, Offset a, Offset b) {
  if (polygon.length < 3) return false;

  for (var i = 0; i < polygon.length; i++) {
    if (_segmentsCross(a, b, polygon[i], polygon[(i + 1) % polygon.length])) {
      return true;
    }
  }
  return containsPoint(polygon, (a + b) / 2);
}

/// Ray-casting point-in-polygon. Boundary cases are not defined and do not
/// need to be — every caller is asking about a tap or a centroid, never about
/// a point sitting exactly on a wall.
bool containsPoint(List<Offset> polygon, Offset point) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.dy > point.dy) != (b.dy > point.dy) &&
        point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Area-weighted centroid.
///
/// Not the vertex average, which for an L-shaped room sits out in the missing
/// corner and puts the room's label in the corridor next door.
Offset areaCentroid(List<Offset> polygon) {
  if (polygon.isEmpty) return Offset.zero;
  if (polygon.length < 3) return polygon.first;

  var area = 0.0;
  var cx = 0.0;
  var cy = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final p = polygon[i];
    final q = polygon[(i + 1) % polygon.length];
    final f = p.dx * q.dy - q.dx * p.dy;
    area += f;
    cx += (p.dx + q.dx) * f;
    cy += (p.dy + q.dy) * f;
  }
  area *= 0.5;

  // Degenerate: every vertex collinear, or duplicated onto one point.
  if (area.abs() < 1e-9) return polygon.first;
  return Offset(cx / (6 * area), cy / (6 * area));
}

/// A point guaranteed to lie inside [polygon] — where a label can go.
///
/// The area centroid is the right answer for a convex or mildly concave room
/// and is tried first. But it is **not** guaranteed to be interior: a thin
/// L-shape puts it in the notch, outside the room entirely, and a U-shaped
/// lecture theatre puts it in the gap between the arms. The spec's §10 asserts
/// the centroid of an L falls inside the polygon, which is not a property the
/// centroid has.
///
/// The fallback is a scanline: cast a horizontal ray through the centroid's
/// latitude, take the widest interior span, and return its midpoint. That is
/// cheap, always interior for a simple polygon, and lands the label in the
/// widest part of the room, which is where it should have gone anyway.
Offset interiorPoint(List<Offset> polygon) {
  if (polygon.length < 3) return areaCentroid(polygon);

  final centroid = areaCentroid(polygon);
  if (containsPoint(polygon, centroid)) return centroid;

  final widest = _widestSpanAt(polygon, centroid.dy);
  if (widest != null) return widest;

  // Every scanline degenerate (a zero-area sliver). Nothing sensible to
  // return, so return something stable rather than something wrong.
  return centroid;
}

/// Midpoint of the widest interior run of the horizontal line y = [y].
Offset? _widestSpanAt(List<Offset> polygon, double y) {
  final crossings = <double>[];
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.dy > y) != (b.dy > y)) {
      crossings.add((b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx);
    }
  }
  if (crossings.length < 2) return null;
  crossings.sort();

  // Crossings pair up into interior spans: [0,1] is inside, [1,2] is outside,
  // and so on. That is the same parity rule [containsPoint] uses.
  var bestWidth = 0.0;
  double? bestCentre;
  for (var i = 0; i + 1 < crossings.length; i += 2) {
    final width = crossings[i + 1] - crossings[i];
    if (width > bestWidth) {
      bestWidth = width;
      bestCentre = (crossings[i] + crossings[i + 1]) / 2;
    }
  }
  if (bestCentre == null || bestWidth <= 0) return null;
  return Offset(bestCentre, y);
}

/// Axis-aligned extent, in metres.
Rect boundsOf(List<Offset> polygon) {
  if (polygon.isEmpty) return Rect.zero;
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final p in polygon) {
    if (p.dx < left) left = p.dx;
    if (p.dx > right) right = p.dx;
    if (p.dy < top) top = p.dy;
    if (p.dy > bottom) bottom = p.dy;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

double perimeterOf(List<Offset> polygon) {
  if (polygon.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    total += (polygon[(i + 1) % polygon.length] - polygon[i]).distance;
  }
  return total;
}

/// The turn from [heading] onto [toTarget], in radians, in (-π, π].
///
/// **Positive is a LEFT turn** (counter-clockwise), because this is a
/// right-handed y-north frame. This function is the only place in the codebase
/// that decides that; see the header note. Callers wanting the repo's
/// degrees-positive-is-right convention use [turnDegreesRight].
///
/// Returns 0 when either vector is degenerate — two rooms whose centroids
/// coincide, or a leg of zero length — because "turn towards a place you are
/// already standing" has no answer and 0 keeps the walker facing forwards.
double signedTurnRad(Offset heading, Offset toTarget) {
  if (heading.distanceSquared < 1e-12 || toTarget.distanceSquared < 1e-12) {
    return 0;
  }
  final cross = heading.dx * toTarget.dy - heading.dy * toTarget.dx;
  final dot = heading.dx * toTarget.dx + heading.dy * toTarget.dy;
  return math.atan2(cross, dot);
}

/// [signedTurnRad] in degrees, **sign flipped so positive is RIGHT**.
///
/// Matches `PlannedLeg.turnDeg`, `route_layout`'s heading convention and the
/// turn buttons the capture UI already offers. Converting once, here, is what
/// keeps the room layer and the landmark layer from disagreeing about which
/// way is left.
double turnDegreesRight(Offset heading, Offset toTarget) =>
    -signedTurnRad(heading, toTarget) * 180 / math.pi;

/// Which side of the directed line a→b the point [p] falls on.
///
/// `-1` left, `1` right, `0` on the line. Same convention as
/// [turnDegreesRight]: positive is right.
int sideOfLine(Offset a, Offset b, Offset p) {
  final cross = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
  if (cross > 1e-9) return -1; // counter-clockwise => left
  if (cross < -1e-9) return 1;
  return 0;
}

/// Unit vector along the polygon's longest edge.
///
/// For a corridor this is its axis — the line a walker actually travels down.
/// The longest edge is the right proxy because a corridor's two long walls are
/// its longest edges by construction, and it is also the best-measured
/// direction in the polygon: two corners 20 m apart fix a bearing that two
/// corners 2 m apart cannot.
///
/// Approximate for an L-shaped corridor, which has no single axis. The proper
/// answer for those is to give the corridor a **centreline** — see
/// [projectOntoPolyline] and `Room.centreline` — which has a direction at every
/// point along it and so stays right around a bend. This remains the fallback
/// for a corridor traced as a bare polygon.
Offset longestEdgeDirection(List<Offset> polygon) {
  if (polygon.length < 2) return const Offset(1, 0);

  var best = const Offset(1, 0);
  var bestLength = -1.0;
  for (var i = 0; i < polygon.length; i++) {
    final edge = polygon[(i + 1) % polygon.length] - polygon[i];
    final length = edge.distance;
    if (length > bestLength) {
      bestLength = length;
      best = edge;
    }
  }
  return bestLength < 1e-9 ? const Offset(1, 0) : best / bestLength;
}

/// Distance from [p] to the segment a→b, and how far along it the nearest
/// point sits (0 at [a], 1 at [b]).
///
/// Used to place a door on a corridor wall and to order the doors a walker
/// passes. Clamped, so a point beyond either end measures to that end rather
/// than to the infinite line.
({double distance, double t}) projectOntoSegment(Offset a, Offset b, Offset p) {
  final ab = b - a;
  final lengthSq = ab.distanceSquared;
  if (lengthSq < 1e-12) return (distance: (p - a).distance, t: 0);

  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSq;
  t = t.clamp(0.0, 1.0);
  final closest = a + Offset(ab.dx * t, ab.dy * t);
  return (distance: (p - closest).distance, t: t);
}

/// Unit vector along the polygon edge nearest to [point].
///
/// The direction of the wall a door sits in. A door is a gap *along* its wall,
/// so drawing one without knowing that wall's bearing means guessing — and the
/// renderer guessed horizontal for every opening on every plan. On a vertical
/// wall that draws the gap straight through the wall instead of along it, so a
/// door came out as a blob sitting on the line rather than a hole in it.
///
/// Nearest edge rather than longest: a door belongs to the piece of wall it was
/// placed on, which on an L-shaped room is usually not the longest one.
/// Degenerate polygons fall back to horizontal, which is no worse than what
/// every opening used to get.
Offset nearestEdgeDirection(List<Offset> polygon, Offset point) {
  if (polygon.length < 2) return const Offset(1, 0);

  var best = const Offset(1, 0);
  var bestDistance = double.infinity;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final edge = b - a;
    if (edge.distance < 1e-9) continue;
    final hit = projectOntoSegment(a, b, point);
    if (hit.distance < bestDistance) {
      bestDistance = hit.distance;
      best = edge / edge.distance;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// Polylines — the centreline of a corridor.
//
// A corridor traced as a bare polygon has no direction of travel: everything
// downstream has to guess one from [longestEdgeDirection], which is a decent
// proxy for a straight hallway and simply wrong for an L. That guess decides
// which side of the corridor each door is on, so getting it wrong flips "left"
// and "right" in the one sentence the app must never get wrong.
//
// A centreline removes the guess. It is the line a walker actually follows, it
// has a direction at every point along it, and arc length along it is the real
// walking distance rather than the straight line through the walls.
// ---------------------------------------------------------------------------

/// Total length of an open polyline.
double polylineLength(List<Offset> polyline) {
  var total = 0.0;
  for (var i = 0; i + 1 < polyline.length; i++) {
    total += (polyline[i + 1] - polyline[i]).distance;
  }
  return total;
}

/// The point on [polyline] nearest [p].
///
/// `along` is arc length from the start, which is what orders the doors a
/// walker passes; `distance` is the perpendicular offset, which is how far they
/// step off the centreline to reach one.
({Offset at, double along, double distance, int index}) projectOntoPolyline(
  List<Offset> polyline,
  Offset p,
) {
  if (polyline.isEmpty) {
    return (at: p, along: 0, distance: double.infinity, index: 0);
  }
  if (polyline.length == 1) {
    return (
      at: polyline.first,
      along: 0,
      distance: (p - polyline.first).distance,
      index: 0,
    );
  }

  var best = (
    at: polyline.first,
    along: 0.0,
    distance: double.infinity,
    index: 0,
  );
  var travelled = 0.0;

  for (var i = 0; i + 1 < polyline.length; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];
    final length = (b - a).distance;
    final hit = projectOntoSegment(a, b, p);
    if (hit.distance < best.distance) {
      best = (
        at: a + (b - a) * hit.t,
        along: travelled + length * hit.t,
        distance: hit.distance,
        index: i,
      );
    }
    travelled += length;
  }
  return best;
}

/// The point [along] arc length from the start of [polyline], clamped to it.
Offset pointAlongPolyline(List<Offset> polyline, double along) {
  if (polyline.isEmpty) return Offset.zero;
  if (polyline.length == 1 || along <= 0) return polyline.first;

  var travelled = 0.0;
  for (var i = 0; i + 1 < polyline.length; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];
    final length = (b - a).distance;
    if (along <= travelled + length) {
      if (length < 1e-12) return a;
      return a + (b - a) * ((along - travelled) / length);
    }
    travelled += length;
  }
  return polyline.last;
}

/// Unit direction of travel at arc length [along], pointing towards the end.
Offset polylineDirectionAt(List<Offset> polyline, double along) {
  if (polyline.length < 2) return const Offset(1, 0);

  var travelled = 0.0;
  for (var i = 0; i + 1 < polyline.length; i++) {
    final segment = polyline[i + 1] - polyline[i];
    final length = segment.distance;
    if (length < 1e-12) continue;
    if (along <= travelled + length || i + 2 == polyline.length) {
      return segment / length;
    }
    travelled += length;
  }
  return const Offset(1, 0);
}

/// The stretch of [polyline] between two arc lengths, as its own polyline.
///
/// Walked in the direction implied by the arguments: passing `to` before `from`
/// returns the sub-path reversed, because a corridor is walked both ways and
/// the route has to be drawn the way the walker goes.
List<Offset> polylineSlice(List<Offset> polyline, double from, double to) {
  if (polyline.length < 2) return [...polyline];

  final reversed = to < from;
  final start = reversed ? to : from;
  final end = reversed ? from : to;

  final out = <Offset>[pointAlongPolyline(polyline, start)];
  var travelled = 0.0;
  for (var i = 0; i + 1 < polyline.length; i++) {
    travelled += (polyline[i + 1] - polyline[i]).distance;
    // Interior vertices strictly inside the span — the ends are already there,
    // and a duplicated vertex makes a zero-length leg the directions layer has
    // to skip.
    if (travelled > start + 1e-9 && travelled < end - 1e-9) {
      out.add(polyline[i + 1]);
    }
  }
  out.add(pointAlongPolyline(polyline, end));

  return reversed ? out.reversed.toList() : out;
}

/// A closed polygon [halfWidth] either side of [polyline] — a corridor drawn
/// from the line down its middle.
///
/// Mitred at the bends so the two sides stay parallel to the centreline rather
/// than notching in at every vertex. The mitre is capped: at a hairpin the exact
/// mitre runs off to infinity, and a bevel that is slightly wrong at one corner
/// is better than a spike across the floor.
List<Offset> ribbonAround(List<Offset> polyline, double halfWidth) {
  final points = _withoutRepeats(polyline);
  if (points.length < 2 || halfWidth <= 0) return const [];

  /// Left-hand normal: +90° in the y-north frame, which is counter-clockwise,
  /// which is left — the same convention [sideOfLine] encodes.
  Offset leftOf(Offset direction) => Offset(-direction.dy, direction.dx);

  Offset directionAt(int i) {
    final a = points[i == 0 ? 0 : i - 1];
    final b = points[i == 0 ? 1 : i];
    final d = b - a;
    return d.distance < 1e-12 ? const Offset(1, 0) : d / d.distance;
  }

  final left = <Offset>[];
  final right = <Offset>[];

  for (var i = 0; i < points.length; i++) {
    final incoming = directionAt(i);
    final outgoing = i + 1 < points.length
        ? (points[i + 1] - points[i]) / (points[i + 1] - points[i]).distance
        : incoming;

    final nIn = leftOf(incoming);
    final nOut = leftOf(outgoing);
    var normal = nIn + nOut;
    final length = normal.distance;
    normal = length < 1e-9 ? nIn : normal / length;

    // Mitre length: 1/cos(half the turn). Capped at 3 half-widths.
    final cosHalf = normal.dx * nIn.dx + normal.dy * nIn.dy;
    final scale = cosHalf.abs() < 1e-6 ? 3.0 : (1 / cosHalf).clamp(-3.0, 3.0);

    left.add(points[i] + normal * halfWidth * scale);
    right.add(points[i] - normal * halfWidth * scale);
  }

  return normaliseWinding([...left, ...right.reversed]);
}

List<Offset> _withoutRepeats(List<Offset> points) {
  final out = <Offset>[];
  for (final point in points) {
    if (out.isEmpty || (point - out.last).distance > 1e-9) out.add(point);
  }
  return out;
}
