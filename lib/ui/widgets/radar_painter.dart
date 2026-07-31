import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sonar radar: range rings + a heading needle, with a blip marking the
/// last measured surface (if any). Reusable wherever a single-ping
/// distance + heading reading needs a visual — currently the sonar
/// feature, per CLAUDE.md's "lite demo" framing for phone-based ranging.
class RadarView extends StatelessWidget {
  const RadarView({
    super.key,
    required this.headingDegrees,
    required this.distanceMeters,
    this.maxRangeMeters = 5,
    this.ringCount = 4,
  });

  /// 0–360, or null before the first compass reading arrives.
  final double? headingDegrees;

  /// Last measured distance, or null when there's no reading yet.
  final double? distanceMeters;

  final double maxRangeMeters;
  final int ringCount;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadarPainter(
        headingDegrees: headingDegrees ?? 0,
        distanceMeters: distanceMeters,
        maxRangeMeters: maxRangeMeters,
        ringCount: ringCount,
      ),
      size: Size.infinite,
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.headingDegrees,
    required this.distanceMeters,
    required this.maxRangeMeters,
    required this.ringCount,
  });

  final double headingDegrees;
  final double? distanceMeters;
  final double maxRangeMeters;
  final int ringCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;

    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= ringCount; i++) {
      canvas.drawCircle(center, radius * i / ringCount, ringPaint);
    }

    final crosshair = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crosshair,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crosshair,
    );

    // Heading needle: 0deg points "up" (away from the user, matching how
    // the phone is held facing the target surface).
    final headingRad = (headingDegrees - 90) * math.pi / 180;
    final needleEnd = center +
        Offset(math.cos(headingRad), math.sin(headingRad)) * radius;
    canvas.drawLine(
      center,
      needleEnd,
      Paint()
        ..color = const Color(0xFFFB5B47).withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    final distance = distanceMeters;
    if (distance != null) {
      final clamped = distance.clamp(0.0, maxRangeMeters);
      final blipRadius = radius * (clamped / maxRangeMeters);
      final blip = center +
          Offset(math.cos(headingRad), math.sin(headingRad)) * blipRadius;
      canvas.drawCircle(
        blip,
        6,
        Paint()..color = const Color(0xFFFB5B47),
      );
      canvas.drawCircle(
        blip,
        10,
        Paint()
          ..color = const Color(0xFFFB5B47).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    canvas.drawCircle(
      center,
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.headingDegrees != headingDegrees ||
        oldDelegate.distanceMeters != distanceMeters ||
        oldDelegate.maxRangeMeters != maxRangeMeters ||
        oldDelegate.ringCount != ringCount;
  }
}
