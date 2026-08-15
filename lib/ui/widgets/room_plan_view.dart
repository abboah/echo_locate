import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/models/room_plan.dart';
import '../../core/theme/app_colors.dart';
import '../../services/mapping/plan_viewport.dart';
import '../../services/mapping/room_geometry.dart';
import '../../services/mapping/room_graph.dart';
import 'room_plan_palette.dart';
import 'zoomable_plan.dart';

/// The wall-board schematic — floorplan spec §5.
///
/// Filled rooms, category colours, room names, a legend that writes itself.
/// Explicitly **not** CAD: no wall thickness, no door arcs. That is not a
/// shortcut, it is the target — a posted floor plan is what people actually
/// read, and matching it costs a fraction of drafting output.
///
/// One deliberate exception to "no hatching": staircases get treads. A posted
/// plan draws them too, and a floor here can hold seven — with only a fill to
/// separate them they read as small offices, on a map whose whole job is
/// telling somebody where the stairs are. Hatching stays banned as decoration;
/// this is a category that cannot be told apart without it.
///
/// Sits alongside `FloorPlanView`, which draws the same floor as landmarks and
/// corridor lines. Both exist because they answer different questions: the
/// landmark view is the schematic recovered from recorded walks and needs no
/// ARCore, this one is the room geometry when a plan has been traced or
/// captured. `RoomNavGraph` is where they meet.
///
/// Accessible by the same rule as `FloorPlanView`: a `CustomPaint` is one
/// unlabelled box to a screen reader, so every room is published as a semantics
/// node. For a blind user the voice route is the primary path — but "what is on
/// this floor" should not require sight either.
class RoomPlanView extends StatelessWidget {
  const RoomPlanView({
    super.key,
    required this.plan,
    this.route,
    this.highlightedRoomId,
    this.onRoomTap,
    this.showLegend = true,
    this.zoomable = true,
    this.editingRoomId,
    this.selectedPoint,
    this.onPointSelected,
    this.onPointMoved,
  });

  final RoomPlan plan;

  /// Drawn as a coral polyline over the rooms, with the rooms it passes
  /// through tinted. The same accent `FloorPlanView` uses for a route, because
  /// to the user it is the same thing.
  final RoomRoute? route;

  /// Where the user is, or the room they last selected.
  final String? highlightedRoomId;

  final ValueChanged<String>? onRoomTap;

  final bool showLegend;

  /// Whether the plan can be pinched into.
  ///
  /// On by default: a floor with twenty rooms on a phone screen renders each
  /// one a few millimetres across, and both reading a room's code and tapping
  /// the right one need it larger. Turned off where the plan is a thumbnail
  /// nobody is meant to work on — a gesture that zooms something decorative is
  /// a gesture that eats the scroll of the list it sits in.
  final bool zoomable;

  /// The room whose points are open for editing, if any.
  ///
  /// Editing is opt-in per room rather than a mode over the whole floor: with
  /// thirty-six rooms every corner on screen at once is a field of handles
  /// nobody can hit the right one of, and a stray drag silently reshapes a room
  /// the contributor was not looking at.
  final String? editingRoomId;

  /// Which of [editablePoints] is selected, so the controls can act on it.
  final int? selectedPoint;

  final ValueChanged<int?>? onPointSelected;

  /// Reports a handle dragged to a new position, in **plan** coordinates.
  final void Function(int index, Offset to)? onPointMoved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = RoomPalette.of(theme.brightness);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Computed here rather than inside paint() so a tap resolves against
        // exactly the projection that was drawn — the same reason
        // FloorPlanView does it, and the same bug if it does not.
        final viewport = _fit(constraints);

