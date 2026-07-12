import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/building.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_dimens.dart';
import 'building_glyph.dart';
import 'percent_badge.dart';

/// Building row used on Explore and Maps: glyph · name+meta · % badge.
class BuildingListTile extends StatelessWidget {
  const BuildingListTile({
    super.key,
    required this.building,
    this.metaSuffix = '',
    this.trailing,
  });

  final Building building;
  final String metaSuffix;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.pushNamed(
        RouteNames.buildingDetail,
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
        ],
      ),
    );
  }
}
