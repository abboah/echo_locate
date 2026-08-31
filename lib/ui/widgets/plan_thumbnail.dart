import 'package:flutter/material.dart';

import '../../core/models/room_plan.dart';
import '../../core/theme/app_dimens.dart';
import 'room_plan_palette.dart';

/// A traced floor at list-row size — rooms and nothing else.
///
/// Deliberately not [RoomPlanView] shrunk. That widget draws room codes, a
/// legend, doors and the route, all of which are the point at full size and
/// all of which turn into grey noise in a 56-pixel box. What survives at this
/// size is the *shape* of the floor, which is exactly what somebody scanning a
/// list of floors is matching against their memory of the building.
///
/// Fills come from [RoomPalette] rather than from a grey of its own, so a floor
/// looks like itself in the list and on the map, in both themes.
class PlanThumbnail extends StatelessWidget {
  const PlanThumbnail({super.key, required this.plan, this.size = 56});

  final RoomPlan plan;

  /// Side length in points, or `double.infinity` to fill whatever box the
  /// parent gives it — a list row wants a fixed square, a card wants the
  /// space above its title.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = RoomPalette.of(theme.brightness);

    final painted = ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      child: ColoredBox(
        color: theme.colorScheme.surface,
        // One picture, already described by the row's own text. Announcing
        // "image" here would make a screen reader read every row twice.
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: _PlanThumbnailPainter(plan: plan, palette: palette),
            // `Size.infinite` as a *preferred* size is not a constraint —
            // CustomPaint takes the box it is given, and an unbounded literal
            // would assert. Sized only when a real number was asked for.
            size: size.isFinite ? Size.square(size) : Size.zero,
            child: size.isFinite ? null : const SizedBox.expand(),
          ),
        ),
      ),
    );

    if (!size.isFinite) return painted;
    return SizedBox(width: size, height: size, child: painted);
  }
}

class _PlanThumbnailPainter extends CustomPainter {
  const _PlanThumbnailPainter({required this.plan, required this.palette});

  final RoomPlan plan;
  final RoomPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rooms = plan.drawableRooms.toList();
    if (rooms.isEmpty) return;

    // Bounds over every corner drawn, so the floor fills the box whatever
    // coordinate space it was traced in — plan units and metres both.
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final room in rooms) {
      for (final corner in room.corners) {
        if (corner.dx < left) left = corner.dx;
        if (corner.dx > right) right = corner.dx;
        if (corner.dy < top) top = corner.dy;
        if (corner.dy > bottom) bottom = corner.dy;
      }
    }
    final width = right - left;
    final height = bottom - top;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return;
    }

    const inset = 4.0;
    final scale = ((size.width - inset * 2) / width).clamp(
      0.0,
      (size.height - inset * 2) / height,
    );
    // Centred rather than corner-anchored: a long thin floor pinned to the
    // top-left reads as a rendering fault rather than as a corridor.
    final dx = (size.width - width * scale) / 2 - left * scale;
    final dy = (size.height - height * scale) / 2 - top * scale;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = palette.outline.withValues(alpha: 0.55);

    for (final room in rooms) {
      final corners = room.corners;
      if (corners.length < 3) continue;
      final path = Path()
        ..moveTo(corners.first.dx * scale + dx, corners.first.dy * scale + dy);
      for (final corner in corners.skip(1)) {
        path.lineTo(corner.dx * scale + dx, corner.dy * scale + dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = palette.fillFor(room.category));
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_PlanThumbnailPainter old) =>
      old.plan != plan || old.palette != palette;
}