        // [zoom] divides every fixed pixel size below, so labels, route strokes
        // and door ticks keep their size on screen while the floor under them
        // grows. Without it a plan zoomed to read one room's code has a route
        // line as wide as a corridor drawn over it.
        Widget build(double zoom) {
          final painter = CustomPaint(
            size: Size.infinite,
            painter: _RoomPlanPainter(
              plan: plan,
              route: route,
              highlightedRoomId: highlightedRoomId,
              viewport: viewport,
              palette: palette,
              brightness: theme.brightness,
              textDirection: Directionality.of(context),
              showLegend: showLegend,
              onRoomTap: onRoomTap,
              zoom: zoom,
              editingRoomId: editingRoomId,
              editablePoints: editablePoints(),
              selectedPoint: selectedPoint,
            ),
          );

          final onTap = onRoomTap;
          final onMoved = onPointMoved;
          final editing = editingRoomId != null && onMoved != null;
          if (onTap == null && !editing) return painter;

          // Tracks which handle a drag started on. Held here rather than in
          // state so a drag survives the rebuild each move causes: looking the
          // handle up again mid-drag finds whichever one is now nearest the
          // finger, and two points close together swap under you.
          int? dragging;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              if (editing) {
                final handle = handleAt(details.localPosition, viewport);
                if (handle != null) {
                  onPointSelected?.call(handle);
                  return;
                }
              }
              // Inside the zoom, so this is still box coordinates and the
              // viewport computed above is still the one that was drawn.
              final hit = roomAt(details.localPosition, viewport);
              if (hit != null) onTap?.call(hit);
            },
            onPanStart: !editing
                ? null
                : (details) {
                    dragging = handleAt(details.localPosition, viewport);
                    if (dragging != null) onPointSelected?.call(dragging);
                  },
            onPanUpdate: !editing
                ? null
                : (details) {
                    final index = dragging;
                    if (index == null) return;
                    final to = viewport.toPlan(
                      details.localPosition.dx,
                      details.localPosition.dy,
                    );
                    onMoved(index, Offset(to.x, to.y));
                  },
            onPanEnd: !editing ? null : (_) => dragging = null,
            child: painter,
          );
        }

        return zoomable
            ? ZoomablePlan(builder: (context, zoom) => build(zoom))
            : build(1);
      },
    );
  }

  // Legend metrics, shared with the painter so the space reserved for the
  // panel and the space it actually occupies cannot drift apart.
  static const double legendPadding = 8;
  static const double legendRowHeight = 16;
  static const double legendMargin = 12;

  /// Height the legend will take, before it is drawn.
  ///
  /// Only the row count is needed, which is why this can be known without
  /// measuring any text: the panel's *width* depends on the longest category
  /// name, its height does not.
  static double legendHeightFor(List<Room> rooms) {
    final categories = RoomPalette.legendFor(rooms);
    if (categories.isEmpty) return 0;
    return legendPadding * 2 +
        legendRowsFor(categories.length) * legendRowHeight +
        legendMargin * 2;
  }

  /// Rows the legend will use for [count] categories.
  ///
  /// Two columns past five, because the panel is reserved out of the plan and a
  /// single column of eight ate a third of the canvas — the fix for the legend
  /// covering the rooms should not be the legend squashing them instead. Under
  /// six it stays one column, where a second would be mostly empty.
  static int legendRowsFor(int count) =>
      count > legendSingleColumnMax ? (count + 1) ~/ 2 : count;

  static const int legendSingleColumnMax = 5;

  PlanViewport _fit(BoxConstraints constraints) {
    // The legend is painted onto the same canvas, bottom-left, so the plan has
    // to be fitted into what is left after it. It was not, and on a floor with
    // eight categories the panel sat squarely on top of the rooms — worst
    // exactly where floors are busiest, because the number of categories grows
    // with the number of rooms.
    final reserved = showLegend
        ? legendHeightFor(plan.drawableRooms.toList())
        : 0.0;

    return PlanViewport.fitPoints(
      [
        for (final room in plan.drawableRooms)
          for (final corner in room.polygon) (x: corner.x, y: corner.y),
      ],
      width: constraints.maxWidth,
      height: (constraints.maxHeight - reserved).clamp(
        1.0,
        constraints.maxHeight,
      ),
      // In the plan's own units. A traced plan is unitless and about one
      // unit across, so the metric cap would clamp a whole floor to a few
      // pixels.
      maxScale: PlanViewport.maxScaleFor(plan.metresPerUnit),
    );
  }

  /// Plan units per metre, for the one length that is quoted in metres.
  ///
  /// [Opening.widthM] is in metres and [PlanViewport.scale] is pixels per
  /// *plan unit*, so a door has to be converted before it can be drawn. On a
  /// traced plan the two differ by about fifty, and multiplying them directly
  /// drew every door as a line straight across the screen — visible on a phone
  /// as stray full-width strokes over the plan, with nothing to say why.
  ///
  /// The nominal floor width is the same one [PlanViewport.maxScaleFor]
  /// assumes, so a door keeps its proportion to the floor whether or not
  /// anybody ever set a scale.
  static double unitsPerMetreFor(RoomPlan plan) =>
      1 / (plan.metresPerUnit ?? PlanViewport.assumedFloorMetres);

  /// The room under [point], or null when the tap missed every room.
  ///
  /// Exposed for testing: hit testing that drifts from the drawing shows up as
  /// "tapping does nothing sometimes", which is close to undebuggable in the
  /// field.
  /// The editable points of [editingRoomId] — a corridor's centreline, or any
  /// other room's corners.
  ///
  /// One list for both because to the person dragging them they are the same
  /// thing: the points this shape is made of. Which list it is decides what an
  /// edit means, and that is [PlanEditorCubit]'s business, not the canvas's.
  List<Offset> editablePoints() {
    final id = editingRoomId;
    if (id == null) return const [];
    for (final room in plan.rooms) {
      if (room.id != id) continue;
      return room.hasSpine ? room.spine : room.corners;
    }
    return const [];
  }

  /// Index of the handle under [point], or null.
  ///
  /// Hit radius is in *screen* pixels rather than plan units: a handle has to
  /// stay thumb-sized however far the plan is zoomed out, or the points on a
  /// floor viewed whole are untappable.
  int? handleAt(Offset point, PlanViewport viewport, {double radius = 22}) {
    final points = editablePoints();
    int? best;
    var bestDistance = radius;
    for (var i = 0; i < points.length; i++) {
      final at = Offset(
        viewport.toCanvasX(points[i].dx),
        viewport.toCanvasY(points[i].dy),
      );
      final d = (at - point).distance;
      if (d <= bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  String? roomAt(Offset point, PlanViewport viewport) {
    // Smallest room first, so a washroom inside a suite is reachable rather
    // than swallowed by whatever encloses it.
    final candidates = plan.drawableRooms.toList()
      ..sort((a, b) => a.areaSqM.compareTo(b.areaSqM));

    for (final room in candidates) {
      final path = _pathFor(room, viewport);
      if (path.contains(point)) return room.id;
    }
    return null;
  }

  static Path _pathFor(Room room, PlanViewport viewport) {
    final path = Path();
    final corners = room.polygon;
    if (corners.isEmpty) return path;
    path.moveTo(
      viewport.toCanvasX(corners.first.x),
      viewport.toCanvasY(corners.first.y),
    );
    for (final corner in corners.skip(1)) {
      path.lineTo(viewport.toCanvasX(corner.x), viewport.toCanvasY(corner.y));
    }
    return path..close();
  }
}

class _RoomPlanPainter extends CustomPainter {
  _RoomPlanPainter({
    required this.plan,
    required this.route,
    required this.highlightedRoomId,
    required this.viewport,
    required this.palette,
    required this.brightness,
    required this.textDirection,
    required this.showLegend,
    this.onRoomTap,
    this.zoom = 1,
    this.editingRoomId,
    this.editablePoints = const [],
    this.selectedPoint,
  });

  final String? editingRoomId;
  final List<Offset> editablePoints;
  final int? selectedPoint;

  /// How magnified the plan is — see [ZoomablePlan]. Divides every size below
  /// that is meant to be a fixed number of screen pixels.
  final double zoom;

  double _px(double pixels) => pixels / zoom;

  final RoomPlan plan;
  final RoomRoute? route;
  final String? highlightedRoomId;
  final PlanViewport viewport;
  final RoomPalette palette;
  final Brightness brightness;
  final TextDirection textDirection;
  final bool showLegend;
  final ValueChanged<String>? onRoomTap;

  bool get _dark => brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _dark ? AppColors.darkSurface : AppColors.surface,
    );

    final rooms = plan.drawableRooms.toList();
    if (rooms.isEmpty) return;

    final onRoute = route?.roomsPassed.toSet() ?? const <String>{};

    // Circulation first, then storedRooms: a corridor's outline should not cut across
    // the rooms that open off it.
    for (final room in rooms.where((r) => r.isCirculation)) {
      _paintRoom(canvas, room, onRoute);
    }
    for (final room in rooms.where((r) => !r.isCirculation)) {
      _paintRoom(canvas, room, onRoute);
    }

    _paintOpenings(canvas);
    _paintRoute(canvas);

    // Labels after every fill, so a neighbouring room's polygon can never be
    // painted over a name.
    //
    // Biggest room first, and each name claims the space it lands on. With 36
    // rooms on a phone the old unconditional pass stacked "GF4", "GF20" and
    // "Office" into one another until none of them could be read — and the
    // leader-line fallback added a third line of text to the same pile. A name
    // that cannot be placed clear of the ones already down is dropped: the
    // room is still in the semantics tree, still tappable, and still coloured
    // by category, so nothing is lost that the drawing was carrying.
    final placed = <Rect>[];
    final byPrecedence = [...rooms]
      ..sort((a, b) => _labelPriority(b).compareTo(_labelPriority(a)));
    for (final room in byPrecedence) {
      _paintLabel(canvas, room, size, placed);
    }

    _paintHandles(canvas);

    if (showLegend) _paintLegend(canvas, size, rooms);
  }

  void _paintRoom(Canvas canvas, Room room, Set<String> onRoute) {
    final path = RoomPlanView._pathFor(room, viewport);
    final fill = palette.fillFor(room.category);

    canvas.drawPath(path, Paint()..color = fill);

    if (room.id == highlightedRoomId) {
      canvas.drawPath(
        path,
        Paint()..color = AppColors.coral.withValues(alpha: 0.22),
      );
    } else if (onRoute.contains(room.id)) {
      canvas.drawPath(
        path,
        Paint()..color = AppColors.coral.withValues(alpha: 0.10),
      );
    }

    if (room.category == RoomCategory.staircase) {
      _paintTreads(canvas, room, path);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px(room.isCirculation ? 1.5 : 2)
        ..strokeJoin = StrokeJoin.round
        ..color = palette.outline,
    );
  }

  double get _unitsPerMetre => RoomPlanView.unitsPerMetreFor(plan);

  /// Doors as a gap-coloured tick across the wall. Not a swing arc — the plan
  /// does not know which way a door opens, and drawing one would be inventing
  /// detail the capture never recorded.
  void _paintOpenings(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _px(3)
      ..color = palette.corridorFill;

    final exterior = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _px(3)
      ..color = AppColors.coral;

    final rooms = {for (final room in plan.rooms) room.id: room};

    for (final opening in plan.openings) {
      final centre = Offset(
        viewport.toCanvasX(opening.at.x),
        viewport.toCanvasY(opening.at.y),
      );
      final half = (opening.widthM * _unitsPerMetre * viewport.scale) / 2;

      // Along the wall the door is in, not along the screen. This was
      // `Offset(half, 0)` for every opening on every plan: correct on a
      // horizontal wall and drawn straight *through* a vertical one, which is
      // why doors read as blobs sitting on the outline instead of gaps in it.
      //
      // The y component is negated because the wall direction is in plan space
      // and the canvas y axis points the other way — see
      // [PlanViewport.toCanvasY]. Without it every door on a sloping wall
      // mirrors, which is exactly the mistake that axis invites.
      final room = rooms[opening.roomAId];
      final wall = room == null || room.corners.length < 2
          ? const Offset(1, 0)
          : nearestEdgeDirection(room.corners, opening.at.offset);
      final along = Offset(wall.dx, -wall.dy) * half;

      canvas.drawLine(
        centre - along,
        centre + along,
        opening.isExterior ? exterior : paint,
      );
    }
  }

  /// Draggable handles on the shape being edited.
  ///
  /// Drawn last, over everything including the route, because they are the only
  /// thing on screen the finger is aimed at while editing. Sized in screen
  /// pixels via [_px] so they stay thumb-sized at any zoom — a handle that
  /// scales with the plan is untappable on a floor viewed whole, which is
  /// exactly when somebody is looking for the corridor that runs too far.
  void _paintHandles(Canvas canvas) {
    if (editingRoomId == null || editablePoints.isEmpty) return;

    final fill = Paint()..color = palette.corridorFill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(2)
      ..color = AppColors.coral;

    for (var i = 0; i < editablePoints.length; i++) {
      final at = Offset(
        viewport.toCanvasX(editablePoints[i].dx),
        viewport.toCanvasY(editablePoints[i].dy),
      );
      final selected = i == selectedPoint;
      final radius = _px(selected ? 8 : 5.5);
      canvas.drawCircle(at, radius, selected ? (Paint()..color = AppColors.coral) : fill);
      canvas.drawCircle(at, radius, edge);
    }
  }

  /// Treads across a staircase, so it is not read as a small office.
  ///
  /// A floor like the KNUST Library ground has seven of them, and with only a
  /// fill to go on they were indistinguishable from the offices between them —
  /// on a wayfinding map, where "take the stairs" is one of the few
  /// instructions that matters.
  ///
  /// Drawn across the room's short axis, which is the way treads actually run,
  /// and clipped to the polygon so they stop at the walls.
  void _paintTreads(Canvas canvas, Room room, Path path) {
    final box = _canvasBounds(room);
    if (box.isEmpty) return;

    final horizontal = box.width >= box.height;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(1)
      ..color = palette.outline.withValues(alpha: 0.45);

    canvas.save();
    canvas.clipPath(path);
    const treads = 5;
    for (var i = 1; i < treads; i++) {
      final t = i / treads;
      canvas.drawLine(
        horizontal
            ? Offset(box.left + box.width * t, box.top)
            : Offset(box.left, box.top + box.height * t),
        horizontal
            ? Offset(box.left + box.width * t, box.bottom)
            : Offset(box.right, box.top + box.height * t),
        paint,
      );
    }
    canvas.restore();
  }

  void _paintRoute(Canvas canvas) {
    final drawn = route?.drawnLine ?? const <Offset>[];
    if (drawn.length < 2) return;

    final path = Path()
      ..moveTo(
        viewport.toCanvasX(drawn.first.dx),
        viewport.toCanvasY(drawn.first.dy),
      );
    for (final point in drawn.skip(1)) {
      path.lineTo(viewport.toCanvasX(point.dx), viewport.toCanvasY(point.dy));
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px(3.5)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.coral,
    );

    final end = drawn.last;
    canvas.drawCircle(
      Offset(viewport.toCanvasX(end.dx), viewport.toCanvasY(end.dy)),
      _px(5),
      Paint()..color = AppColors.coral,
    );
  }

  /// The overflow ladder: full label → code only → smaller → smaller → leader
  /// line to a label outside the room.
  ///
  /// A 1.2 × 2.4 m washroom cannot hold "WC Ground Floor West" at any size.
  /// Without the ladder every small room on the plan looks broken, which is
  /// most of them on a real floor.
  /// Which names get the space when they compete for it.
  ///
  /// A room somebody named beats one showing only its category: "GF14" is a
  /// destination a person can be sent to, "Office" is one of eleven. Corridors
  /// come next — they are what the directions are phrased around — and area
  /// breaks the remaining ties, because a big room has the room for its name
  /// and a broom cupboard does not.
  static double _labelPriority(Room room) {
    final area = room.bounds.width * room.bounds.height;
    if (room.isNamed) return 1000 + area;
    if (room.isCirculation) return 500 + area;
    return area;
  }

  void _paintLabel(Canvas canvas, Room room, Size size, List<Rect> placed) {
    final box = _canvasBounds(room);
    final centre = Offset(
      viewport.toCanvasX(room.centre.dx),
      viewport.toCanvasY(room.centre.dy),
    );
    final ink = palette.labelOn(palette.fillFor(room.category));

    for (final attempt in _labelAttempts(room)) {
      final painter = _textPainter(attempt.text, attempt.size, ink);
      if (painter.width > box.width * 0.9 ||
          painter.height > box.height * 0.9) {
        continue;
      }
      final origin = centre - Offset(painter.width / 2, painter.height / 2);
      // A little breathing room, or two names that merely touch still read as
      // one word.
      final rect = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        painter.width,
        painter.height,
      ).inflate(2);
      if (placed.any(rect.overlaps)) continue;

      painter.paint(canvas, origin);
      placed.add(rect);
      return;
    }

    _paintLeaderLine(canvas, room, centre, size, placed);
  }

  /// Progressively smaller ways to fit a room's name inside its outline.
  ///
  /// Every attempt is the same text now. It used to lead with the allocated
  /// code and hang the name under it, but the code is an opaque id — drawing
  /// it would put a meaningless token in the middle of every room.
  Iterable<({String text, double size})> _labelAttempts(Room room) sync* {
    yield (text: room.displayName, size: 12);
    yield (text: room.displayName, size: 10);
    yield (text: room.displayName, size: 8);
  }

  /// Last resort: the name sits just outside the room with a hairline back to
  /// it. Better a label you can follow than one clipped to three characters.
  void _paintLeaderLine(
    Canvas canvas,
    Room room,
    Offset centre,
    Size size,
    List<Rect> placed,
  ) {
    // Only worth the ink for a room somebody named. A leader line saying
    // "Staircase" beside a hatched staircase spends a line and a word to
    // repeat what the drawing already says, and on this floor there are seven
    // of them pointing into the same corridor.
    if (!room.isNamed) return;

    final box = _canvasBounds(room);
    final painter = _textPainter(
      room.displayName,
      9,
      _dark ? AppColors.darkMuted : AppColors.inkMuted,
    );

    // Out to the right unless that runs off the canvas, in which case left.
    final toRight = box.right + 6 + painter.width < size.width;
    final anchor = toRight
        ? Offset(box.right + 6, centre.dy - painter.height / 2)
        : Offset(box.left - 6 - painter.width, centre.dy - painter.height / 2);

    // Same rule as an inside label: if the space is taken, the name is dropped
    // rather than piled on top of one already there.
    final rect = Rect.fromLTWH(
      anchor.dx,
      anchor.dy,
      painter.width,
      painter.height,
    ).inflate(2);
    if (placed.any(rect.overlaps)) return;
    placed.add(rect);

    canvas.drawLine(
      centre,
      Offset(toRight ? box.right + 4 : box.left - 4, centre.dy),
      Paint()
        ..strokeWidth = _px(1)
        ..color = (_dark ? AppColors.darkMuted : AppColors.inkMuted).withValues(
          alpha: 0.7,
        ),
    );
    painter.paint(canvas, anchor);
  }

  void _paintLegend(Canvas canvas, Size size, List<Room> rooms) {
    final categories = RoomPalette.legendFor(rooms);
    if (categories.isEmpty) return;

    const swatch = 10.0;
    const gap = 6.0;
    // Shared with the space `_fit` sets aside — see [RoomPlanView.legendHeightFor].
    const rowHeight = RoomPlanView.legendRowHeight;
    const padding = RoomPlanView.legendPadding;

    final entries = [
      for (final category in categories)
        (
          category: category,
          painter: _textPainter(
            RoomPalette.labelFor(category),
            10,
            _dark ? AppColors.darkOnSurface : AppColors.ink,
          ),
        ),
    ];

    final columns =
        entries.length > RoomPlanView.legendSingleColumnMax ? 2 : 1;
    final rows = RoomPlanView.legendRowsFor(entries.length);
    const columnGap = 14.0;
    final columnWidth =
        swatch +
        gap +
        entries.map((e) => e.painter.width).reduce((a, b) => a > b ? a : b);
    final width =
        padding * 2 + columns * columnWidth + (columns - 1) * columnGap;
    final height = padding * 2 + rows * rowHeight;

    // Bottom-left, where a wall board puts it, and clamped so a floor with
    // fourteen categories does not run off the top.
    final top = (size.height - height - 12).clamp(0.0, size.height);
    final panel = Rect.fromLTWH(12, top, width, height);

    canvas.drawRRect(
      RRect.fromRectAndRadius(panel, const Radius.circular(8)),
      Paint()
        ..color = (_dark ? AppColors.darkElevated : AppColors.white).withValues(
          alpha: 0.94,
        ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(panel, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px(1)
        ..color = _dark ? AppColors.darkHairline : AppColors.hairline,
    );

    for (var i = 0; i < entries.length; i++) {
      final column = i ~/ rows;
      final rowTop = panel.top + padding + (i % rows) * rowHeight;
      final left = panel.left + padding + column * (columnWidth + columnGap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, rowTop + 2, swatch, swatch),
          const Radius.circular(2),
        ),
        Paint()..color = palette.fillFor(entries[i].category),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, rowTop + 2, swatch, swatch),
          const Radius.circular(2),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _px(0.75)
          ..color = palette.outline.withValues(alpha: 0.5),
      );
      // Off `left`, which already carries the column. Computing this from
      // `panel.left` instead put both columns' text at the first column's x and
      // printed the two names on top of each other.
      entries[i].painter.paint(canvas, Offset(left + swatch + gap, rowTop));
    }
  }

  Rect _canvasBounds(Room room) {
    final box = room.bounds;
    return Rect.fromLTRB(
      viewport.toCanvasX(box.left),
      viewport.toCanvasY(box.bottom),
      viewport.toCanvasX(box.right),
      viewport.toCanvasY(box.top),
    );
  }

  /// Laid-out labels, kept between paints.
  ///
  /// Laying out text is the expensive part of drawing this plan: thirty-six
  /// rooms, up to three size attempts each, is over a hundred layouts per
  /// frame — and dragging a corner repaints every frame. The result depends
  /// only on the text, size, colour and direction, none of which change while a
  /// point is being dragged, so it is computed once and reused.
  ///
  /// Static because the painter itself is rebuilt on every repaint. Bounded so
  /// a long editing session cannot grow it without limit; the cap is far above
  /// the ~150 entries a busy floor needs, and clearing wholesale costs one
  /// frame's layouts rather than tracking usage.
  static final Map<({String text, double size, int colour, TextDirection dir}),
      TextPainter> _labelCache = {};

  static const int _labelCacheLimit = 600;

  TextPainter _textPainter(String text, double size, Color colour) {
    final key = (
      text: text,
      size: _px(size),
      colour: colour.toARGB32(),
      dir: textDirection,
    );
    final hit = _labelCache[key];
    if (hit != null) return hit;

    if (_labelCache.length >= _labelCacheLimit) _labelCache.clear();

    return _labelCache[key] = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: _px(size),
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: colour,
        ),
      ),
      textDirection: textDirection,
      textAlign: TextAlign.center,
    )..layout();
  }

  /// Publishes every room as a semantics node, naming it, its category and its
  /// role in the current route.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final onRoute = route?.roomsPassed.toSet() ?? const <String>{};
    final tappable = onRoomTap != null;

    return [
      for (final room in plan.drawableRooms)
        CustomPainterSemantics(
          rect: _canvasBounds(room),
          properties: SemanticsProperties(
            label: _describe(room, onRoute),
            textDirection: textDirection,
            button: tappable,
            enabled: tappable,
            onTap: tappable ? () => onRoomTap!(room.id) : null,
          ),
        ),
    ];
  };

  String _describe(Room room, Set<String> onRoute) {
    final role = switch (room.id) {
      final id when id == highlightedRoomId => 'you are here',
      final id when id == route?.roomsPassed.lastOrNull => 'your destination',
      final id when onRoute.contains(id) => 'on your route',
      _ => null,
    };

    return [
      room.displayName,
      // Not repeated when the room is unnamed: "Office, office" reads as a
      // stutter to anybody on TalkBack, which is who this string is for.
      if (room.isNamed) RoomPalette.labelFor(room.category).toLowerCase(),
      if (role != null) role,
    ].join(', ');
  }

  @override
  bool shouldRepaint(covariant _RoomPlanPainter old) =>
      // Value equality throughout: RoomPlan and RoomRoute are freezed/immutable,
      // so an edit produces a new instance rather than mutating this one. The
      // spec's version compares mutable objects by identity, which means
      // dragging a wing in the editor never repaints.
      old.plan != plan ||
      old.route != route ||
      old.highlightedRoomId != highlightedRoomId ||
      old.viewport != viewport ||
      old.brightness != brightness ||
      old.textDirection != textDirection ||
      old.showLegend != showLegend ||
      old.zoom != zoom ||
      // Selecting a handle changes nothing but the handles, so without these
      // the tap would land, the cubit would update, and the point would not
      // look any different.
      old.editingRoomId != editingRoomId ||
      old.selectedPoint != selectedPoint;

  @override
  bool shouldRebuildSemantics(covariant _RoomPlanPainter old) =>
      old.plan != plan ||
      old.route != route ||
      old.highlightedRoomId != highlightedRoomId ||
      old.viewport != viewport;
}
