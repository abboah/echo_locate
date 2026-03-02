import 'package:flutter/material.dart';

/// Custom painter for floor plan visualization
class FloorPlanPainter extends CustomPainter {
  final List<FloorPlanPoint> points;
  final Offset? currentPosition;
  final double scale;

  FloorPlanPainter({
    required this.points,
    this.currentPosition,
    this.scale = 50.0, // pixels per meter
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Draw grid
    _drawGrid(canvas, size, center);

    // Draw measurement points
    _drawPoints(canvas, center);

    // Draw path connecting points
    _drawPath(canvas, center);

    // Draw current position indicator
    if (currentPosition != null) {
      _drawCurrentPosition(canvas, center);
    }
  }

  void _drawGrid(Canvas canvas, Size size, Offset center) {
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final gridSpacing = scale; // 1 meter = scale pixels

    // Vertical lines
    for (double x = center.dx % gridSpacing; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal lines
    for (
      double y = center.dy % gridSpacing;
      y < size.height;
      y += gridSpacing
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw axis lines
    final axisPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      axisPaint,
    );
  }

  void _drawPoints(Canvas canvas, Offset center) {
    final pointPaint = Paint()
      ..color = const Color(0xFF00E5CC)
      ..style = PaintingStyle.fill;

    for (final point in points) {
      final x = center.dx + point.x * scale;
      final y = center.dy - point.y * scale; // Flip Y axis

      canvas.drawCircle(Offset(x, y), 5, pointPaint);
    }
  }

  void _drawPath(Canvas canvas, Offset center) {
    if (points.length < 2) return;

    final pathPaint = Paint()
      ..color = const Color(0xFF00E5CC).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    final firstPoint = points.first;
    path.moveTo(
      center.dx + firstPoint.x * scale,
      center.dy - firstPoint.y * scale,
    );

    for (int i = 1; i < points.length; i++) {
      final point = points[i];
      path.lineTo(center.dx + point.x * scale, center.dy - point.y * scale);
    }

    canvas.drawPath(path, pathPaint);
  }

  void _drawCurrentPosition(Canvas canvas, Offset center) {
    if (currentPosition == null) return;

    final x = center.dx + currentPosition!.dx * scale;
    final y = center.dy - currentPosition!.dy * scale;

    // Draw current position marker
    final positionPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 8, positionPaint);

    // Draw glow
    final glowPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 15, glowPaint);
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.scale != scale;
  }
}

/// Represents a point in the floor plan
class FloorPlanPoint {
  final double x; // X coordinate in meters
  final double y; // Y coordinate in meters

  const FloorPlanPoint({required this.x, required this.y});
}
