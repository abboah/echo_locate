import 'package:flutter/material.dart';

import '../../core/models/landmark.dart';
import '../../core/models/walk_route.dart';
import '../../core/theme/app_colors.dart';
import '../../services/mapping/map_node.dart';
import '../../services/mapping/plan_viewport.dart';

/// Renders one floor of a merged landmark graph: corridors as lines, landmarks
/// as nodes, the active route highlighted.
///
/// This is a **schematic**, not a survey. Its geometry comes from step counts
/// and six turn buttons, so corridors are straight, corners are right angles,
/// and a loop will not close. Drawing it any more precisely than that would
/// claim an accuracy the data does not have.
///
/// It is also not the accessible path. A blind user never sees this; they are
/// served by the same graph through voice. The map exists for sighted
/// contributors verifying their own captures, and for examiners.
class FloorPlanView extends StatelessWidget {
  const FloorPlanView({
    super.key,
    required this.nodes,
    required this.edges,
    required this.landmarks,
    this.route,
    this.currentLandmarkId,
    this.onLandmarkTap,
  });

  /// Nodes on the floor being shown — the caller filters, so the painter never
  /// has to know which plane is active.
  final List<MapNode> nodes;

  /// Edges with both ends on this floor. A stairs leg belongs to neither and is
  /// deliberately absent: drawing it would imply a corridor that is not there.
  final List<MapEdge> edges;

  final Map<String, Landmark> landmarks;

  /// Highlighted in coral. Legs that leave this floor are skipped.
  final WalkRoute? route;

  /// Where the user is now, if guidance is running.
  final String? currentLandmarkId;

  /// Tapping a landmark declares "I am here".
  ///
  /// In the field that claim comes from OCR reading the sign; on a desk, or
  /// when the camera cannot see it, somebody has to be able to say so by hand.
  /// The same event drives both.
  final ValueChanged<String>? onLandmarkTap;

  /// How close a tap must land, in pixels. Generous, because the target is a
  /// 6 px dot and the finger is not.
  static const double tapRadius = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Computed here rather than inside paint() so a tap can be resolved
        // against exactly the projection that was drawn.
        final viewport = PlanViewport.fit(
          nodes,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );

        final painter = CustomPaint(
          size: Size.infinite,
          painter: _FloorPlanPainter(
            nodes: nodes,
            edges: edges,
            landmarks: landmarks,
            viewport: viewport,
            routeLandmarkIds: route?.landmarkIds ?? const [],
            destinationId: route?.steps.isEmpty ?? true
                ? null
                : route!.steps.last.toLandmarkId,
            currentLandmarkId: currentLandmarkId,
            brightness: theme.brightness,
            hairline: theme.dividerColor,
            onSurface: theme.colorScheme.onSurface,
            muted: theme.textTheme.bodyMedium?.color ?? AppColors.inkMuted,
          ),
        );

        final onTap = onLandmarkTap;
        if (onTap == null) return painter;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final hit = nearestTo(details.localPosition, viewport);
            if (hit != null) onTap(hit);
          },
          child: painter,
        );
      },
    );
  }

  /// The landmark nearest [point], or null when the tap missed everything.
  ///
  /// Exposed for testing: hit testing that silently drifts from the drawing is
  /// the kind of bug that only shows up as "tapping does nothing sometimes".
  String? nearestTo(Offset point, PlanViewport viewport) {
    String? best;
    var bestDistance = tapRadius;

    for (final node in nodes) {
      final centre = Offset(
        viewport.toCanvasX(node.x),
        viewport.toCanvasY(node.y),
      );
      final distance = (centre - point).distance;
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = node.landmarkId;
      }
    }

    return best;
  }
}

class _FloorPlanPainter extends CustomPainter {
  _FloorPlanPainter({
    required this.nodes,
    required this.edges,
    required this.landmarks,
    required this.viewport,
    required this.routeLandmarkIds,
    required this.destinationId,
    required this.currentLandmarkId,
    required this.brightness,
    required this.hairline,
    required this.onSurface,
    required this.muted,
  });

  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final Map<String, Landmark> landmarks;
  final PlanViewport viewport;
  final List<String> routeLandmarkIds;
  final String? destinationId;
  final String? currentLandmarkId;
  final Brightness brightness;
  final Color hairline;
  final Color onSurface;
  final Color muted;

