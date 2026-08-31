import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/building_mapping/bloc/building_mapping_cubit.dart';
import '../../../services/injection_container.dart';
import '../../../services/mapping/floor_mapping_status.dart';
import '../../widgets/building_actions.dart';
import '../../widgets/floor_stage_chip.dart';
import '../../widgets/responsive.dart';

/// A building: its floors, what state each is in, and what to do next.
///
/// **The building screen.** Tapping a building anywhere — Home, Explore, Maps —
/// lands here. A separate detail screen used to stand in front of it, showing a
/// hero, a room list read from a table nothing writes to, and a "Floors and
/// plans" button that led here anyway. Two taps and a stale room list to reach
/// the one screen that knew the truth about the building.
///
/// So this answers three questions and nothing else — where does this building
/// stand, what is the next thing to do, and is it finished. Every floor gets
/// exactly one primary action, because a person standing in a corridor with a
/// phone does not want a menu.
class BuildingMappingPage extends StatelessWidget {
  const BuildingMappingPage({
    super.key,
    required this.buildingId,
    this.buildingName,
  });

  final String buildingId;

  /// Passed through from wherever the building was chosen, so the screen can
  /// name it without a second fetch.
  final String? buildingName;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => BuildingMappingCubit(getIt(), getIt())..load(buildingId),
    child: BuildingMappingView(buildingName: buildingName),
  );
}

/// The screen itself, given a cubit already in the tree — so it can be tested
/// against mocks.
class BuildingMappingView extends StatelessWidget {
  const BuildingMappingView({super.key, this.buildingName});

  final String? buildingName;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<BuildingMappingCubit, BuildingMappingState>(
        listenWhen: (before, after) =>
            after.error != null && before.error != after.error,
        listener: (context, state) => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(state.error!))),
        builder: (context, state) {
          // The loaded name wins over the one passed in: after a rename the
          // route argument still holds the old name, and the header must not
          // keep showing what the user has just corrected.
          final name = state.building?.name ?? buildingName ?? 'Building';

          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(PhosphorIcons.arrowLeft),
                tooltip: 'Back',
                onPressed: () => context.pop(),
              ),
              title: Text(name, overflow: TextOverflow.ellipsis),
              actions: [
                if (state.status == BuildingMappingStatus.ready) ...[
                  IconButton(
                    tooltip: 'Rename this building',
                    icon: const Icon(PhosphorIcons.pencilSimple, size: 20),
                    onPressed: () => _rename(context, state),
                  ),
                  IconButton(
                    tooltip: state.saved
                        ? 'Saved for offline. Tap to remove.'
                        : 'Save for offline',
                    icon: Icon(
                      state.saved
                          ? PhosphorIconsFill.bookmarkSimple
                          : PhosphorIconsRegular.bookmarkSimple,
                      size: 20,
                      color: state.saved ? AppColors.coral : null,
                    ),
                    onPressed: () =>
                        context.read<BuildingMappingCubit>().toggleSaved(),
                  ),
                ],
              ],
            ),
            body: switch (state.status) {
              BuildingMappingStatus.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              BuildingMappingStatus.failed => _Failed(state: state),
              BuildingMappingStatus.ready => _Floors(state: state),
            },
          );
        },
      );

  Future<void> _rename(BuildContext context, BuildingMappingState state) async {
    final cubit = context.read<BuildingMappingCubit>();
    final edited = await showDialog<({String name, String area})>(
      context: context,
      // The same dialog the building lists open, so the two cannot drift on
      // the one line that matters — that the traced floors stay put.
      builder: (_) => RenameBuildingDialog(
        name: state.building?.name ?? buildingName ?? '',
        area: state.building?.area ?? '',
      ),
    );
    if (edited == null) return;
    await cubit.rename(name: edited.name, area: edited.area);
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.state});

  final BuildingMappingState state;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppDimens.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            state.error ?? 'Could not load this building.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppDimens.space16),
          FilledButton(
            onPressed: () => context.read<BuildingMappingCubit>().refresh(),
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _Floors extends StatelessWidget {
  const _Floors({required this.state});

  final BuildingMappingState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = state.nextFloor;

    return RefreshIndicator(
      onRefresh: () => context.read<BuildingMappingCubit>().refresh(),
      child: ListView(
        padding: Responsive.pagePadding(context),
        children: [
          Text(state.progress.summary, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.space4),
          if (state.isComplete)
            Text(
              'Anyone can navigate it now. Walk a few routes and check them '
              'before you call it done.',
              style: theme.textTheme.bodySmall,
            )
          else if (next != null)
            Text(
              'Next: ${_floorName(next)} — '
              '${next.nextActionReason}',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: AppDimens.space16),
          for (final floor in state.floors)
            _FloorCard(
              floor: floor,
              isNext: floor.floor.id == next?.floor.id,
              buildingId: state.buildingId,
            ),
        ],
      ),
    );
  }
}

class _FloorCard extends StatelessWidget {
  const _FloorCard({
    required this.floor,
    required this.isNext,
    required this.buildingId,
  });

