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
  });

  final String buildingId;
  final String floorId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        RoomNavigateCubit(getIt())
          ..load(buildingId: buildingId, floorId: floorId),
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
        padding: const EdgeInsets.all(AppDimens.space16),
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
                IconButton(
                  tooltip: 'Swap',
                  icon: const Icon(PhosphorIcons.arrowsLeftRight),
                  onPressed: cubit.reverse,
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
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: rooms.any((room) => room.id == value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      for (final room in rooms)
        DropdownMenuItem(
          value: room.id,
          child: Text(room.spokenName, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (id) {
      if (id != null) onChanged(id);
    },
  );
}
