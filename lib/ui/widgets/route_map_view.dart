import 'package:flutter/material.dart';

import '../../core/models/room_plan.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../services/mapping/plan_viewport.dart';
import '../../services/mapping/route_sketch.dart';
import 'room_plan_palette.dart';

/// The whole route, drawn as a line between two points, with the walker on it.
///
/// ## What it is for
///
/// Guidance speaks one leg at a time. That is the right way to walk a route and
/// a poor way to understand one: told "turn right at the help desk", a sighted
/// user cannot tell whether they are a third of the way there, whether the
/// route doubles back on itself, or how many corners are left. This is the
/// answer every map app gives to that question, and the reason it belongs under
/// the instruction rather than replacing it — the instruction is what to do
/// next, and this is where that sits in the whole walk.
///
/// ## Who it is for, which is not everybody
///
/// A blind user is served by the voice, which says more than this can and says
/// it in the right order. This is for the sighted user, the low-vision user who
/// can make out a bold line, and the helper looking over a shoulder. It is
/// still not left silent: the whole thing carries one semantics label saying
/// where the walker is in the route, so a screen reader user gets the summary
/// without having to interpret a picture.
///
/// ## What it will not do
///
/// Claim to be a survey. Where the geometry is measured — a scaled plan — the
/// line is the corridors of the building. Where it is not, the line is a
/// turtle's idea of them (see [RouteSketch]) and the caption says as much,
/// because a schematic that admits it is a schematic is a map and one that does
/// not is a claim.
class RouteMapView extends StatelessWidget {
  const RouteMapView({
    super.key,
    required this.sketch,
    required this.along,
    this.legIndex = 0,
    this.height = 148,
    this.destinationName,
    this.plan,
  });

  final RouteSketch sketch;

  /// The floor to draw behind the route, when there is one.
  ///
  /// Only ever used with a [RouteSketch.surveyed] sketch, and the check is in
  /// the painter rather than left to callers. A turtle sketch is a shape built
  /// out of turns and lengths, not a path through plan coordinates: laying the
  /// building behind it would put the walker's line through walls it never
  /// crosses and claim a correspondence that does not exist.
  final RoomPlan? plan;

  /// How far along the line the walker is — [RouteSketch.progressAlong].
  final double along;

  /// Which leg is being walked, so the landmarks behind the walker can be
  /// drawn as reached rather than as still to come.
  final int legIndex;

  final double height;

  /// Named in the semantics summary, so the screen reader says where this route
  /// goes rather than "route map".
  final String? destinationName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if (!sketch.isDrawable) return const SizedBox.shrink();

    final legs = sketch.legEnds.length;
    final reached = legIndex.clamp(0, legs);
    final percent = sketch.totalLength <= 0
        ? 0
        : ((along / sketch.totalLength) * 100).clamp(0, 100).round();

