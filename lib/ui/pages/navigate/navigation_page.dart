import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/routing/bloc/floor_plan_bloc.dart';
import '../../../services/injection_container.dart';
import '../../../services/mapping/route_planner.dart';
import '../../widgets/floor_plan_painter.dart';

/// Turn-by-turn navigation view (Figma 7:265), over the real landmark graph.
///
/// The plan drawn here is derived from recorded walks, not sensors: somebody
/// walked the building reading its signage, and the corridors are where their
/// steps say they are. See `docs/stream-a-plan.md`.
class NavigationPage extends StatelessWidget {
  const NavigationPage({super.key, this.building, this.destinationRoomId});

  final Building? building;

  /// Set when the user tapped a room on the building detail screen; the route
  /// is then planned before the map is first drawn.
  final String? destinationRoomId;

  @override
  Widget build(BuildContext context) {
    final buildingId = building?.id;

    return BlocProvider(
      create: (_) {
        final bloc = getIt<FloorPlanBloc>();
        if (buildingId != null) {
          bloc.add(
            FloorPlanStarted(buildingId, destinationRoomId: destinationRoomId),
          );
        }
        return bloc;
      },
      child: _NavigationView(buildingName: building?.name ?? 'Building'),
    );
  }
}

class _NavigationView extends StatelessWidget {
  const _NavigationView({required this.buildingName});

  final String buildingName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Arrival is the one moment guidance has to land without being looked
        // at or listened for, so it is also felt.
        child: BlocListener<FloorPlanBloc, FloorPlanState>(
          listenWhen: (before, after) => !before.hasArrived && after.hasArrived,
          listener: (_, __) => HapticFeedback.heavyImpact(),
          child: BlocBuilder<FloorPlanBloc, FloorPlanState>(
            builder: (context, state) {
              return Column(
                children: [
                  _Header(buildingName: buildingName, state: state),
                  Expanded(child: _PlanArea(state: state)),
                  // Slides up when a route appears rather than shoving the map
                  // aside in one frame.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: state.hasRoute
                        ? _InstructionCard(state: state)
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The circular control used across this screen's chrome.
///
/// Sized to 48dp, which is the smallest target Material and WCAG 2.5.5 accept
/// — and this app's users are the ones least able to spend a tap correcting an
/// aim. The icon inside stays small; it is the touch area that grows.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Merged, because the label and the tap action live on different widgets:
    // left unmerged a screen reader reads "Back" and then finds a separate,
    // nameless button to press.
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: theme.brightness == Brightness.dark
              ? AppColors.darkElevated
              : AppColors.white,
          shape: const CircleBorder(),
          elevation: 1,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                icon,
                size: 20,
                color: color ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.buildingName, required this.state});

  final String buildingName;
  final FloorPlanState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final floorLabel = state.floors
        .where((f) => f.id == state.activeFloorId)
        .map((f) => f.label == 'G' ? 'Ground floor' : 'Floor ${f.label}')
        .firstOrNull;
    final destination = state.route?.steps.isEmpty ?? true
        ? null
        : state.landmarks[state.route!.steps.last.toLandmarkId]?.displayName;

    final subtitle = [
      if (floorLabel != null) floorLabel,
      if (destination != null) 'heading to $destination',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space8,
      ),
      child: Row(
        children: [
          _CircleButton(
            icon: PhosphorIconsRegular.caretLeft,
            label: 'Back',
            onTap: () => context.pop(),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            // One node, one sentence: a screen reader should say "KNUST
            // Library, Floor 2, heading to Study Room 2B" rather than making
            // the user swipe through three fragments.
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    buildingName,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
          // Lives in the header rather than floating over the plan: an overlay
          // control makes the landmarks underneath it untappable, and those
          // are how the user says where they are.
          if (state.status == FloorPlanStatus.success &&
              state.emptyReason != FloorPlanEmptyReason.noRoutes)
            _DestinationButton(state: state),
        ],
      ),
    );
  }
}

/// The plan, plus whatever has to be said instead of it.
class _PlanArea extends StatelessWidget {
  const _PlanArea({required this.state});

  final FloorPlanState state;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case FloorPlanStatus.initial:
      case FloorPlanStatus.loading:
        // A bare spinner is silent to a screen reader, which then reports an
        // empty screen while the map is on its way.
        return Semantics(
          liveRegion: true,
          label: 'Loading the floor plan',
          child: const Center(child: CircularProgressIndicator()),
        );

      case FloorPlanStatus.failure:
        return _Message(
          icon: PhosphorIconsRegular.cloudSlash,
          title: 'Could not load this map',
          body: state.error ?? 'Please try again.',
        );

      case FloorPlanStatus.success:
        if (state.emptyReason == FloorPlanEmptyReason.noRoutes) {
          return const _Message(
            icon: PhosphorIconsRegular.mapTrifold,
            title: 'Nobody has walked this building yet',
            // The honest framing for a crowdsourced map: not broken, unmapped.
            body: 'Record a route and it will appear here for everyone else.',
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: FloorPlanView(
                nodes: state.visibleNodes,
                edges: state.visibleEdges,
                landmarks: state.landmarks,
                route: state.route,
                currentLandmarkId: state.currentLandmarkId,
                // In the field this claim comes from OCR reading the sign.
                // Tapping is how a contributor at a desk, or anyone whose
                // camera cannot see the sign, says the same thing.
                onLandmarkTap: (id) {
                  // The dot is 6px and the finger is not, so the tap needs to
                  // confirm itself: without this, a miss and a hit feel the
                  // same until the plan redraws.
                  HapticFeedback.selectionClick();
                  context
                      .read<FloorPlanBloc>()
                      .add(FloorPlanPositionChanged(id));
                },
              ),
            ),
            if (state.floors.length > 1)
              Positioned(
                top: AppDimens.space12,
                right: AppDimens.space12,
                child: _FloorSwitcher(state: state),
              ),
            if (state.emptyReason ==
                FloorPlanEmptyReason.unreachableDestination)
              const Positioned(
                left: AppDimens.space12,
                right: AppDimens.space12,
                bottom: AppDimens.space12,
                child: _Notice(
                  'No recorded walk reaches that room yet.',
                ),
              ),
            if (state.route?.isPlanned ?? false)
              Positioned(
                left: AppDimens.space12,
                bottom: AppDimens.space12,
                child: _Badge(
                  // Spliced from other people's walks. Saying so is the point:
                  // nobody has verified this exact journey end to end.
                  label:
                      'Estimated route · ${state.route!.totalDistanceM.round()} m',
                ),
              ),
          ],
        );
    }
  }
}

