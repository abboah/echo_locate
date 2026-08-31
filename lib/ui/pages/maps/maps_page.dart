import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/maps/bloc/maps_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/floor_stage_chip.dart';
import '../../widgets/plan_thumbnail.dart';
import '../../widgets/responsive.dart';

/// Maps tab: the floors traced onto this phone, and the way into walking one.
///
/// This tab used to list bookmarked *buildings*, which meant it could be full
/// while nothing on it was walkable, and empty while the phone held four traced
/// floors. The floors were reachable only through the contributor hub, two taps
/// inside a screen about mapping — so the artefact the whole app exists to
/// produce had nowhere of its own to live.
///
/// So: one section per building, one row per floor, and the row walks it. A
/// floor that is not finished is still listed, says what it is missing, and
/// leads to the tool that fixes it rather than to a dead end.
class MapsPage extends StatelessWidget {
  const MapsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<MapsBloc>()..add(const MapsStarted()),
      child: const MapsView(),
    );
  }
}

/// The screen itself, given a bloc already in the tree — so it can be tested
/// against mock repositories.
class MapsView extends StatelessWidget {
  const MapsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<MapsBloc, MapsState>(
          listenWhen: (before, after) =>
              after.error != null && before.error != after.error,
          listener: (context, state) => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.error!))),
          builder: (context, state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: Responsive.pagePadding(context, bottom: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Maps', style: theme.textTheme.displaySmall),
                    const SizedBox(height: AppDimens.space4),
                    Text(switch (state.status) {
                      MapsStatus.success when state.buildings.isNotEmpty =>
                        _countLine(state),
                      _ => 'Floor plans traced onto this phone.',
                    }, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.space16),
              Expanded(
                child: switch (state.status) {
                  MapsStatus.initial || MapsStatus.loading => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  MapsStatus.failure => _MapsError(
                    message: state.error ?? 'Could not read the saved plans',
                  ),
                  MapsStatus.success when state.buildings.isEmpty =>
                    const _EmptyMaps(),
                  MapsStatus.success => RefreshIndicator(
                    onRefresh: () async =>
                        context.read<MapsBloc>().add(const MapsStarted()),
                    child: ListView.separated(
                      padding: Responsive.pagePadding(context, top: 0),
                      itemCount: state.buildings.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppDimens.space24),
                      itemBuilder: (context, index) =>
                          _BuildingSection(building: state.buildings[index]),
                    ),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "6 floors in 2 buildings, ready to walk offline." Counted rather than
  /// asserted — the sentence is the evidence that the tab has something in it.
  static String _countLine(MapsState state) {
    final floors = state.floorCount;
    final buildings = state.buildings.length;
    final floorWord = floors == 1 ? 'floor' : 'floors';
    final buildingWord = buildings == 1 ? 'building' : 'buildings';
    return '$floors $floorWord in $buildings $buildingWord, '
        'ready to walk offline.';
  }
}

/// One building, with every floor of it that has been traced.
class _BuildingSection extends StatelessWidget {
  const _BuildingSection({required this.building});

  final MappedBuilding building;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = building.roomCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(building.name, style: theme.textTheme.titleLarge),
                  Text(
                    [
                      if (building.area case final area?) area,
                      '$rooms ${rooms == 1 ? 'room' : 'rooms'}',
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            // The way to add another floor to a building already part-mapped —
            // the action somebody on this tab most often wants next.
            IconButton(
              tooltip: 'Map another floor of ${building.name}',
              icon: const Icon(PhosphorIconsRegular.plus, size: 18),
              onPressed: () => context.pushNamed(
                RouteNames.buildingMapping,
                pathParameters: {'id': building.id},
                extra: building.name,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        for (final floor in building.floors)
          _FloorRow(floor: floor, buildingId: building.id),
      ],
    );
  }
}

/// One traced floor: what it looks like, what it is missing, and where it goes.
class _FloorRow extends StatelessWidget {
  const _FloorRow({required this.floor, required this.buildingId});

  final MappedFloor floor;
  final String buildingId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final walkable = floor.isWalkable;
    final rooms = floor.roomCount;

    // A walkable floor walks. An unfinished one goes to the hub that knows how
    // to finish it — never nowhere, and never to a walk that would fail.
    final action = walkable ? 'Walk this floor' : 'Finish mapping this floor';

    return Semantics(
      button: true,
      label:
          '${floor.title}. $rooms ${rooms == 1 ? 'room' : 'rooms'}. '
          '${FloorStageChip.labelFor(floor.status.stage)}. $action.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
            onTap: () => context.pushNamed(
              walkable ? RouteNames.roomNavigate : RouteNames.buildingMapping,
              pathParameters: {'id': buildingId},
              // roomNavigate reads `extra` as the floor to walk; the hub reads
              // it as the building's name. Two different meanings for the same
              // slot, so each gets what it expects and neither is guessed.
              extra: walkable ? floor.plan.floorId : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDimens.space8),
              child: Row(
                children: [
                  PlanThumbnail(plan: floor.plan),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                floor.title,
                                style: theme.textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppDimens.space8),
                            FloorStageChip(stage: floor.status.stage),
                          ],
                        ),
                        const SizedBox(height: AppDimens.space2),
                        Text(
                          _subtitle(rooms),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Icon(
                    walkable
                        ? PhosphorIconsFill.navigationArrow
                        : PhosphorIconsRegular.caretRight,
                    size: 20,
                    color: walkable
                        ? AppColors.coral
                        : theme.textTheme.bodyMedium?.color,
                  ),
                  // Outside the row's own tap target, so removing a floor can
                  // never be a mis-tap on the way to walking it.
                  _DeleteFloorButton(floor: floor, buildingId: buildingId),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The one sentence worth the space: how big the floor is, and the single
  /// thing that changes what guidance can say on it.
  ///
  /// A floor with no scale routes correctly and speaks its turns correctly,
  /// and can neither speak a distance nor put an arrow in the building. That
  /// is invisible on the walk, so it is said here.
  String _subtitle(int rooms) {
    final size = '$rooms ${rooms == 1 ? 'room' : 'rooms'}';
    if (!floor.isWalkable) return '$size · not walkable yet';
    if (!floor.hasScale) return '$size · no scale, so no spoken distances';
    return '$size · walk it by voice or in AR';
  }
}

/// Removing a traced floor from this device.
///
/// Twenty minutes of somebody's work, and on the published path somebody
/// else's too — so it confirms, and says which of those two this is before
/// asking.
class _DeleteFloorButton extends StatelessWidget {
  const _DeleteFloorButton({required this.floor, required this.buildingId});

  final MappedFloor floor;
  final String buildingId;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Delete ${floor.title}',
      icon: const Icon(PhosphorIconsRegular.trash, size: 18),
      onPressed: () => _confirm(context),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final bloc = context.read<MapsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${floor.title}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The traced rooms and doors for this floor are removed from '
              'this phone.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppDimens.space8),
            Text(
              // The honest limit of what this button can do. Deleting the
              // local copy of a floor somebody published does not unpublish
              // it, and implying otherwise would be worse than saying nothing.
              'If it was published, other people keep their copy. Re-open the '
              'building to download it again.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    bloc.add(
      MapsFloorDeleted(buildingId: buildingId, floorId: floor.plan.floorId),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${floor.title} deleted.')));
  }
}

class _EmptyMaps extends StatelessWidget {
  const _EmptyMaps();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsRegular.mapTrifold,
              size: 48,
              color: theme.textTheme.bodyMedium?.color,
            ),
            const SizedBox(height: AppDimens.space16),
            Text('No floor plans yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.space4),
            Text(
              // Says what a plan *is* and how one gets here, because on a fresh
              // install this screen is the first place somebody wonders.
              'Photograph the floor plan posted in a building and trace its '
              'rooms. Traced floors land here and work with no connection.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.space24),
            ElevatedButton.icon(
              onPressed: () => context.pushNamed(RouteNames.mapBuilding),
              icon: const Icon(PhosphorIconsFill.mapTrifold, size: 18),
              label: const Text('Map a building'),
            ),
            const SizedBox(height: AppDimens.space12),
            OutlinedButton(
              onPressed: () => context.goNamed(RouteNames.explore),
              child: const Text('Browse mapped buildings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapsError extends StatelessWidget {
  const _MapsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.space16),
            OutlinedButton(
              onPressed: () =>
                  context.read<MapsBloc>().add(const MapsStarted()),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
