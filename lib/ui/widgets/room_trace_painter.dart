import 'package:flutter/material.dart';

import '../../core/models/room_plan.dart';
import '../../core/theme/app_colors.dart';
import '../../features/room_trace/bloc/room_trace_bloc.dart';
import '../../services/mapping/board_rectification.dart';
import '../../services/mapping/room_geometry.dart';
import 'room_plan_palette.dart';

/// Draws traced rooms over the photographed wall board.
///
/// Coordinate space is the **box**, not the image inside it: both axes are
/// fractions of the box's *width*, which is the space taps are converted into.
/// Anchoring both to the width is what keeps a traced square square when the
/// box is not — the same rule `PlanTracePainter` follows, and for the same
/// reason.
///
/// Sits between the raw photo and `RoomPlanView`: this one draws *while*
/// tracing, over the picture, in the picture's own coordinates; that one draws
/// the finished plan as a schematic in plan coordinates. Two painters rather
/// than one because they answer different questions — "does this match the
/// board?" and "is this a map?".
class RoomTracePainter extends CustomPainter {
  const RoomTracePainter({
    required this.plan,
    required this.draft,
    required this.rectification,
    this.boardCorners = const [],
    this.scalePoints = const [],
    required this.selectedRoomId,
    required this.mode,
    required this.onDark,
    this.zoom = 1,
  });

  /// How magnified the plan currently is — see [ZoomablePlan].
  ///
  /// Everything drawn at a fixed pixel size is divided by this so it stays the
  /// same size on screen while the plan under it grows. Without it a corner
  /// marker at 8× is a coral disc wide enough to cover several rooms, so
  /// zooming in to place a corner precisely hides the corner being placed —
  /// which is the opposite of what the zoom is for.
  final double zoom;

  /// A pixel size that should not grow with the plan.
  double _px(double pixels) => pixels / zoom;

  final RoomPlan plan;

  /// Corners of the room being traced, in plan space.
  final List<Offset> draft;

  /// The board's perspective correction, so what is drawn lands back on the
  /// walls it was traced from.
  final Homography rectification;

  /// Board corners tapped so far, in photo coordinates — drawn while squaring
  /// the picture up.
  final List<Offset> boardCorners;

  /// The span being measured, in plan space.
  final List<Offset> scalePoints;

  final String? selectedRoomId;
  final RoomTraceMode mode;

  /// Whether the backdrop is dark, so the halo can stay visible on it.
  ///
  /// A plan behind glass photographs dark far more often than not, and a coral
  /// line on a dark photograph without a halo disappears into it.
  final bool onDark;

  static const double cornerRadius = 7;

  /// Plan space back to the box.
  ///
  /// Undoes both corrections the bloc applied on the way in — the y flip and,
  /// when the board has been squared up, the perspective. Without the second a
  /// traced room would be drawn as the *corrected* rectangle sitting on an
  /// uncorrected photo, so it would no longer line up with the walls it was
  /// traced from.
  Offset _at(Offset planPoint, Size size) {
    final image = RoomTraceBloc.toImage(planPoint, rectification);
    return Offset(image.dx * size.width, image.dy * size.width);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final halo = onDark ? AppColors.ink : AppColors.white;
    final palette = onDark ? RoomPalette.dark : RoomPalette.light;

    for (final room in plan.drawableRooms) {
      _paintRoom(canvas, size, room, palette, halo);
    }
    _paintSpines(canvas, size);
    _paintOpenings(canvas, size, halo);
    if (mode == RoomTraceMode.corridor) {
      _paintCorridorDraft(canvas, size, halo);
    } else {
      _paintDraft(canvas, size, halo);
    }
    _paintBoardOutline(canvas, size, halo);
    _paintScaleSpan(canvas, size, halo);
  }

