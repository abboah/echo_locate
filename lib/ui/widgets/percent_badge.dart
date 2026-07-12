import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';

/// "94%" mapped-coverage pill. Coral-tinted when coverage is decent,
/// muted when the building is still mostly unmapped (matches Explore 7:372,
/// where SRC Building at 42% renders grey).
class PercentBadge extends StatelessWidget {
  const PercentBadge(this.percent, {super.key});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlighted = percent >= 50;
    final background = highlighted
        ? (isDark ? AppColors.coral.withValues(alpha: 0.18) : AppColors.coralSoft)
        : Theme.of(context).colorScheme.surface;
    final foreground = highlighted
        ? AppColors.coral
        : Theme.of(context).textTheme.bodyMedium?.color;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space8,
        vertical: AppDimens.space4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Text(
        '$percent%',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
