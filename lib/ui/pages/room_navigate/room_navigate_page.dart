import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/room_plan.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/room_navigate/bloc/room_navigate_cubit.dart';
import '../../../services/injection_container.dart';
import '../../widgets/responsive.dart';
import '../../widgets/room_picker_sheet.dart';
import '../../widgets/room_plan_view.dart';

/// Walking a mapped floor.
///
/// The screen that makes the room layer worth having. Everything up to here
/// produces a map; this is where somebody is actually guided along it, and
/// where the sentence the whole feature exists for — "the second door on your
/// left" — is finally spoken out loud.
///
/// It does not guide anybody itself. It assembles a `GuidanceSession` from the
/// plan and hands it to the same screen that follows a contributor's recorded
/// walk, so a room plan and a recording are followed by identical code. That
/// was the point of converting *toward* guidance rather than building a second
/// voice path.
class RoomNavigatePage extends StatelessWidget {
  const RoomNavigatePage({
    super.key,
    required this.buildingId,
    required this.floorId,
    this.destinationRoomId,
  });

  final String buildingId;
  final String floorId;

  /// Set when the user arrived by tapping a room on the building screen, so
  /// the route opens planned to it instead of asking them to say it twice.
  final String? destinationRoomId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => RoomNavigateCubit(getIt(), getIt())
      ..load(
        buildingId: buildingId,
        floorId: floorId,
        destinationRoomId: destinationRoomId,
      ),
    child: const RoomNavigateView(),
  );
}

/// The screen itself, given a cubit already in the tree — so it can be tested
/// against a mock repository.
class RoomNavigateView extends StatelessWidget {
  const RoomNavigateView({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RoomNavigateCubit, RoomNavigateState>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(PhosphorIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
            title: const Text('Where to?'),
          ),
          body: switch (state.status) {
            RoomNavigateStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            RoomNavigateStatus.empty => _Empty(state: state),
            RoomNavigateStatus.ready => const _Navigate(),
          },
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state});

