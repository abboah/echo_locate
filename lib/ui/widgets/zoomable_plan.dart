import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';

/// Pinch-to-zoom and drag-to-pan around a plan, with the taps still landing
/// where the finger did.
///
/// ## Why tracing needs this
///
/// A floor plan photographed off a wall board is a whole building on a phone
/// screen. A room on it is a few millimetres across and the walls are hairlines;
/// a fingertip covers several rooms at once. Tapping a corner accurately is
/// therefore not a matter of care — at that scale the information needed to
/// place it is not on the screen. Zooming is not a convenience here, it is what
/// makes the corner visible in the first place.
///
/// ## Why the taps still work
///
/// [InteractiveViewer] transforms its child and hit-tests *through* that
/// transform, so a gesture detector inside receives `localPosition` in the
/// child's own untransformed coordinates. Everything below this widget can go
/// on dividing by the box width and never learn that a zoom happened, which is
/// the whole reason it is layered this way rather than by scaling the painter:
/// a painter that scaled itself would leave every tap needing the inverse
/// transform applied by hand, in four places, one of which would be forgotten.
///
/// A single tap passes through to the child because the child's recogniser is
/// deeper in the tree than this one's; only a two-finger gesture, or a drag, is
/// claimed here.
class ZoomablePlan extends StatefulWidget {
  const ZoomablePlan({
    super.key,
    required this.builder,
    this.maxScale = 10,
    this.showResetButton = true,
  });

  /// Builds the plan, given how magnified it currently is.
  ///
  /// The scale is passed down rather than kept private because anything drawn
  /// at a fixed pixel size has to divide by it. A 7-pixel corner marker is
  /// 7 pixels at 1× and 70 at 10×, so the dot that shows where a tap landed
  /// grows until it covers the very detail the zoom was for — and a contributor
  /// zooming in to place a corner precisely finds the marker hiding the corner.
  /// Sizes divided by this stay put on screen while the plan under them grows,
  /// which is what a map annotation should do.
  final Widget Function(BuildContext context, double scale) builder;

  /// Ten times is roughly the point at which a photographed board stops having
  /// more detail to show and starts showing its own pixels.
  final double maxScale;

  /// Whether to offer a way back to the whole floor.
  ///
  /// Worth having: somebody zoomed into one corner of a building has no way to
  /// tell how far off the rest of it is, and pinching back out is fiddly to do
  /// exactly. Turned off where the plan is decorative rather than worked on.
  final bool showResetButton;

  @override
  State<ZoomablePlan> createState() => _ZoomablePlanState();
}

class _ZoomablePlanState extends State<ZoomablePlan>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<Matrix4>? _reset;

  double _scale = 1;

  bool get _zoomed => _scale > 1.01;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
    _animation.addListener(() {
      final reset = _reset;
      if (reset != null) _controller.value = reset.value;
    });
  }

  void _onTransformChanged() {
    // Quantised before it is compared, so a pinch rebuilds the painter a few
    // times rather than on every frame. This sits above a photograph and a
    // CustomPaint, and marker sizes do not need sub-percent accuracy.
    final scale = (_controller.value.getMaxScaleOnAxis() * 20).round() / 20;
    if (scale != _scale) setState(() => _scale = scale);
  }

  void _resetZoom() {
    _reset = Matrix4Tween(
      begin: _controller.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic));
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: widget.maxScale,
          // Panning at 1× would drag the whole plan off the screen for no
          // reason; there is nothing outside it to reach.
          panEnabled: true,
          clipBehavior: Clip.hardEdge,
          child: widget.builder(context, _scale),
        ),
      ),
      if (widget.showResetButton && _zoomed)
        Positioned(
          right: AppDimens.space12,
          bottom: AppDimens.space12,
          child: _ResetChip(onPressed: _resetZoom),
        ),
    ],
  );
}

class _ResetChip extends StatelessWidget {
  const _ResetChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.ink.withValues(alpha: 0.72),
    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppDimens.space12,
          vertical: AppDimens.space8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.arrowsIn, size: 16, color: AppColors.white),
            SizedBox(width: AppDimens.space4),
            Text(
              'Fit',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