  /// The board's corners as they are tapped, in photo coordinates.
  ///
  /// Drawn without going through [_at]: these are being used to *build* the
  /// correction, so they cannot be mapped through it.
  void _paintBoardOutline(Canvas canvas, Size size, Color halo) {
    if (boardCorners.isEmpty) return;

    final points = [
      for (final corner in boardCorners)
        Offset(corner.dx * size.width, corner.dy * size.width),
    ];

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(2.5)
      ..color = AppColors.warning;

    for (var i = 0; i + 1 < points.length; i++) {
      canvas.drawLine(points[i], points[i + 1], line);
    }
    if (points.length == 4) {
      canvas.drawLine(points.last, points.first, line);
    }

    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], _px(9), Paint()..color = halo);
      canvas.drawCircle(points[i], _px(6), Paint()..color = AppColors.warning);
      // Numbered, because the order is what makes the quad sane and getting it
      // wrong is the common mis-tap.
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: halo,
            fontSize: _px(9),
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        points[i] - Offset(label.width / 2, label.height / 2),
      );
    }
  }

  /// The span whose real length is about to be given.
  void _paintScaleSpan(Canvas canvas, Size size, Color halo) {
    if (scalePoints.isEmpty) return;
    final points = [for (final point in scalePoints) _at(point, size)];

    if (points.length == 2) {
      canvas.drawLine(
        points.first,
        points.last,
        Paint()
          ..strokeWidth = _px(6)
          ..strokeCap = StrokeCap.round
          ..color = halo.withValues(alpha: 0.85),
      );
      canvas.drawLine(
        points.first,
        points.last,
        Paint()
          ..strokeWidth = _px(3)
          ..strokeCap = StrokeCap.round
          ..color = AppColors.success,
      );
    }

    for (final point in points) {
      canvas.drawCircle(point, _px(9), Paint()..color = halo);
      canvas.drawCircle(point, _px(6), Paint()..color = AppColors.success);
    }
  }

  void _paintRoom(
    Canvas canvas,
    Size size,
    Room room,
    RoomPalette palette,
    Color halo,
  ) {
    final path = Path();
    final corners = room.corners;
    path.moveTo(_at(corners.first, size).dx, _at(corners.first, size).dy);
    for (final corner in corners.skip(1)) {
      final at = _at(corner, size);
      path.lineTo(at.dx, at.dy);
    }
    path.close();

    final selected = room.id == selectedRoomId;

    // Translucent, always: the contributor is checking the trace against the
    // photograph underneath it, and an opaque fill hides the thing being
    // traced.
    canvas.drawPath(
      path,
      Paint()
        ..color = palette
            .fillFor(room.category)
            .withValues(alpha: selected ? 0.55 : 0.35),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px(selected ? 5 : 4)
        ..color = halo.withValues(alpha: 0.8),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px(selected ? 3 : 2)
        ..strokeJoin = StrokeJoin.round
        ..color = selected ? AppColors.coral : palette.outline,
    );
  }

  /// The line down the middle of each corridor drawn as a path.
  ///
  /// Worth showing, quietly: it is the thing routing follows, so a contributor
  /// checking their work against the board should be able to see whether it
  /// runs down the hallway or through a wall. Drawn thin and dashed so it reads
  /// as an annotation on the corridor rather than another wall.
  void _paintSpines(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(1.5)
      ..strokeCap = StrokeCap.round
      ..color = AppColors.coral.withValues(alpha: 0.75);

    for (final room in plan.drawableRooms) {
      if (!room.hasSpine) continue;
      final points = [for (final point in room.spine) _at(point, size)];
      for (var i = 0; i + 1 < points.length; i++) {
        _dash(canvas, points[i], points[i + 1], [line]);
      }
    }
  }

  /// The hallway being drawn: the tapped line, and the width it will become.
  void _paintCorridorDraft(Canvas canvas, Size size, Color halo) {
    if (draft.isEmpty) return;

    // The generated outline, shown before it is committed — the width is the
    // one thing about a path corridor the contributor does not choose, so it
    // should not be a surprise after the fact.
    if (draft.length >= 2) {
      final outline = ribbonAround(draft, RoomTraceBloc.corridorWidthUnits / 2);
      if (outline.length >= 3) {
        final path = Path()
          ..moveTo(_at(outline.first, size).dx, _at(outline.first, size).dy);
        for (final corner in outline.skip(1)) {
          final at = _at(corner, size);
          path.lineTo(at.dx, at.dy);
        }
        path.close();
        canvas.drawPath(
          path,
          Paint()..color = AppColors.coral.withValues(alpha: 0.18),
        );
      }
    }

    final points = [for (final point in draft) _at(point, size)];
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(3)
      ..strokeCap = StrokeCap.round
      ..color = AppColors.coral;
    final lineHalo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(6)
      ..strokeCap = StrokeCap.round
      ..color = halo.withValues(alpha: 0.85);

    // Open, with no dashed closing line: a corridor is a line with two ends,
    // and drawing the leader that a room's trace shows would say it is about to
    // become a loop.
    for (var i = 0; i + 1 < points.length; i++) {
      canvas.drawLine(points[i], points[i + 1], lineHalo);
      canvas.drawLine(points[i], points[i + 1], line);
    }

    for (final point in points) {
      canvas.drawCircle(point, _px(cornerRadius + 1), Paint()..color = halo);
      canvas.drawCircle(
        point,
        _px(cornerRadius - 1),
        Paint()..color = AppColors.coral,
      );
    }
  }

  void _dash(Canvas canvas, Offset from, Offset to, List<Paint> paints) {
    final dash = _px(5);
    final gap = _px(4);
    final total = (to - from).distance;
    if (total < 1) return;
    final step = (to - from) / total;

    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total);
      final a = from + step * travelled;
      final b = from + step * end;
      for (final paint in paints) {
        canvas.drawLine(a, b, paint);
      }
      travelled = end + gap;
    }
  }

  void _paintOpenings(Canvas canvas, Size size, Color halo) {
    for (final opening in plan.openings) {
      final at = _at(opening.position, size);
      canvas.drawCircle(
        at,
        _px(8),
        Paint()..color = halo.withValues(alpha: 0.85),
      );
      canvas.drawCircle(
        at,
        5.5,
        Paint()
          ..color = opening.isExterior ? AppColors.warning : AppColors.coral,
      );
    }
  }

  /// The room being traced: corners so far, the walls between them, and a
  /// dashed closing line back to the start.
  void _paintDraft(Canvas canvas, Size size, Color halo) {
    if (draft.isEmpty) return;

    final points = [for (final corner in draft) _at(corner, size)];

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(3)
      ..strokeCap = StrokeCap.round
      ..color = AppColors.coral;
    final lineHalo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(6)
      ..strokeCap = StrokeCap.round
      ..color = halo.withValues(alpha: 0.85);

    for (var i = 0; i + 1 < points.length; i++) {
      canvas.drawLine(points[i], points[i + 1], lineHalo);
      canvas.drawLine(points[i], points[i + 1], line);
    }

    // The wall that closing would add, shown before it is committed so the
    // shape can be judged before it becomes a room.
    if (points.length >= 3) {
      _dashed(canvas, points.last, points.first, lineHalo, line);
    }

    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        points[i],
        _px(cornerRadius + 2),
        Paint()..color = halo,
      );
      canvas.drawCircle(
        points[i],
        _px(cornerRadius),
        Paint()
          // The first corner is the one closing snaps back to, so it is the
          // one worth being able to find.
          ..color = i == 0 ? AppColors.coral : AppColors.coralPressed,
      );
    }
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Paint halo, Paint line) {
    final dash = _px(7);
    final gap = _px(5);
    final total = (to - from).distance;
    if (total < 1) return;
    final step = (to - from) / total;

    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total);
      final a = from + step * travelled;
      final b = from + step * end;
      canvas.drawLine(a, b, halo);
      canvas.drawLine(a, b, line);
      travelled = end + gap;
    }
  }

  @override
  bool shouldRepaint(covariant RoomTracePainter old) =>
      old.plan != plan ||
      old.draft != draft ||
      old.rectification != rectification ||
      old.boardCorners != boardCorners ||
      old.scalePoints != scalePoints ||
      old.selectedRoomId != selectedRoomId ||
      old.mode != mode ||
      old.onDark != onDark ||
      old.zoom != zoom;
}
