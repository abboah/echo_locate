import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/building_detail/bloc/building_detail_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/building_glyph.dart';
import '../../widgets/section_label.dart';

/// Building detail (Figma 7:301): hero, floor chips, rooms, navigate CTA.
class BuildingDetailPage extends StatelessWidget {
  const BuildingDetailPage({
    super.key,
    required this.buildingId,
    this.building,
  });

  final String buildingId;

  /// Passed via route `extra` when navigating from a list (instant render);
  /// null on deep links, where the bloc fetches by id instead.
  final Building? building;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<BuildingDetailBloc>()
        ..add(BuildingDetailStarted(buildingId: buildingId, building: building)),
      child: const _BuildingDetailView(),
    );
  }
}

class _BuildingDetailView extends StatelessWidget {
  const _BuildingDetailView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: BlocBuilder<BuildingDetailBloc, BuildingDetailState>(
        builder: (context, state) {
          if (state.status == BuildingDetailStatus.loading ||
              state.status == BuildingDetailStatus.initial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == BuildingDetailStatus.failure ||
              state.building == null) {
            return _DetailError(message: state.error ?? 'Building not found');
          }
          final building = state.building!;

          return Column(
            children: [
              _Hero(building: building),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppDimens.pageGutter),
                  children: [
                    Text(building.name, style: theme.textTheme.displaySmall),
                    const SizedBox(height: AppDimens.space4),
                    Text(
                      '${building.floorsCount} floors · '
                      '${building.mappers} mappers · ${building.updatedLabel}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppDimens.space16),
                    Row(
                      children: [
                        for (var i = 0; i < state.floors.length; i++) ...[
                          _FloorChip(
                            label: state.floors[i].label,
                            selected: state.selectedFloor == i,
                            onTap: () => context
                                .read<BuildingDetailBloc>()
                                .add(BuildingDetailFloorSelected(i)),
                          ),
                          const SizedBox(width: AppDimens.space8),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppDimens.space24),
                    if (state.selectedFloor < state.floors.length)
                      SectionLabel(
                        'Rooms on floor ${state.floors[state.selectedFloor].label}',
                      ),
                    const SizedBox(height: AppDimens.space8),
                    for (final room in state.roomsOnSelectedFloor) ...[
                      _RoomTile(room: room, building: building),
                      Divider(height: 1, color: theme.dividerColor),
                    ],
                  ],
                ),
              ),
              _BottomActions(building: building),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.building});

  final Building building;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 210,
      width: double.infinity,
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: Icon(
                BuildingGlyph.iconFor(building.glyph),
                size: 88,
                color: theme.dividerColor,
              ),
            ),
            Positioned(
              top: AppDimens.space12,
              left: AppDimens.pageGutter,
              child: _BackCircle(onTap: () => context.pop()),
            ),
            Positioned(
              top: AppDimens.space20,
              right: AppDimens.pageGutter,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                  vertical: AppDimens.space4,
                ),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? AppColors.coral.withValues(alpha: 0.18)
                      : AppColors.coralSoft,
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                ),
                child: Text(
                  '${building.mappedPercent}% mapped',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.coral,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackCircle extends StatelessWidget {
  const _BackCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark ? AppColors.darkElevated : AppColors.white,
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            PhosphorIconsRegular.caretLeft,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _FloorChip extends StatelessWidget {
  const _FloorChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = isDark ? AppColors.darkElevated : AppColors.ink;

    return Material(
      color: selected
          ? selectedBg
          : (isDark ? AppColors.darkSurface : AppColors.white),
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.transparent : theme.dividerColor,
            ),
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          ),
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: selected ? Colors.white : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.building});

  final Room room;
  final Building building;

  static IconData _iconFor(String kind) => switch (kind) {
        'hall' => PhosphorIconsRegular.armchair,
        'desk' => PhosphorIconsRegular.question,
        _ => PhosphorIconsRegular.doorOpen,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.pushNamed(
        RouteNames.navigate,
        pathParameters: {'id': building.id},
        // The room travels in the query string rather than `extra` so a
        // deep link to a specific door survives a cold start.
        queryParameters: {'room': room.id},
        extra: building,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.space12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              ),
              child: Icon(
                _iconFor(room.kind),
                size: 20,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(width: AppDimens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, style: theme.textTheme.titleMedium),
                  Text('~${room.distanceM} m away',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            Icon(
              PhosphorIconsRegular.navigationArrow,
              size: 20,
              color: theme.textTheme.bodyMedium?.color,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.building});

  final Building building;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.all(AppDimens.space16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('3D preview arrives in Phase 3'),
                  ),
                ),
                icon: const Icon(PhosphorIconsRegular.cube, size: 18),
                label: const Text('3D'),
              ),
            ),
            const SizedBox(width: AppDimens.space12),
            const _SaveButton(),
            const SizedBox(width: AppDimens.space12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => context.pushNamed(
                  RouteNames.navigate,
                  pathParameters: {'id': building.id},
                  extra: building,
                ),
                icon: const Icon(PhosphorIconsFill.navigationArrow, size: 18),
                label: const Text('Navigate here'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bookmark toggle — writes a `saved_maps` row so the building appears on the
/// Maps tab and stays available offline.
class _SaveButton extends StatelessWidget {
  const _SaveButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BuildingDetailBloc, BuildingDetailState>(
      buildWhen: (a, b) => a.saved != b.saved,
      builder: (context, state) {
        final saved = state.saved;
        return SizedBox(
          width: 56,
          child: OutlinedButton(
            onPressed: () => context
                .read<BuildingDetailBloc>()
                .add(const BuildingDetailSaveToggled()),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: saved ? AppColors.coral : null,
            ),
            child: Semantics(
              button: true,
              label: saved ? 'Saved for offline. Tap to remove.' : 'Save for offline',
              child: Icon(
                saved
                    ? PhosphorIconsFill.bookmarkSimple
                    : PhosphorIconsRegular.bookmarkSimple,
                size: 20,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.space12),
              child: _BackCircle(onTap: () => context.pop()),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