    return Semantics(
      // One label for the whole picture. A screen reader reading out a
      // decorative line vertex by vertex would be noise; what a user actually
      // wants from a map at a glance is how far through they are.
      label: destinationName == null
          ? 'Route map. About $percent per cent of the way, '
                'landmark ${reached + 1} of ${legs + 1}.'
          : 'Route map to $destinationName. About $percent per cent of the '
                'way, landmark ${reached + 1} of ${legs + 1}.',
      excludeSemantics: true,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: dark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          border: Border.all(
            color: dark ? AppColors.darkHairline : AppColors.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _RouteMapPainter(
            sketch: sketch,
            along: along,
            legIndex: reached,
            dark: dark,
            plan: sketch.surveyed ? plan : null,
            palette: RoomPalette.of(theme.brightness),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RouteMapPainter extends CustomPainter {
  _RouteMapPainter({
    required this.sketch,
    required this.along,
    required this.legIndex,
    required this.dark,
    required this.palette,
    this.plan,
  });

  final RouteSketch sketch;
  final double along;
  final int legIndex;
  final bool dark;
  final RoomPalette palette;
  final RoomPlan? plan;

  /// Room for the end markers and the walker's halo, which are drawn *on* the
  /// extreme points of the line and would otherwise be clipped in half by the
  /// edge of the card.
  static const double _padding = 22;

  /// How much floor to show either side of the route, in metres.
  ///
  /// The card is framed on the **route**, not on the floor: a whole storey
  /// squeezed into a strip this size is a grey smudge with a coral thread
  /// through it, and the thing a walker wants to recognise is the corridor they
  /// are in and the rooms opening off it. Enough for the rooms on both sides
  /// and the ones just past each end, and no more.
  static const double _surroundM = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final points = sketch.points;
    if (points.length < 2) return;

    final floor = plan;
    final unit = floor?.metresPerUnit ?? 1;

    // The same fitter the floor plan screen uses, so a route drawn here and the
    // same route drawn there are the same shape rather than two independent
    // guesses at how to fit a line into a box.
    //
    // Framed on the route plus [_surroundM] of floor around it. No zoom cap
    // worth the name: this box shows one corridor, so filling it is always
    // right, and `maxScale` is set past anything a phone can reach rather than
    // left at a value that would letterbox a short route into an empty card.
    final frame = <({double x, double y})>[
      for (final point in points) (x: point.dx, y: point.dy),
      if (floor != null) ...[
        for (final point in points) ...[
          (x: point.dx - _surroundM, y: point.dy - _surroundM),
          (x: point.dx + _surroundM, y: point.dy + _surroundM),
        ],
      ],
    ];

    final viewport = PlanViewport.fitPoints(
      frame,
      width: size.width,
      height: size.height,
      padding: _padding,
      maxScale: 1e6,
    );

    Offset toCanvas(Offset plan) =>
        Offset(viewport.toCanvasX(plan.dx), viewport.toCanvasY(plan.dy));

    if (floor != null) _drawFloor(canvas, floor, unit, toCanvas);

    // A casing under the line, in the card's own colour and wider than it.
    //
    // The route used to be drawn on an empty card, where a pale grey read
    // fine. It now crosses room fills of every hue the palette has, and a line
    // has to stay legible over all of them — including the near-white a
    // corridor gets and the mustard of a lecture hall. Every map app solves
    // this the same way, and it is why a route on a paper map has a halo.
    final casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = (dark ? AppColors.darkBackground : AppColors.white)
          .withValues(alpha: 0.85);

    final ahead = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = dark ? AppColors.darkMuted : AppColors.inkMuted;

    final walked = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.coral;

    // The whole route first, in the colour of the part not yet walked, then the
    // walked part over it. Drawn in that order so the join between them is a
    // clean overlap rather than two lines meeting at a seam that shifts as the
    // walker moves.
    final whole = _pathThrough(points, toCanvas);
    canvas.drawPath(whole, casing);
    canvas.drawPath(whole, ahead);

    final behind = sketch.upTo(along);
    if (behind.length >= 2) {
      canvas.drawPath(_pathThrough(behind, toCanvas), walked);
    }

    _drawLandmarks(canvas, toCanvas);
    _drawEnds(canvas, toCanvas);
    _drawWalker(canvas, toCanvas(sketch.pointAt(along)));
  }

  /// The floor behind the route: rooms filled by category, walls on top.
  ///
  /// Deliberately less than the floor plan screen draws. No room names, no door
  /// ticks, no legend, no stair treads — at this size every one of those is a
  /// smudge that costs contrast against the one line that matters. What
  /// survives is what makes a corridor recognisable at a glance: the shape of
  /// the space, and which side the rooms are on.
  ///
  /// Room coordinates are plan units and the route is in metres, so the floor
  /// is scaled by [unit] to bring the two into the same frame. Getting this
  /// wrong does not look wrong — it looks like a route through a building fifty
  /// times too big, with the line running off into blank floor.
  void _drawFloor(
    Canvas canvas,
    RoomPlan floor,
    double unit,
    Offset Function(Offset) toCanvas,
  ) {
    final rooms = floor.drawableRooms.toList();
    if (rooms.isEmpty) return;

    final wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round
      ..color = palette.outline.withValues(alpha: 0.55);

    // Circulation first, so a corridor's wall does not cut across the rooms
    // opening off it — the same order the full plan painter uses.
    for (final room in rooms.where((r) => r.isCirculation)) {
      _drawRoom(canvas, room, unit, toCanvas, wall);
    }
    for (final room in rooms.where((r) => !r.isCirculation)) {
      _drawRoom(canvas, room, unit, toCanvas, wall);
    }
  }

  void _drawRoom(
    Canvas canvas,
    Room room,
    double unit,
    Offset Function(Offset) toCanvas,
    Paint wall,
  ) {
    if (room.polygon.length < 3) return;

    final path = Path();
    for (var i = 0; i < room.polygon.length; i++) {
      final corner = room.polygon[i];
      final at = toCanvas(Offset(corner.x * unit, corner.y * unit));
      if (i == 0) {
        path.moveTo(at.dx, at.dy);
      } else {
        path.lineTo(at.dx, at.dy);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = palette.fillFor(room.category));
    canvas.drawPath(path, wall);
  }

  Path _pathThrough(List<Offset> plan, Offset Function(Offset) toCanvas) {
    final path = Path()..moveTo(toCanvas(plan.first).dx, toCanvas(plan.first).dy);
    for (var i = 1; i < plan.length; i++) {
      final point = toCanvas(plan[i]);
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }

  /// A dot at every landmark the route passes through.
  ///
  /// Filled where the walker has been, hollow where they have not — the same
  /// distinction the line makes, repeated at the points that are places rather
  /// than geometry, because those are the ones somebody can look for.
  void _drawLandmarks(Canvas canvas, Offset Function(Offset) toCanvas) {
    final surface = dark ? AppColors.darkSurface : AppColors.surface;

    // The last leg end is the destination, which gets its own marker.
    for (var i = 0; i + 1 < sketch.legEnds.length; i++) {
      final at = toCanvas(sketch.pointAt(sketch.legEnds[i]));
      final passed = i < legIndex;

      canvas.drawCircle(at, 5, Paint()..color = surface);
      canvas.drawCircle(
        at,
        4,
        Paint()
          ..style = passed ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = passed
              ? AppColors.coral
              : (dark ? AppColors.darkMuted : AppColors.inkMuted),
      );
    }
  }

  /// Where the walk began and where it ends.
  void _drawEnds(Canvas canvas, Offset Function(Offset) toCanvas) {
    final ink = dark ? AppColors.darkOnSurface : AppColors.ink;
    final surface = dark ? AppColors.darkSurface : AppColors.surface;

    final start = sketch.start;
    if (start != null) {
      canvas.drawCircle(
        toCanvas(start),
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = dark ? AppColors.darkMuted : AppColors.inkMuted,
      );
    }

    final end = sketch.destination;
    if (end == null) return;
    final at = toCanvas(end);
    // A ring around the destination so it reads as the place the line is going
    // to rather than as one more landmark on the way.
    canvas.drawCircle(at, 9, Paint()..color = surface);
    canvas.drawCircle(
      at,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink,
    );
    canvas.drawCircle(at, 4, Paint()..color = ink);
  }

  /// The walker: a coral dot inside a ring of the card's own colour.
  ///
  /// The ring is what keeps it visible where it matters most — sitting on top
  /// of the coral line it has just walked along, which is exactly where it
  /// spends the whole route.
  void _drawWalker(Canvas canvas, Offset at) {
    canvas.drawCircle(
      at,
      8,
      Paint()..color = dark ? AppColors.darkSurface : AppColors.surface,
    );
    canvas.drawCircle(at, 6, Paint()..color = AppColors.coral);
    canvas.drawCircle(
      at,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = dark ? AppColors.darkSurface : AppColors.white,
    );
  }

  @override
  bool shouldRepaint(_RouteMapPainter old) =>
      old.along != along ||
      old.legIndex != legIndex ||
      old.dark != dark ||
      !identical(old.sketch, sketch) ||
      !identical(old.plan, plan);
}