  final FloorMappingStatus floor;
  final bool isNext;
  final String buildingId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.space12),
      // The next floor is the only one highlighted. More than one emphasis is
      // no emphasis, and the whole job of this screen is saying which one.
      shape: isNext
          ? RoundedRectangleBorder(
              side: const BorderSide(color: AppColors.coral, width: 1.5),
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _floorName(floor),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                FloorStageChip(stage: floor.stage),
              ],
            ),
            const SizedBox(height: AppDimens.space4),
            Text(floor.summary, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppDimens.space12),
            if (floor.stage == FloorMappingStage.notStarted)
              _StartRow(floor: floor, buildingId: buildingId)
            else
              _ContinueRow(floor: floor, buildingId: buildingId),
          ],
        ),
      ),
    );
  }
}

/// A floor nobody has touched: choose how to map it.
class _StartRow extends StatelessWidget {
  const _StartRow({required this.floor, required this.buildingId});

  final FloorMappingStatus floor;
  final String buildingId;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        // Tracing is the only authoring path. A floor takes about fifteen
        // minutes, needs no ARCore, and produces the same artefact on every
        // phone — which is what makes contributing possible on the hardware
        // most contributors actually own.
        child: FilledButton.icon(
          onPressed: () => _go(context, RouteNames.roomTrace),
          icon: const Icon(PhosphorIcons.image, size: 18),
          label: const Text('Trace a photo'),
        ),
      ),
    ],
  );

  void _go(BuildContext context, String route) {
    final cubit = context.read<BuildingMappingCubit>();
    context
        .pushNamed(
          route,
          pathParameters: {'id': buildingId},
          extra: floor.floor.id,
        )
        // The floor has changed underneath while they were away.
        .then((_) => cubit.refresh());
  }
}

/// A floor part-way through: one primary action, plus the tools.
class _ContinueRow extends StatelessWidget {
  const _ContinueRow({required this.floor, required this.buildingId});

  final FloorMappingStatus floor;
  final String buildingId;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: () => _go(context, _primaryRoute),
              child: Text(floor.nextActionLabel),
            ),
          ),
          const SizedBox(width: AppDimens.space8),
          IconButton.outlined(
            tooltip: 'Edit this floor',
            icon: const Icon(PhosphorIcons.pencilSimple, size: 18),
            onPressed: () => _go(context, RouteNames.planEditor),
          ),
        ],
      ),
      // Offered the moment a floor is walkable, not only when it is
      // perfect. A floor with pending door counts routes fine — it just
      // will not name which door — and hearing it aloud is how somebody
      // finds out whether the map is any good.
      if (floor.stage.isNavigable) ...[
        const SizedBox(height: AppDimens.space8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _go(context, RouteNames.roomNavigate),
            icon: const Icon(PhosphorIcons.navigationArrow, size: 18),
            label: const Text('Walk this floor'),
          ),
        ),
      ],
    ],
  );

  /// Where the primary action goes.
  ///
  /// Back to the method that made the floor, because that is where the tools
  /// for it are: a traced plan gets its doors by tapping the photograph, a
  /// scanned one by standing in the doorway. Sending somebody to the other one
  /// would mean tracing over geometry captured in metres.
  ///
  /// A disconnected *scanned* floor is the exception — two AR captures parked
  /// beside each other need aligning, and that is an editor job.
  ///
  /// A disconnected *traced* floor is not the same problem and used to be sent
  /// to the same place. What disconnects a traced floor is almost always a
  /// corridor that was never drawn — and the editor cannot draw one. Its only
  /// join is "add a door between two rooms that share a wall", which in a
  /// building whose rooms open onto a hallway is both the wrong fix and a door
  /// that does not exist. The corridor tool is in the tracer, so that is where
  /// this goes; re-opening it loads the floor as traced so far and continues
  /// it rather than starting again.
  String get _primaryRoute => switch (floor.stage) {
    // A disconnected traced floor is almost always a corridor nobody drew,
    // and the corridor tool is in the tracer. Re-opening loads the floor as
    // traced so far and continues it rather than starting again.
    FloorMappingStage.disconnected => RouteNames.roomTrace,
    // A finished floor's primary action is to walk it. There is nothing left
    // to author, and walking is how a contributor finds out whether the floor
    // they traced actually guides somebody.
    FloorMappingStage.ready => RouteNames.roomNavigate,
    _ => RouteNames.roomTrace,
  };

  void _go(BuildContext context, String route) {
    final cubit = context.read<BuildingMappingCubit>();
    context
        .pushNamed(
          route,
          pathParameters: {'id': buildingId},
          extra: floor.floor.id,
        )
        .then((_) => cubit.refresh());
  }
}

String _floorName(FloorMappingStatus floor) {
  final label = floor.floor.label.trim();
  if (label.isEmpty) return 'Floor';
  if (label.toUpperCase() == 'G') return 'Ground floor';
  return 'Floor $label';
}
