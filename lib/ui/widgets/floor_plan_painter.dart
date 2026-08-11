import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/landmark.dart';
import '../../core/theme/app_colors.dart';
import '../../services/mapping/floor_graph.dart';

/// Draws a building's merged landmark graph as a corridor schematic.
///
/// Corridors are the legs people walked, landmarks are the signs they read,
/// and the highlighted line is the route being planned. Nothing here is
/// surveyed: the geometry comes from tapped turns and step counts, so it is
/// labelled a schematic in the UI and in the report. What it gets right is
/// topology — which corridor meets which, and how far along each one things
/// are — and that is what a route needs.
///
/// Structure follows `radar_painter.dart`: theme colours passed in, all
/// measurement done against the canvas so it scales to any tile size.
class FloorPlanPainter extends CustomPainter {
  FloorPlanPainter({
    required this.graph,
    required this.landmarks,
    required this.brightness,
    required this.hairline,
    required this.onSurface,
    required this.muted,
    this.highlighted = const [],
  });

  final FloorGraph graph;

  /// Landmark id → record, for names and glyphs.
  final Map<String, Landmark> landmarks;

  /// Landmark ids along the planned route, in walking order.
  final List<String> highlighted;

  final Brightness brightness;
  final Color hairline;
  final Color onSurface;
  final Color muted;

  bool get _dark => brightness == Brightness.dark;

  static const double _padding = 28;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _dark ? AppColors.darkSurface : AppColors.surface,
    );
    if (graph.isEmpty) return;

    final project = _projection(size);
    final onPath = highlighted.toSet();

    final corridor = Paint()
      ..color = hairline
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final walked = Paint()
      ..color = _dark
          ? AppColors.darkElevated
          : AppColors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Corridors first, so landmarks sit on top of them.
    for (final edge in graph.edges) {
      final from = graph.nodeOf(edge.fromId);
      final to = graph.nodeOf(edge.toId);
      if (from == null || to == null) continue;
      canvas.drawLine(project(from.x, from.y), project(to.x, to.y), corridor);
      canvas.drawLine(project(from.x, from.y), project(to.x, to.y), walked);
    }

    // The planned route, drawn along the legs it actually uses rather than as
    // a straight line between endpoints — the difference is the whole point of
    // routing over recorded walks.
    if (highlighted.length > 1) {
      final route = Paint()
        ..color = AppColors.coral
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < highlighted.length - 1; i++) {
        final from = graph.nodeOf(highlighted[i]);
        final to = graph.nodeOf(highlighted[i + 1]);
        if (from == null || to == null) continue;
        canvas.drawLine(project(from.x, from.y), project(to.x, to.y), route);
      }
    }

    for (final entry in graph.nodes.entries) {
      final landmark = landmarks[entry.key];
      final centre = project(entry.value.x, entry.value.y);
      final isOnPath = onPath.contains(entry.key);
      final isEnd = highlighted.isNotEmpty &&
          (highlighted.first == entry.key || highlighted.last == entry.key);

      _drawNode(canvas, centre, landmark?.kind, isOnPath: isOnPath, isEnd: isEnd);

      // Labelling every node turns a corridor into a wall of text. The route's
      // own landmarks are named, and so are doors and entrances — the things
      // somebody scanning the map is looking for.
      final name = landmark?.displayName;
      if (name == null) continue;
      final worthNaming = isOnPath ||
          landmark!.kind == LandmarkKind.door ||
          landmark.kind == LandmarkKind.entrance;
      if (!worthNaming) continue;

      _drawLabel(
        canvas,
        name,
        centre + const Offset(0, 14),
        size,
        color: isOnPath ? AppColors.coral : muted,
        bold: isEnd,
      );
    }
  }

  /// Metres → canvas pixels, fitted with north up.
  Offset Function(double x, double y) _projection(Size size) {
    final bounds = graph.bounds;
    final spanX = bounds.maxX - bounds.minX;
    final spanY = bounds.maxY - bounds.minY;

    final usableWidth = math.max(size.width - _padding * 2, 1.0);
    final usableHeight = math.max(size.height - _padding * 2, 1.0);

    // A single landmark, or a perfectly straight corridor, has no extent in
    // one axis; fall back to a fixed scale rather than dividing by zero.
    final scale = math.min(
      spanX < 0.01 ? double.infinity : usableWidth / spanX,
      spanY < 0.01 ? double.infinity : usableHeight / spanY,
    );
    final metresToPixels = scale.isFinite ? scale : 8.0;

    final drawnWidth = spanX * metresToPixels;
    final drawnHeight = spanY * metresToPixels;
    final offsetX = (size.width - drawnWidth) / 2;
    final offsetY = (size.height - drawnHeight) / 2;

    return (x, y) => Offset(
          offsetX + (x - bounds.minX) * metresToPixels,
          // Canvas y grows downward; north should be up.
          offsetY + (bounds.maxY - y) * metresToPixels,
        );
  }

  void _drawNode(
    Canvas canvas,
    Offset centre,
    LandmarkKind? kind, {
    required bool isOnPath,
    required bool isEnd,
  }) {
    final fill = Paint()
      ..color = isOnPath
          ? AppColors.coral
          : (_dark ? AppColors.darkOnSurface : onSurface);

    switch (kind) {
      case LandmarkKind.stairs:
      case LandmarkKind.lift:
        // Square: a place you leave the floor from.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: centre, width: 11, height: 11),
            const Radius.circular(2),
          ),
          fill,
        );
      case LandmarkKind.door:
      case LandmarkKind.entrance:
        canvas.drawCircle(centre, isEnd ? 7 : 5.5, fill);
        canvas.drawCircle(
          centre,
          isEnd ? 11 : 9,
          Paint()
            ..color = fill.color.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
      case _:
        canvas.drawCircle(centre, 4.5, fill);
    }
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset anchor,
    Size bounds, {
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

    // Keep labels inside the tile; a name clipped at the edge is unreadable.
    final dx = (anchor.dx - painter.width / 2)
        .clamp(2.0, math.max(2.0, bounds.width - painter.width - 2))
        .toDouble();
    final dy = anchor.dy
        .clamp(2.0, math.max(2.0, bounds.height - painter.height - 2))
        .toDouble();
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter old) =>
      old.graph != graph ||
      old.highlighted != highlighted ||
      old.brightness != brightness;
}