/// Opens the destination list, and clears the current route.
///
/// This is the only way to reach the room-to-room case from the UI, and that
/// case is the claim the project defends: a journey assembled from walks
/// nobody made end to end. Without it the app can only replay recordings.
class _DestinationButton extends StatelessWidget {
  const _DestinationButton({required this.state});

  final FloorPlanState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<FloorPlanBloc>();

    // Icon-only. A labelled pill crowded the building name down to "KNU…" on a
    // 360dp screen, and the destination is already named in the subtitle
    // beneath it. Semantics carries the label for screen readers, which is the
    // audience that matters most here.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.hasRoute) ...[
          _CircleButton(
            icon: PhosphorIconsRegular.x,
            label: 'Clear route',
            color: theme.textTheme.labelSmall?.color,
            onTap: () => bloc.add(const FloorPlanRouteCleared()),
          ),
          const SizedBox(width: AppDimens.space8),
        ],
        _CircleButton(
          icon: PhosphorIconsRegular.magnifyingGlass,
          label: state.hasRoute ? 'Change destination' : 'Choose a destination',
          color: AppColors.coral,
          onTap: () => _pickDestination(context, bloc),
        ),
      ],
    );
  }

  Future<void> _pickDestination(
    BuildContext context,
    FloorPlanBloc bloc,
  ) async {
    final roomId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      // A building's room list is long. Left at the default height it is a
      // stub of a list with the rest unreachable.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      builder: (_) => _DestinationSheet(state: state),
    );
    if (roomId != null) {
      HapticFeedback.mediumImpact();
      bloc.add(FloorPlanDestinationSelected(roomId));
    }
  }
}

class _DestinationSheet extends StatelessWidget {
  const _DestinationSheet({required this.state});

