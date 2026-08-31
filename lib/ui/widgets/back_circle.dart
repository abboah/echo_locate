import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';

/// The back control for screens with no app bar.
///
/// The building screen and the floor map both open with something full-bleed
/// at the top — a hero, a schematic — so neither can carry an `AppBar`, and
/// both had grown their own private copy of this button. Identical code, and
/// neither copy was labelled, so a screen reader announced the way out of two
/// screens as an unnamed button.
///
/// Screens that *do* have an app bar keep its leading icon: an arrow to go
/// back up the hierarchy, a cross to abandon a task in progress.
class BackCircle extends StatelessWidget {
  const BackCircle({super.key, this.onTap, this.tooltip = 'Back'});

  /// Defaults to popping the route, which is what both callers wanted.
  final VoidCallback? onTap;
  final String tooltip;

  /// 42 rather than 48: it floats over content rather than sitting in a bar,
  /// and its whole circle is hittable.
  static const double diameter = 42;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isDark ? AppColors.darkElevated : AppColors.white,
          shape: const CircleBorder(),
          elevation: 1,
          child: InkWell(
            onTap: onTap ?? () => context.pop(),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: Icon(
                PhosphorIconsRegular.caretLeft,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
