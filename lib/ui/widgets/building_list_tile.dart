import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/models/building.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_dimens.dart';
import 'building_actions.dart';
import 'building_glyph.dart';
import 'percent_badge.dart';

/// Building row used on Explore and Maps: glyph · name+meta · % badge.
class BuildingListTile extends StatelessWidget {
  const BuildingListTile({
    super.key,
    required this.building,
    this.metaSuffix = '',
    this.trailing,
    this.onChanged,
  });

  final Building building;
  final String metaSuffix;
  final Widget? trailing;

  /// Called after the row's own menu renames or removes this building, so the
  /// list that owns it can reload. Null on a list where editing makes no
  /// sense, and the menu is then not offered at all.
  final ValueChanged<BuildingChange>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.pushNamed(
        RouteNames.building,
        pathParameters: {'id': building.id},
        extra: building,
      ),
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      child: Row(
        children: [
          BuildingGlyph(building.glyph, size: 56),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(building.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppDimens.space2),
                Text(
                  '${building.floorsCount} '
                  '${building.floorsCount == 1 ? "floor" : "floors"}'
                  ' · ${building.mappers} mappers$metaSuffix',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.space8),
          trailing ?? PercentBadge(building.mappedPercent),
          if (onChanged case final onChanged?)
            // An explicit button rather than a long-press: this app is built
            // for people who cannot see where they are aiming, and a gesture
            // with no visible target is a feature they will never find.
            IconButton(
              tooltip: 'Options for ${building.name}',
              icon: const Icon(
                PhosphorIconsRegular.dotsThreeVertical,
                size: 20,
              ),
              onPressed: () async {
                final change = await showBuildingActions(context, building);
                if (change != BuildingChange.none) onChanged(change);
              },
            ),
        ],
      ),
    );
  }
}
