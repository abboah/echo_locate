import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../services/mapping/floor_mapping_status.dart';

/// How far along a floor is, as a pill.
///
/// One definition, because the same floor is now shown on two screens — the
/// contributor hub and the Maps tab — and a floor that reads "Ready" on one and
/// "Needs doors" on the other would be a bug the user has no way to resolve.
///
/// The wording is what is *missing*, not a grade. "Needs doors" tells somebody
/// what to go and do; "40% complete" tells them nothing they can act on.
class FloorStageChip extends StatelessWidget {
  const FloorStageChip({super.key, required this.stage});

  final FloorMappingStage stage;

  static (String, Color) _describe(FloorMappingStage stage) => switch (stage) {
    FloorMappingStage.notStarted => ('Not mapped', AppColors.inkMuted),
    FloorMappingStage.needsDoors => ('Needs doors', AppColors.warning),
    FloorMappingStage.disconnected => ('Not joined up', AppColors.warning),
    FloorMappingStage.countsPending => ('Counts pending', AppColors.warning),
    FloorMappingStage.ready => ('Ready', AppColors.success),
  };

  /// The stage as a phrase a screen reader can put in a sentence.
  static String labelFor(FloorMappingStage stage) => _describe(stage).$1;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = _describe(stage);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      // The row's own label already says the stage in its sentence; the pill
      // repeating it would have a screen reader say it twice.
      child: ExcludeSemantics(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colour,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