  final FloorPlanState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final here = state.currentLandmarkId;
    final from = here == null ? null : state.landmarks[here]?.displayName;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AppDimens.space16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.space16,
              0,
              AppDimens.space16,
              AppDimens.space8,
            ),
            child: Text(
              from == null ? 'Choose a destination' : 'From $from',
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final floor in state.floors) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.space16,
                AppDimens.space8,
                AppDimens.space16,
                4,
              ),
              child: Text(
                floor.label == 'G' ? 'Ground floor' : 'Floor ${floor.label}',
                style: theme.textTheme.labelSmall,
              ),
            ),
            for (final room in floor.rooms)
              Builder(
                builder: (context) {
                  // A room nobody has recorded a landmark at cannot be routed
                  // to. Greying it out is more honest than accepting the tap
                  // and then explaining why nothing happened.
                  final reachable = state.landmarks.values.any(
                    (l) => l.roomId == room.id,
                  );

                  return Semantics(
                    button: reachable,
                    enabled: reachable,
                    // Grey is invisible to a screen reader, so the reason has
                    // to be in words or the room just looks broken.
                    label: reachable
                        ? room.name
                        : '${room.name}, no recorded walk reaches this room '
                            'yet',
                    child: ExcludeSemantics(
                      child: ListTile(
                        title: Text(room.name),
                        enabled: reachable,
                        trailing: const Icon(
                          PhosphorIconsRegular.caretRight,
                          size: 16,
                        ),
                        onTap: () => Navigator.of(context).pop(room.id),
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _FloorSwitcher extends StatelessWidget {
  const _FloorSwitcher({required this.state});

  final FloorPlanState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.darkElevated : AppColors.white,
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final floor in state.floors)
              Builder(
                builder: (context) {
                  final selected = floor.id == state.activeFloorId;
                  final name = floor.label == 'G'
                      ? 'Ground floor'
                      : 'Floor ${floor.label}';

                  return Semantics(
                    selected: selected,
                    button: true,
                    label: name,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context
                            .read<FloorPlanBloc>()
                            .add(FloorPlanFloorSelected(floor.id));
                      },
                      // The fill crossfades instead of snapping, so the eye
                      // can follow which floor it moved to.
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              selected ? AppColors.coral : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: theme.textTheme.labelLarge!.copyWith(
                            color: selected
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                          ),
                          child: Text(floor.label),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.state});

  final FloorPlanState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final route = state.route!;
    final step = state.currentStep;
    if (step == null) return const SizedBox.shrink();

    final arrived = state.hasArrived;
    final index = route.steps.indexOf(step);
    final progress =
        arrived ? 1.0 : (index + 1) / route.steps.length;
    final remaining = arrived
        ? 0.0
        : route.steps.skip(index).fold<double>(0, (sum, s) => sum + s.distanceM);

    return Container(
      margin: const EdgeInsets.all(AppDimens.space12),
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.white,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          // Read as one sentence, and announced only when the app's own voice
          // is muted — with both on, TalkBack and the TTS engine talk over
          // each other saying the same thing.
          MergeSemantics(
            child: Semantics(
              liveRegion: !state.voiceOn,
              label: state.spokenGuidance,
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    _TurnBadge(
                      icon: arrived
                          ? PhosphorIconsBold.checkCircle
                          : _turnIcon(step.turnDeg),
                    ),
                    const SizedBox(width: AppDimens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            arrived
                                ? 'Arrived'
                                : 'Leg ${index + 1} of ${route.steps.length}',
                            style: theme.textTheme.labelSmall,
                          ),
                          // Legs cross-fade into each other; the text changing
                          // under the eye is how the user notices the route
                          // moved on without being told twice.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOut,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.25),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: Text(
                              // The contributor's own sentence where it still
                              // applies, otherwise one rebuilt for the way
                              // round being walked.
                              arrived
                                  ? state.landmarks[step.toLandmarkId]
                                          ?.displayName ??
                                      'You have arrived'
                                  : step.instruction,
                              key: ValueKey(state.guidanceKey),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!arrived) ...[
                      const SizedBox(width: AppDimens.space8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${step.distanceM.round()} m',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: AppColors.coral),
                          ),
                          Text(
                            '${remaining.round()} m to go',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space16),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  // Animated between values rather than jumping: the bar is
                  // the only thing on screen showing the journey shortening.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      backgroundColor: theme.colorScheme.surface,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppColors.coral),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.space12),
              // Sits with the guidance it silences rather than up in the
              // header, where it would crowd the building name and be one more
              // thing between the user and the map.
              _VoiceButton(on: state.voiceOn),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _turnIcon(int turnDeg) => switch (turnDeg) {
        90 || 135 => PhosphorIconsBold.arrowBendUpRight,
        -90 || -135 => PhosphorIconsBold.arrowBendUpLeft,
        180 => PhosphorIconsBold.arrowUDownLeft,
        _ => PhosphorIconsBold.arrowUp,
      };
}

/// The coral disc carrying the turn arrow.
///
/// The arrow rotates into its new direction rather than being swapped out:
/// a left turn replaced instantly by a right turn is two unrelated pictures,
/// where a turning arrow is one instruction changing.
class _TurnBadge extends StatelessWidget {
  const _TurnBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.coral,
        shape: BoxShape.circle,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          icon,
          key: ValueKey(icon.codePoint),
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

/// Mutes and unmutes spoken guidance.
///
/// Deliberately not hidden behind a settings screen. The voice is the primary
/// output for the users this app is built for, and the secondary output for
/// everyone else walking a corridor without looking down — both need it
/// reachable in one tap.
class _VoiceButton extends StatelessWidget {
  const _VoiceButton({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
      child: Semantics(
        button: true,
        toggled: on,
        label: on ? 'Mute spoken directions' : 'Speak directions aloud',
        child: IconButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            context.read<FloorPlanBloc>().add(FloorPlanVoiceToggled(!on));
          },
          // The default IconButton target is already 48dp; stated here so a
          // later density change cannot quietly shrink it.
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(
            on
                ? PhosphorIconsRegular.speakerHigh
                : PhosphorIconsRegular.speakerSlash,
            size: 20,
            color: on ? AppColors.coral : theme.textTheme.labelSmall?.color,
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.textTheme.labelSmall?.color),
            const SizedBox(height: AppDimens.space16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.space8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space12,
      ),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? AppColors.darkElevated
            : AppColors.white,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? AppColors.coral.withValues(alpha: 0.16)
            : AppColors.coralSoft,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: AppColors.coral),
      ),
    );
  }
}
