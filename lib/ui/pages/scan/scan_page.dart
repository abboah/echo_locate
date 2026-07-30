import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';

/// Scan screen (Figma 7:448).
///
/// Phase 1: the full scanning UI over a dark placeholder viewport, with
/// mocked live stats. Phase 2 replaces the placeholder with the camera
/// feed + real coverage/room-type from the sensing services — this layout
/// stays as-is.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanline = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _scanline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The camera viewport is dark regardless of app theme.
    const viewportColor = Color(0xFF161514);

    return Scaffold(
      backgroundColor: viewportColor,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  // Viewfinder frame + animated scanline.
                  Center(
                    child: SizedBox(
                      width: 240,
                      height: 220,
                      child: AnimatedBuilder(
                        animation: _scanline,
                        builder: (context, _) => CustomPaint(
                          painter: _ViewfinderPainter(
                            scanlineT: _scanline.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppDimens.space16,
                    top: AppDimens.space12,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => context.pop(),
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(PhosphorIconsRegular.x,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: AppDimens.space20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space12,
                          vertical: AppDimens.space8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.coral,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppDimens.space8),
                            const Text(
                              'Scanning',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: AppDimens.space32,
                    child: Center(
                      child: Text(
                        'Pan slowly along the wall',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _ScanSheet(),
        ],
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.scanlineT});

  final double scanlineT;

  @override
  void paint(Canvas canvas, Size size) {
    final corner = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const len = 26.0;
    const r = 14.0;
    final w = size.width;
    final h = size.height;

    // Four rounded corner brackets.
    canvas.drawPath(
      Path()
        ..moveTo(0, len)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(len, 0),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - len, 0)
        ..lineTo(w - r, 0)
        ..quadraticBezierTo(w, 0, w, r)
        ..lineTo(w, len),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w, h - len)
        ..lineTo(w, h - r)
        ..quadraticBezierTo(w, h, w - r, h)
        ..lineTo(w - len, h),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(len, h)
        ..lineTo(r, h)
        ..quadraticBezierTo(0, h, 0, h - r)
        ..lineTo(0, h - len),
      corner,
    );

    // Animated coral scanline.
    final y = h * (0.25 + 0.5 * scanlineT);
    canvas.drawLine(
      Offset(w * 0.08, y),
      Offset(w * 0.92, y),
      Paint()
        ..color = AppColors.coral
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter old) =>
      old.scanlineT != scanlineT;
}

class _ScanSheet extends StatelessWidget {
  const _ScanSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16,
        AppDimens.space12,
        AppDimens.space16,
        AppDimens.space16,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              ),
            ),
            const SizedBox(height: AppDimens.space16),
            const Row(
              children: [
                _StatChip(label: 'Room type', value: 'Corridor'),
                SizedBox(width: AppDimens.space8),
                _StatChip(
                  label: 'Coverage',
                  value: '74%',
                  valueColor: AppColors.coral,
                ),
                SizedBox(width: AppDimens.space8),
                _StatChip(label: 'Size', value: '18×4m'),
              ],
            ),
            const SizedBox(height: AppDimens.space16),
            ElevatedButton(
              onPressed: () {
                context.pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Scan saved locally (mock) — live scanning lands in Phase 2',
                    ),
                  ),
                );
              },
              child: const Text('Done — save & upload'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppDimens.space12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            const SizedBox(height: AppDimens.space2),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(color: valueColor),
            ),
          ],
        ),
      ),
    );
  }
}