  bool get _dark => brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _dark ? AppColors.darkSurface : AppColors.surface,
    );

    _paintGrid(canvas, size);

    if (nodes.isEmpty) return;

    final placed = {
      for (final node in nodes)
        node.landmarkId: Offset(
          viewport.toCanvasX(node.x),
          viewport.toCanvasY(node.y),
        ),
    };

    _paintCorridors(canvas, placed);
    _paintRoute(canvas, placed);
    _paintNodes(canvas, placed, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = hairline.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += size.width / 6) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += size.height / 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  /// Corridors are drawn as a bordered band rather than a hairline, so the plan
  /// reads as space you can walk through rather than a wiring diagram.
  void _paintCorridors(Canvas canvas, Map<String, Offset> placed) {
    final casing = Paint()
      ..color = hairline
      ..strokeWidth = 17
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = _dark ? AppColors.darkElevated : AppColors.white
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final from = placed[edge.fromId];
      final to = placed[edge.toId];
      if (from == null || to == null) continue;
      canvas.drawLine(from, to, casing);
    }
    // Every casing first, then every fill: drawn edge by edge, one corridor's
    // casing would cut a seam across the corridor it joins.
    for (final edge in edges) {
      final from = placed[edge.fromId];
      final to = placed[edge.toId];
      if (from == null || to == null) continue;
      canvas.drawLine(from, to, fill);
    }
  }

  void _paintRoute(Canvas canvas, Map<String, Offset> placed) {
    if (routeLandmarkIds.length < 2) return;

    final line = Paint()
      ..color = AppColors.coral
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i + 1 < routeLandmarkIds.length; i++) {
      final from = placed[routeLandmarkIds[i]];
      final to = placed[routeLandmarkIds[i + 1]];
      // A leg whose other end is on a different floor simply has no line to
      // draw here — the floor switcher is how the user follows it.
      if (from == null || to == null) continue;
      canvas.drawLine(from, to, line);
    }
  }

  void _paintNodes(Canvas canvas, Map<String, Offset> placed, Size size) {
    final onRoute = routeLandmarkIds.toSet();

    for (final node in nodes) {
      final centre = placed[node.landmarkId];
      if (centre == null) continue;

      final landmark = landmarks[node.landmarkId];
      final kind = landmark?.kind ?? LandmarkKind.sign;
      final isDestination = node.landmarkId == destinationId;
      final highlighted = isDestination || onRoute.contains(node.landmarkId);
      final colour = highlighted ? AppColors.coral : muted;

      // Shape carries the kind, so the plan stays readable in greyscale and
      // for anyone who cannot separate coral from grey.
      switch (kind) {
        case LandmarkKind.stairs:
        case LandmarkKind.lift:
          _paintSquare(canvas, centre, colour, filled: highlighted);
        case LandmarkKind.door:
        case LandmarkKind.entrance:
          canvas.drawCircle(centre, 6, Paint()..color = colour);
          canvas.drawCircle(
            centre,
            6,
            Paint()
              ..color = _dark ? AppColors.darkSurface : AppColors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        case LandmarkKind.junction:
        case LandmarkKind.sign:
          canvas.drawCircle(
            centre,
            4.5,
            Paint()
              ..color = colour
              ..style = highlighted ? PaintingStyle.fill : PaintingStyle.stroke
              ..strokeWidth = 2,
          );
      }

      final label = landmark?.displayName;
      if (label != null) {
        _paintLabel(
          canvas,
          label,
          centre + const Offset(0, 16),
          size,
          color: highlighted ? AppColors.coral : muted,
          bold: isDestination,
        );
      }
    }

    // Drawn last so the halo is never clipped by a corridor or a label.
    final current = currentLandmarkId;
    if (current != null && placed[current] != null) {
      final centre = placed[current]!;
      canvas.drawCircle(
        centre,
        11,
        Paint()..color = AppColors.coral.withValues(alpha: 0.25),
      );
      canvas.drawCircle(centre, 6, Paint()..color = AppColors.coral);
    }
  }

  void _paintSquare(
    Canvas canvas,
    Offset centre,
    Color colour, {
    required bool filled,
  }) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: 11, height: 11),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = colour
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset topCentre,
    Size size, {
    required Color color,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);

    // Nudged back inside rather than centred blindly. The viewport fits the
    // *nodes*, and a label is up to 110px wide around one — so a landmark
    // near the edge, which is exactly where an entrance or a stairwell tends
    // to sit, would otherwise have its name run off the screen.
    const margin = 4.0;
    final maxLeft = size.width - painter.width - margin;
    final left = maxLeft < margin
        ? margin
        : (topCentre.dx - painter.width / 2).clamp(margin, maxLeft);

    painter.paint(canvas, Offset(left, topCentre.dy));
  }

  @override
  bool shouldRepaint(covariant _FloorPlanPainter old) =>
      old.brightness != brightness ||
      old.viewport != viewport ||
      old.nodes != nodes ||
      old.edges != edges ||
      old.routeLandmarkIds != routeLandmarkIds ||
      old.currentLandmarkId != currentLandmarkId ||
      old.destinationId != destinationId;
}