  final RoomNavigateState state;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppDimens.space24),
      child: Text(
        state.error ??
            'This floor needs at least two rooms before anywhere can be '
                'navigated to. Map it first.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}

class _Navigate extends StatelessWidget {
  const _Navigate();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RoomNavigateCubit>();
    final state = context.watch<RoomNavigateCubit>().state;

    return Column(
      children: [
        Expanded(
          child: RoomPlanView(
            plan: state.plan!,
            route: state.route,
            highlightedRoomId: state.fromRoomId,
            // Tapping the map is the quicker way to pick a destination than
            // hunting a dropdown, and it is how a sighted contributor checks
            // the plan against the building.
            onRoomTap: cubit.selectTo,
          ),
        ),
        _Controls(cubit: cubit, state: state),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.cubit, required this.state});

  final RoomNavigateCubit cubit;
  final RoomNavigateState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: Responsive.pagePadding(
          context,
          top: AppDimens.space16,
          bottom: AppDimens.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _RoomPicker(
                    label: 'From',
                    value: state.fromRoomId,
                    rooms: state.origins,
                    onChanged: cubit.selectFrom,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space4,
                  ),
                  child: IconButton(
                    tooltip: 'Swap start and destination',
                    icon: const Icon(PhosphorIcons.arrowsLeftRight, size: 20),
                    onPressed: cubit.reverse,
                  ),
                ),
                Expanded(
                  child: _RoomPicker(
                    label: 'To',
                    value: state.toRoomId,
                    rooms: state.destinations,
                    onChanged: cubit.selectTo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space12),
            if (state.isUnreachable)
              Text(
                'No route between those two. They are on the map and nothing '
                'joins them — a door is missing.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                ),
              )
            else ...[
              if (!state.ordinalsAreSafe)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.space8),
                  child: Text(
                    // Said plainly rather than hidden: the route is walkable,
                    // it simply will not name which door, and a user should
                    // know that is why.
                    'Door counts on this route are incomplete, so it will not '
                    'say which door — only where to walk.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              // The instructions in full, before setting off. Guidance speaks
              // them one at a time; a contributor checking a floor they mapped
              // needs to read the lot against the building.
              //
              // One semantics node for the whole route rather than one per
              // line. This is the screen a blind user meets before setting
              // off, and swiping through six separate unlabelled fragments to
              // assemble the route in their head is not how anybody wants to
              // hear directions — they want the route, once, as a sentence.
              Semantics(
                label: state.preview.isEmpty
                    ? ''
                    : 'The route, ${state.preview.length} '
                          '${state.preview.length == 1 ? 'step' : 'steps'}. '
                          '${state.preview.map((i) => i.text).join(' ')}',
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final instruction in state.preview.take(6))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '· ${instruction.text}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      if (state.preview.length > 6)
                        Text(
                          '…and ${state.preview.length - 6} more',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            // Measuring a step, offered where it changes something.
            //
            // This lived in Profile as a settings row, which asked for it
            // before the user had walked anywhere and had any reason to care.
            // Here the route is drawn, the floor has a scale, and the distance
            // about to be spoken is a generic adult's rather than theirs.
            if (state.shouldOfferStride)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.space8),
                child: _StridePrompt(cubit: cubit),
              ),
            // Said here because this is the last moment it can be acted on,
            // and because the failure it warns about is invisible: a plan with
            // no scale routes correctly, speaks its turns correctly, and puts
            // an arrow on screen that is dead reckoning from whichever way the
            // phone happened to be held. Nothing on the walk looks wrong.
            if (state.hasRoute && state.plan?.isMetric == false)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.space8),
                child: Text(
                  'This floor has no scale, so the AR arrow cannot be laid '
                  'into the building and distances will not be spoken. Set a '
                  'scale in Trace rooms to fix it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),
            const SizedBox(height: AppDimens.space12),
            FilledButton.icon(
              onPressed: state.hasRoute
                  ? () {
                      final session = cubit.sessionFor();
                      if (session == null) return;
                      context.pushNamed(RouteNames.guidance, extra: session);
                    }
                  : null,
              icon: const Icon(PhosphorIcons.navigationArrow),
              label: const Text('Start guidance'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Distances are estimated" — and the one tap that fixes it.
///
/// Deliberately not a warning colour. Nothing is wrong: the route is correct
/// and walkable, and the fallback stride is a real anthropometric average. It
/// is simply not *this* walker's, and every leg is divided through it.
class _StridePrompt extends StatelessWidget {
  const _StridePrompt({required this.cubit});

  final RoomNavigateCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label:
          'Distances are estimated from an average step. '
          'Measure your own step.',
      child: ExcludeSemantics(
        child: Material(
          color: isDark
              ? AppColors.coral.withValues(alpha: 0.14)
              : AppColors.coralSoft,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
            onTap: () async {
              await context.pushNamed(RouteNames.strideCalibration);
              // Straight back to a screen that no longer asks.
              await cubit.refreshStride();
            },
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.space12),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsFill.ruler,
                    size: 18,
                    color: AppColors.coral,
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: Text(
                      'Distances use an average step. Measure yours to make '
                      'them accurate.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? theme.colorScheme.onSurface
                            : AppColors.ink,
                      ),
                    ),
                  ),
                  const Icon(
                    PhosphorIconsRegular.caretRight,
                    size: 16,
                    color: AppColors.coral,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One end of the walk, as a field that opens a proper picker.
///
/// This was a `DropdownButtonFormField`. On a floor with forty rooms that
/// opened a floating menu nearly the height of the screen — unsearchable, every
/// name clipped to half a row's width, and close to unusable with a screen
/// reader, which is the audience this screen is for. The sheet behind it can be
/// searched, groups rooms by what they are, and gives each one a full-width
/// target.
class _RoomPicker extends StatelessWidget {
  const _RoomPicker({
    required this.label,
    required this.value,
    required this.rooms,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Room> rooms;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = rooms.where((room) => room.id == value).firstOrNull;
    final name = chosen?.spokenName ?? 'Choose';

    return Semantics(
      button: true,
      label: '$label: $name. Tap to change.',
      child: ExcludeSemantics(
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
            onTap: rooms.isEmpty
                ? null
                : () async {
                    final picked = await RoomPickerSheet.show(
                      context,
                      title: label == 'From' ? 'Start from' : 'Go to',
                      rooms: rooms,
                      selectedId: value,
                    );
                    if (picked != null) onChanged(picked);
                  },
            child: Container(
              // Never a fixed height: the room name is the one piece of text
              // here and it has to be allowed to wrap.
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space12,
                vertical: AppDimens.space8,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: theme.textTheme.labelSmall),
                        Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: chosen == null
                                ? theme.textTheme.bodyMedium?.color
                                : theme.colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    PhosphorIconsRegular.caretDown,
                    size: 16,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
