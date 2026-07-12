import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/building.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';

/// Turn-by-turn navigation view (Figma 7:265).
///
/// Phase 1: static mock — the floor plan, route and instruction card are
/// hardcoded to match the design. Phase 2 wires the real floor plan +
/// A* route into this exact layout.
class NavigationPage extends StatelessWidget {
  const NavigationPage({super.key, this.building});

  final Building? building;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buildingName = building?.name ?? 'CABS Block';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space16,
                vertical: AppDimens.space8,
              ),
              child: Row(
                children: [
                  Material(
                    color: theme.brightness == Brightness.dark
                        ? AppColors.darkElevated
                        : AppColors.white,
                    shape: const CircleBorder(),
                    elevation: 1,
                    child: InkWell(
                      onTap: () => context.pop(),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(
                          Icons.chevron_left,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(buildingName, style: theme.textTheme.titleMedium),
                      Text(
                        'Floor 2 · heading to Conference Room',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _FloorPlanPainter(
                  brightness: theme.brightness,
                  hairline: theme.dividerColor,
                  onSurface: theme.colorScheme.onSurface,
                  muted: theme.textTheme.bodyMedium?.color ??
                      AppColors.inkMuted,
                ),
              ),
            ),
            const _InstructionCard(),
          ],
        ),
      ),
    );
  }
}

/// Static mock plan: rooms 203–206 along a corridor, dotted route into the
/// highlighted Conference Room.
class _FloorPlanPainter extends CustomPainter {
  _FloorPlanPainter({
    required this.brightness,
    required this.hairline,
    required this.onSurface,
    required this.muted,
  });

  final Brightness brightness;
  final Color hairline;
  final Color onSurface;
  final Color muted;

  bool get _dark => brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    final surface =
        Paint()..color = _dark ? AppColors.darkSurface : AppColors.surface;
    final roomFill =
        Paint()..color = _dark ? AppColors.darkElevated : AppColors.white;
    final roomBorder = Paint()
      ..color = hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    canvas.drawRect(Offset.zero & size, surface);

    // Faint structural grid.
    final grid = Paint()
      ..color = hairline.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += size.width / 6) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += size.height / 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final w = size.width;
    final h = size.height;

    Rect room(double l, double t, double r, double b) =>
        Rect.fromLTRB(w * l, h * t, w * r, h * b);

    void drawRoom(Rect rect, String label, {bool highlighted = false}) {
      final rrect =
          RRect.fromRectAndRadius(rect, const Radius.circular(4));
      if (highlighted) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = _dark
                ? AppColors.coral.withValues(alpha: 0.16)
                : AppColors.coralSoft,
        );
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = AppColors.coral
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      } else {
        canvas.drawRRect(rrect, roomFill);
        canvas.drawRRect(rrect, roomBorder);
      }
      _text(
        canvas,
        label,
        rect.center,
        color: highlighted ? AppColors.coral : muted,
        bold: highlighted,
      );
    }

    // Top row of rooms.
    drawRoom(room(0.02, 0.06, 0.30, 0.30), '203');
    drawRoom(room(0.36, 0.06, 0.62, 0.30), '204');
    drawRoom(room(0.68, 0.06, 0.98, 0.30), '205');

    // Corridor label.
    _text(canvas, 'Corridor', Offset(w * 0.5, h * 0.415), color: muted);

    // Bottom rooms.
    drawRoom(room(0.02, 0.52, 0.30, 0.78), '206');
    drawRoom(room(0.38, 0.52, 0.98, 0.78), 'Conference Rm',
        highlighted: true);

    // Dotted route: along the corridor, then down into the room.
    const routeColor = AppColors.coral;
    final start = Offset(w * 0.10, h * 0.43);
    final corner = Offset(w * 0.70, h * 0.43);
    final end = Offset(w * 0.70, h * 0.58);
    _dottedLine(canvas, start, corner, routeColor);
    _dottedLine(canvas, corner, end, routeColor);

    // Current position: coral dot with soft halo.
    canvas.drawCircle(
        start, 10, Paint()..color = routeColor.withValues(alpha: 0.25));
    canvas.drawCircle(start, 5.5, Paint()..color = routeColor);

    // Destination dot.
    canvas.drawCircle(end, 5, Paint()..color = onSurface);
  }

  void _dottedLine(Canvas canvas, Offset from, Offset to, Color color) {
    const dotSpacing = 14.0;
    final paint = Paint()..color = color;
    final delta = to - from;
    final count = (delta.distance / dotSpacing).floor();
    for (var i = 1; i <= count; i++) {
      final t = i / (count + 1);
      canvas.drawCircle(from + delta * t, 2.4, paint);
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center, {
    required Color color,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _FloorPlanPainter old) =>
      old.brightness != brightness;
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(AppDimens.space12),
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.white,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.coral,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.arrow_upward, color: Colors.white),
              ),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Continue 80 m',
                        style: theme.textTheme.titleMedium),
                    Text(
                      'Then turn right into Conference Room',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '2 min',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppColors.coral),
                  ),
                  Text('120 m', style: theme.textTheme.labelSmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space16),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: LinearProgressIndicator(
              value: 0.33,
              minHeight: 5,
              backgroundColor: theme.colorScheme.surface,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.coral),
            ),
          ),
        ],
      ),
    );
  }
}
