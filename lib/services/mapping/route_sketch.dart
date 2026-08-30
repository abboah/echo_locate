// The route as a shape you can look at — the map under the instruction.
//
// Guidance speaks one leg at a time, which is the right way to *walk* a route
// and a poor way to understand one. A sighted user handed "turn right at the
// help desk" has no idea whether they are a third of the way there or nearly
// arrived, whether the route doubles back, or how many corners are left. Every
// map app answers that with a line between two points, and this is the geometry
// behind ours.
//
// ## Two sources, because a route does not always know where it is
//
// **The real line, where there is one.** `GuidanceSession.routePath` is the
// route as metres on the floor, the same geometry the AR layer registers into
// ARCore's world. Drawn, it is the corridors of the building.
//
// **A turtle, where there is not.** A route with no scale still knows its turns
// and its relative lengths, which is a turtle program — the same one
// `route_layout` runs over a recorded walk. Running it gives a shape that is
// schematic rather than surveyed: the corners are where the corners are, and
// the proportions hold, but a corridor recorded as a right angle is drawn as
// one whether or not the building agrees.
//
// The second is deliberately not held to the standard of the first. A schematic
// of the way ahead is the thing a paper sign by a lift is, and nobody has ever
// been misled by one — whereas refusing to draw anything until somebody
// measures a floor plan would leave the commonest case in this app with a blank
// panel where the map should be.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../features/guidance/guidance_session.dart';
import 'route_planner.dart';

/// A route laid out as a line, with the landmarks marked along it.
class RouteSketch {
  const RouteSketch({
    required this.points,
    required this.legEnds,
    required this.surveyed,
  });

  /// Every vertex of the line, in the frame it was laid out in.
  ///
  /// The unit is deliberately not named. When [surveyed] these are metres on
  /// the plan; when not they are whatever the route's own lengths were in. A
  /// drawing is scaled to fit either way, and nothing here is ever quoted to
  /// the user as a distance — [RouteSketch] draws, it does not speak.
  final List<Offset> points;

  /// How far along the line each leg of the spoken route ends.
  ///
  /// One entry per leg, in order, so the dot for "the help desk" lands where
  /// guidance thinks the help desk is rather than at an arbitrary vertex.
  final List<double> legEnds;

  /// Whether this came from measured geometry rather than from the turtle.
  ///
  /// The screen says so. A schematic that admits it is a schematic is a map;
  /// one that does not is a claim about a building.
  final bool surveyed;

  double get totalLength => legEnds.isEmpty ? 0 : legEnds.last;

  /// Where the line starts, so a caller can mark it without reaching into
  /// [points] and rediscovering that it may be empty.
  Offset? get start => points.isEmpty ? null : points.first;

  Offset? get destination => points.isEmpty ? null : points.last;

  /// Whether there is enough of a line here to be worth drawing.
  bool get isDrawable => points.length >= 2 && totalLength > 0;

  /// The point [along] the line, clamped to its ends.
  Offset pointAt(double along) {
    if (points.isEmpty) return Offset.zero;
    if (along <= 0) return points.first;

    var remaining = along;
    for (var i = 0; i + 1 < points.length; i++) {
      final span = (points[i + 1] - points[i]).distance;
      if (span < 1e-9) continue;
      if (remaining <= span) {
        return points[i] + (points[i + 1] - points[i]) * (remaining / span);
      }
      remaining -= span;
    }
    return points.last;
  }

  /// The line from its start up to [along], for drawing the walked part in a
  /// different colour from the part still ahead.
  ///
  /// Includes the interpolated point at the end, so the walked line stops
  /// exactly under the walker's dot rather than at the last vertex behind them.
  List<Offset> upTo(double along) {
    if (points.isEmpty || along <= 0) return const [];

    final walked = <Offset>[points.first];
    var remaining = along;
    for (var i = 0; i + 1 < points.length; i++) {
      final span = (points[i + 1] - points[i]).distance;
      if (span < 1e-9) continue;
      if (remaining <= span) {
        walked.add(points[i] + (points[i + 1] - points[i]) * (remaining / span));
        return walked;
      }
      remaining -= span;
      walked.add(points[i + 1]);
    }
    return walked;
  }

  /// Lays [session]'s route out, measured where it can be and schematic where
  /// it cannot.
  ///
  /// Returns null only for a route with nothing in it — no legs at all — which
  /// is a session that should not have been started.
  static RouteSketch? of(GuidanceSession session) {
    final path = session.routePath;
    if (path != null && path.pointsM.length >= 2 && path.legEndsM.isNotEmpty) {
      return RouteSketch(
        points: path.pointsM,
        legEnds: path.legEndsM,
        surveyed: true,
      );
    }
    return fromTurns(session.plan);
  }

  /// The turtle: turns and lengths in, a shape out.
  ///
  /// Heading 0 is +y — "up" on the drawing, the direction the walker is facing
  /// when they set off — and a positive `turnDeg` is a turn to the right toward
  /// +x. The same convention `route_layout`, `route_registration` and
  /// `ArGuidanceHandler`'s trail all use, so a right angle means the same thing
  /// in all four and a drawing can be checked against an arrow.
  static RouteSketch? fromTurns(PlannedRoute route) {
    if (route.legs.isEmpty) return null;

    var x = 0.0;
    var y = 0.0;
    var headingDeg = 0.0;
    var along = 0.0;

    final points = <Offset>[Offset(x, y)];
    final legEnds = <double>[];

    for (final leg in route.legs) {
      headingDeg += leg.turnDeg;
      final headingRad = headingDeg * math.pi / 180;

      // A leg of no length still gets a vertex, so the leg count and the
      // landmark dots stay in step with the spoken route — a zero-length leg is
      // a stairwell landing placed above its stairwell, not a missing leg.
      final length = leg.distanceM.abs();
      x += length * math.sin(headingRad);
      y += length * math.cos(headingRad);
      along += length;

      points.add(Offset(x, y));
      legEnds.add(along);
    }

    return RouteSketch(points: points, legEnds: legEnds, surveyed: false);
  }

  /// How far along the line the walker has got, from the walk's own clock.
  ///
  /// ## Why this is a fraction of a leg rather than a distance
  ///
  /// The two numbers involved are not always in the same unit. `walkedM` is
  /// always real metres — ARCore measures the corridor, or a stride length
  /// converts the steps — while the line is in metres only when [surveyed]. On
  /// a traced plan nobody measured, adding one to the other would place the
  /// walker by treating fractions of a photograph as metres, which on a small
  /// plan puts them past the destination within a few steps.
  ///
  /// Taking the *fraction of the current leg* sidesteps it: both numbers
  /// describe the same leg, so the ratio is unitless and correct in either
  /// case. [legMetres] is what guidance believes this leg's real length to be,
  /// and is zero when it has no idea — in which case the walker sits at the
  /// start of the leg rather than somewhere invented.
  double progressAlong({
    required int legIndex,
    required double walkedM,
    required double legMetres,
  }) {
    if (legEnds.isEmpty) return 0;
    final index = legIndex.clamp(0, legEnds.length - 1);
    final legStart = index == 0 ? 0.0 : legEnds[index - 1];
    final legLength = legEnds[index] - legStart;
    if (legLength <= 0 || legMetres <= 0) return legStart;

    final fraction = (walkedM / legMetres).clamp(0.0, 1.0);
    return legStart + legLength * fraction;
  }
}
