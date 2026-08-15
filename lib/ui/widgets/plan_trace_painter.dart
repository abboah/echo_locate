import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/plan_trace/bloc/plan_trace_bloc.dart';

/// Draws the trace over the photographed plan: corridors, the landmarks placed
/// on them, and the span the scale was measured from.
///
/// The plan's coordinate space is the **box**, not the image inside it: [u] and
/// [v] are both fractions of the box's width, which is the same space taps are
/// converted into. Anchoring both axes to the width is what keeps a traced
/// corridor square when the box is not.
class PlanTracePainter extends CustomPainter {
  const PlanTracePainter({
    required this.points,
    required this.links,
    required this.selectedRef,
    required this.onDark,
  });

  final List<PlanPoint> points;
  final List<PlanLink> links;
  final String? selectedRef;
  final bool onDark;

  static const double nodeRadius = 9;

  Offset _at(double u, double v, Size size) =>
      Offset(u * size.width, v * size.width);

  @override
  void paint(Canvas canvas, Size size) {
    final halo = onDark ? AppColors.ink : AppColors.white;

    final corridor = Paint()
      ..color = AppColors.coral
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Drawn under the corridors so a coral line stays visible over a dark
    // photograph, which is what most plans behind glass photograph as.
    final corridorHalo = Paint()
      ..color = halo.withValues(alpha: 0.85)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final link in links) {
      final from = _find(link.fromRef);
      final to = _find(link.toRef);
      if (from == null || to == null) continue;
      final a = _at(from.u, from.v, size);
      final b = _at(to.u, to.v, size);
      canvas.drawLine(a, b, corridorHalo);
      canvas.drawLine(a, b, corridor);
    }

    for (final point in points) {
      final centre = _at(point.u, point.v, size);
      final selected = point.ref == selectedRef;

      canvas.drawCircle(
        centre,
        nodeRadius + 3,
        Paint()..color = halo.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        centre,
        nodeRadius,
        Paint()..color = selected ? AppColors.ink : AppColors.coral,
      );
      if (selected) {
        // The point the next tap will join to, so the ring is the one piece of
        // state the gesture model depends on being visible.
        canvas.drawCircle(
          centre,
          nodeRadius + 6,
          Paint()
            ..color = AppColors.coral
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }

      _drawLabel(canvas, point.displayName, centre, halo);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset centre, Color halo) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: onDark ? AppColors.darkOnSurface : AppColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          // Legible over a photograph without measuring a background box for
          // every label.
          shadows: [Shadow(color: halo, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, centre + Offset(nodeRadius + 6, -painter.height / 2));
  }

  PlanPoint? _find(String ref) {
    for (final point in points) {
      if (point.ref == ref) return point;
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant PlanTracePainter old) =>
      old.points != points ||
      old.links != links ||
      old.selectedRef != selectedRef ||
      old.onDark != onDark;
}
