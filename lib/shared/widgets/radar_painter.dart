import 'dart:math';
import 'package:flutter/material.dart';

/// Custom painter for radar visualization
class RadarPainter extends CustomPainter {
  final double sweepAngle; // Current sweep line angle in radians
  final Offset?
  blipPosition; // Position of the detected object (distance, angle)
  final double maxDistance; // Maximum display distance in meters

  RadarPainter({
    required this.sweepAngle,
    this.blipPosition,
    this.maxDistance = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;

    // Draw dark circular background
    final backgroundPaint = Paint()
      ..color = const Color(0xFF0A0E1A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, backgroundPaint);

    // Draw concentric rings at 25%, 50%, 75%, 100% radius
    final ringPaint = Paint()
      ..color = const Color(0xFF00E5CC).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * (i / 4), ringPaint);
    }

    // Draw crosshairs
    final crosshairPaint = Paint()
      ..color = const Color(0xFF00E5CC).withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crosshairPaint,
    );
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crosshairPaint,
    );

    // Draw sweep line
    final sweepPaint = Paint()
      ..color = const Color(0xFF00E5CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final sweepEnd = Offset(
      center.dx + radius * cos(sweepAngle),
      center.dy + radius * sin(sweepAngle),
    );
    canvas.drawLine(center, sweepEnd, sweepPaint);

    // Draw sweep gradient (fading trail)
    final sweepGradient = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: sweepAngle - 0.5,
        endAngle: sweepAngle,
        colors: [
          const Color(0xFF00E5CC).withValues(alpha: 0.0),
          const Color(0xFF00E5CC).withValues(alpha: 0.3),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      sweepAngle - 0.5,
      0.5,
      true,
      sweepGradient,
    );

    // Draw blip (detected object)
    if (blipPosition != null) {
      final blipDistance = blipPosition!.dx; // Distance in meters
      final blipAngle = blipPosition!.dy; // Angle in radians

      // Scale distance to radius
      final blipRadius = (blipDistance / maxDistance) * radius;
      final blipOffset = Offset(
        center.dx + blipRadius * cos(blipAngle),
        center.dy + blipRadius * sin(blipAngle),
      );

      // Draw blip dot
      final blipPaint = Paint()
        ..color = const Color(0xFF00E5CC)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(blipOffset, 6, blipPaint);

      // Draw blip glow
      final glowPaint = Paint()
        ..color = const Color(0xFF00E5CC).withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(blipOffset, 12, glowPaint);
    }

    // Draw outer ring
    final outerRingPaint = Paint()
      ..color = const Color(0xFF00E5CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, outerRingPaint);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.blipPosition != blipPosition ||
        oldDelegate.maxDistance != maxDistance;
  }
}
