import 'package:flutter/material.dart';

import '../../core/theme/app_dimens.dart';

/// How a screen adapts to the device it is on.
///
/// Every page laid itself out for one phone: a 22-point gutter whatever the
/// width, a grid pinned at two columns, and content running the full width of
/// whatever it was given. That is fine on the handset it was designed against
/// and wrong at both ends — cramped at 320dp, and on a tablet a line of body
/// text ran the whole width of the screen, which is unreadable however good
/// the type is.
///
/// Deliberately three breakpoints and no more. This is a phone app with an
/// accessibility remit, not a responsive web layout, and every extra breakpoint
/// is another combination nobody will test.
abstract final class Responsive {
  /// Below this a phone is small enough that the standard gutter is eating
  /// content — older and cheaper handsets, which for this app's audience is
  /// most of them.
  static const double compactWidth = 360;

  /// Above this the device is a tablet or a phone in landscape, and a single
  /// column of full-width text stops being readable.
  static const double expandedWidth = 720;

  static double _width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) => _width(context) < compactWidth;

  static bool isExpanded(BuildContext context) =>
      _width(context) >= expandedWidth;

  /// The page gutter for this width.
  static double gutter(BuildContext context) {
    final width = _width(context);
    if (width < compactWidth) return AppDimens.space16;
    if (width >= expandedWidth) return AppDimens.space32;
    return AppDimens.pageGutter;
  }

  /// Standard page padding: the gutter on both sides, plus room at the bottom
  /// so the last row of a list is not jammed against the navigation bar.
  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = AppDimens.space16,
    double bottom = AppDimens.space32,
  }) {
    final side = gutter(context);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  /// Horizontal-only padding, for a page that manages its own vertical rhythm.
  static EdgeInsets horizontalPadding(BuildContext context) =>
      EdgeInsets.symmetric(horizontal: gutter(context));

  /// Columns for a card grid.
  ///
  /// Two is right for a phone and wrong for everything else: one column on a
  /// very narrow screen keeps the card readable instead of squeezing two, and
  /// a tablet fits three or four rather than stretching two across 1000
  /// points.
  static int gridColumns(BuildContext context) {
    final width = _width(context);
    if (width < 340) return 1;
    if (width < expandedWidth) return 2;
    if (width < 1000) return 3;
    return 4;
  }

  /// Card aspect ratio, paired with [gridColumns].
  ///
  /// A single-column card is wide, so it must be much shorter or it becomes a
  /// full-screen tile. Scaled down with the text scale factor as well: the
  /// card's text block grows with the system font while the ratio would
  /// otherwise hold the box the same size, which is what makes a card overflow.
  static double cardAspectRatio(BuildContext context) {
    final columns = gridColumns(context);
    final base = columns == 1 ? 1.9 : 0.82;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return base / scale.clamp(1.0, 1.6);
  }

  /// Caps a column of reading content and centres it.
  ///
  /// Body text past about 70 characters is measurably harder to read, and this
  /// app's users are the ones least able to absorb the cost. Below the cap it
  /// changes nothing at all, so it is safe to wrap a phone layout in.
  static Widget readable(
    BuildContext context,
    Widget child, {
    double max = 640,
  }) {
    if (!isExpanded(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}
