import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart';
import '../../../core/models/landmark.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/guidance/guidance_session.dart';
import '../../../features/routing/bloc/floor_map_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/floor_plan_painter.dart';

/// The building's map, drawn from the walks contributors recorded.
///
/// Two jobs. It shows a sighted user — a contributor checking their capture,
/// an examiner, a friend helping someone find a room — the shape of the
/// building. And it is where a route is chosen before guidance takes over,
/// including routes nobody recorded: pick any two landmarks and A* answers
/// over the merged graph.
class NavigationPage extends StatelessWidget {
  const NavigationPage({
    super.key,
    required this.buildingId,
    this.building,
    this.destinationRoomId,
  });

  final String buildingId;
  final Building? building;

  /// Set when the user arrived by tapping a room on the building screen, so
  /// the route is planned to it on open instead of asking them to pick it
  /// again.
  final String? destinationRoomId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FloorMapBloc>()
        ..add(
          FloorMapRequested(buildingId, destinationRoomId: destinationRoomId),
        ),
      child: _NavigationView(
        buildingId: buildingId,
        // The name travels with the tap when there is one; opened cold — a
        // shortcut, a restored stack — the bloc looks it up.
        buildingName: building?.name,
      ),
    );
  }
}

class _NavigationView extends StatelessWidget {
  const _NavigationView({required this.buildingId, this.buildingName});

  final String buildingId;
  final String? buildingName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<FloorMapBloc, FloorMapState>(
          builder: (context, state) {
            return Column(
              children: [
                _Header(
                  buildingName:
                      buildingName ?? state.buildingName ?? 'Building',
                  subtitle: switch (state.status) {
                    FloorMapStatus.ready => _walksLine(state),
                    FloorMapStatus.empty => 'Not mapped yet',
                    FloorMapStatus.failure => 'Map unavailable',
                    FloorMapStatus.loading => 'Loading the map…',
                  },
                ),
                Expanded(
                  child: switch (state.status) {
                    FloorMapStatus.loading => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    FloorMapStatus.failure => _Message(
                      icon: PhosphorIconsRegular.cloudSlash,
                      title: state.error ?? 'Map unavailable',
                      detail:
                          'Open this building once with a connection and '
                          'its map is kept for offline use.',
                      action: Padding(
                        padding: const EdgeInsets.only(top: AppDimens.space16),
                        child: OutlinedButton.icon(
                          onPressed: () => context.read<FloorMapBloc>().add(
                            FloorMapRequested(buildingId),
                          ),
                          icon: const Icon(
                            PhosphorIconsRegular.arrowClockwise,
                            size: 18,
                          ),
                          label: const Text('Try again'),
                        ),
                      ),
                    ),
                    FloorMapStatus.empty => _Message(
                      icon: PhosphorIconsRegular.mapTrifold,
                      title: 'Nobody has mapped this building yet',
                      detail:
                          'Trace the floor plan posted on its wall, or walk '
                          'it and record a route. Either becomes this '
                          'building’s first map — and its first directions.',
                      action: Column(
                        children: [
                          _TraceButton(buildingId: buildingId),
                          _RecordButton(buildingId: buildingId, compact: true),
                        ],
                      ),
                    ),
                    FloorMapStatus.ready => _Schematic(state: state),
                  },
                ),
                if (state.status == FloorMapStatus.ready)
                  _RoutePicker(state: state, buildingId: buildingId),
              ],
            );
          },
        ),
      ),
    );
  }

  String _walksLine(FloorMapState state) {
    final walks = state.routes.length;
    final places = state.graph.nodes.length;
    return '$places landmarks · ${walks == 1 ? '1 recorded walk' : '$walks recorded walks'}';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.buildingName, required this.subtitle});

  final String buildingName;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space8,
      ),
      child: Row(
        children: [
          Material(
            color: theme.brightness == Brightness.dark
                ? AppColors.darkElevated
                : AppColors.white,
            shape: const CircleBorder(),
            elevation: 1,
            child: InkWell(
              onTap: () => context.pop(),
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
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(buildingName, style: theme.textTheme.titleMedium),
                Text(subtitle, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Below this the drift is smaller than the dots being drawn, and saying so
/// would be noise rather than candour.
const double _spreadWorthMentioningM = 1.5;

/// Switches which floor plane is drawn.
///
/// Only the picture changes. The graph spans every floor and A* routes across
/// them, so a plan that climbs stairs stays planned whichever plane is showing.
class _FloorSwitcher extends StatelessWidget {
  const _FloorSwitcher({required this.state, required this.floorIds});

  final FloorMapState state;
  final List<String> floorIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.darkElevated : AppColors.white,
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final floorId in floorIds)
              Semantics(
                selected: floorId == state.activeFloorId,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                  onTap: () => context.read<FloorMapBloc>().add(
                    FloorMapFloorSelected(floorId),
                  ),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: floorId == state.activeFloorId
                          ? AppColors.coral
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                    ),
                    child: Text(
                      state.labelForFloor(floorId),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: floorId == state.activeFloorId
                            ? AppColors.white
                            : theme.colorScheme.onSurface,
                      ),
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

/// States how far the merge found the same landmark to be from itself.
///
/// Spec §10 asks for this as a measured result. Showing it on the map rather
/// than burying it in a log is the honest presentation: the schematic is built
/// from step counts and tapped turns, and a viewer comparing it against the
/// building deserves to know by how much it can be wrong.
class _SpreadNote extends StatelessWidget {
  const _SpreadNote({required this.metres});

  final double metres;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text =
        'Schematic — landmarks placed within about '
        '${metres.toStringAsFixed(1)} m';

    return Semantics(
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        child: ExcludeSemantics(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.textTheme.bodyMedium?.color ?? AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _Schematic extends StatelessWidget {
  const _Schematic({required this.state});

  final FloorMapState state;

  @override
  Widget build(BuildContext context) {
    final floorIds = state.mappedFloorIds;

    return Semantics(
      // The plan publishes each landmark as its own semantics node, so a screen
      // reader can explore it. This container labels the whole thing, which is
      // what a user meets first — an unlabelled rectangle says nothing.
      container: true,
      explicitChildNodes: true,
      label:
          'Schematic map of the building, drawn from recorded walks. '
          'Choose a start and a destination below to plan a route.',
      child: Stack(
        children: [
          Positioned.fill(
            child: FloorPlanView(
              nodes: state.nodesOnActiveFloor,
              edges: state.edgesOnActiveFloor,
              landmarks: state.landmarksById,
              route: state.plan,
              // A graph built from a traced plan is in plan units, not metres,
              // and the zoom cap has to know which.
              metric: state.graph.metric,
              // Tapping a landmark sets where the walk starts from. On the
              // field that claim comes from OCR; here somebody says it by hand.
              onLandmarkTap: (id) =>
                  context.read<FloorMapBloc>().add(FloorMapFromSelected(id)),
              currentLandmarkId: state.fromId,
            ),
          ),
          if (floorIds.length > 1)
            Positioned(
              top: AppDimens.space12,
              right: AppDimens.space12,
              child: _FloorSwitcher(state: state, floorIds: floorIds),
            ),
          if (state.worstSpreadM >= _spreadWorthMentioningM)
            Positioned(
              left: AppDimens.space12,
              bottom: AppDimens.space12,
              child: _SpreadNote(metres: state.worstSpreadM),
            ),
        ],
      ),
    );
  }
}

class _RoutePicker extends StatelessWidget {
  const _RoutePicker({required this.state, required this.buildingId});

  final FloorMapState state;
  final String buildingId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final plan = state.plan;
    final bothPicked = state.fromId != null && state.toId != null;

    return Container(
      margin: const EdgeInsets.all(AppDimens.space12),
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.white,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LandmarkPicker(
            label: 'From',
            value: state.fromId,
            landmarks: state.mappedLandmarks,
            onChanged: (id) =>
                context.read<FloorMapBloc>().add(FloorMapFromSelected(id)),
          ),
          const SizedBox(height: AppDimens.space8),
          _LandmarkPicker(
            label: 'To',
            value: state.toId,
            landmarks: state.mappedLandmarks,
            onChanged: (id) =>
                context.read<FloorMapBloc>().add(FloorMapToSelected(id)),
          ),
          const SizedBox(height: AppDimens.space12),
          if (plan != null)
            Row(
              children: [
                const Icon(
                  PhosphorIconsFill.path,
                  size: 18,
                  color: AppColors.coral,
                ),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: Text(
                    '${plan.legs.length} '
                    '${plan.legs.length == 1 ? 'leg' : 'legs'} · '
                    '${plan.totalDistanceM.round()} m'
                    '${plan.synthesised ? ' · joined from separate walks' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            )
          else if (bothPicked)
            Text(
              'No recorded walk connects these two yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            )
          else
            Text(
              'Pick where you are and where you are going.',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: AppDimens.space12),
          ElevatedButton.icon(
            onPressed: plan == null
                ? null
                : () => _startGuidance(context, plan.landmarkIds.last),
            icon: const Icon(PhosphorIconsFill.eye, size: 18),
            label: const Text('Start guidance'),
          ),
          const SizedBox(height: AppDimens.space8),
          _TraceButton(buildingId: buildingId, compact: true),
          const SizedBox(height: AppDimens.space8),
          _RecordButton(buildingId: buildingId, compact: true),
        ],
      ),
    );
  }

  void _startGuidance(BuildContext context, String destinationId) {
    final plan = state.plan;
    if (plan == null) return;

    context.pushNamed(
      RouteNames.guidance,
      extra: GuidanceSession(
        plan: plan,
        landmarks: state.landmarks,
        destinationName:
            state.landmarkOf(destinationId)?.displayName ?? 'your destination',
        // The whole building, so a lost user can be relocated against any sign
        // in it, not just the ones on this route.
        graph: state.graph,
        // A traced plan nobody measured routes correctly but cannot be spoken
        // in steps; guidance leans on landmark confirmation instead.
        metric: state.graph.metric,
      ),
    );
  }
}

class _LandmarkPicker extends StatelessWidget {
  const _LandmarkPicker({
    required this.label,
    required this.value,
    required this.landmarks,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Landmark> landmarks;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
      ),
      items: [
        for (final landmark in landmarks)
          DropdownMenuItem(
            value: landmark.id,
            child: Text(landmark.displayName, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (id) {
        if (id != null) onChanged(id);
      },
    );
  }
}

/// Tracing the plan posted on the wall — the faster way to map a building, and
/// the accurate one: traced coordinates are absolute, where a recorded walk's
/// are chained from step counts and drift.
class _TraceButton extends StatelessWidget {
  const _TraceButton({required this.buildingId, this.compact = false});

  final String buildingId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton.icon(
      onPressed: () async {
        final bloc = context.read<FloorMapBloc>();
        await context.pushNamed(
          RouteNames.planTrace,
          pathParameters: {'id': buildingId},
        );
        if (!bloc.isClosed) bloc.add(FloorMapRequested(buildingId));
      },
      icon: const Icon(PhosphorIconsRegular.mapTrifold, size: 18),
      label: const Text('Trace the floor plan'),
    );
    return compact
        ? button
        : Padding(
            padding: const EdgeInsets.only(top: AppDimens.space16),
            child: button,
          );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.buildingId, this.compact = false});

  final String buildingId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: () async {
        final bloc = context.read<FloorMapBloc>();
        await context.pushNamed(
          RouteNames.capture,
          pathParameters: {'id': buildingId},
        );
        // Reload on the way back: a contributor who has just walked the
        // building expects to see their walk on the map, and without this
        // they return to the "nobody has walked this yet" screen they left.
        if (!bloc.isClosed) bloc.add(FloorMapRequested(buildingId));
      },
      icon: const Icon(PhosphorIconsRegular.footprints, size: 18),
      label: const Text('Record a route'),
    );
    return compact
        ? button
        : Padding(
            padding: const EdgeInsets.only(top: AppDimens.space16),
            child: button,
          );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.textTheme.labelSmall?.color),
            const SizedBox(height: AppDimens.space16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppDimens.space8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}
