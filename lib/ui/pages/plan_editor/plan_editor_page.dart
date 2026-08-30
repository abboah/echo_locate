import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/room_plan.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/plan_editor/bloc/plan_editor_cubit.dart';
import '../../../services/injection_container.dart';
import '../../widgets/floor_picker.dart';
import '../../widgets/room_plan_palette.dart';
import '../../widgets/sheet_body.dart';
import '../../widgets/sheet_text_field.dart';
import '../../widgets/room_plan_view.dart';

/// Correcting a saved floor — floorplan spec §8.
///
/// Where a building too large for one AR session gets put back together. Each
/// session is captured in its own coordinate frame and arrives *parked* beside
/// the floor rather than placed on it; here somebody who can see the building
/// drags it where it belongs. The spec chooses that over pose-graph
/// optimisation deliberately — weeks of work against a few seconds of a
/// contributor's attention.
///
/// It is also the only place a saved plan can be fixed: a room traced twice, a
/// category picked wrongly, a door nobody tagged. A floor plan that cannot be
/// corrected is one that gets recaptured from scratch instead.
class PlanEditorPage extends StatelessWidget {
  const PlanEditorPage({
    super.key,
    required this.buildingId,
    required this.floorId,
  });

  final String buildingId;
  final String floorId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        PlanEditorCubit(getIt(), getIt())
          ..load(buildingId: buildingId, floorId: floorId),
    child: const PlanEditorView(),
  );
}

/// The screen itself, given a cubit already in the tree — so it can be tested
/// against a mock repository.
class PlanEditorView extends StatelessWidget {
  const PlanEditorView({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<PlanEditorCubit, PlanEditorState>(
        listenWhen: (before, after) =>
            before.error != after.error ||
            before.hint != after.hint ||
            before.status != after.status,
        listener: (context, state) {
          final message = state.error ?? state.hint;
          if (message != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: state.error != null ? AppColors.error : null,
                ),
              );
          }
          if (state.status == PlanEditorStatus.saved) context.pop();
        },
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(PhosphorIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
            title: const Text('Edit this floor'),
            actions: [
              if (state.status == PlanEditorStatus.ready)
                _ScaleMenu(
                  cubit: context.read<PlanEditorCubit>(),
                  state: state,
                ),
              TextButton(
                onPressed: state.isDirty
                    ? () => context.read<PlanEditorCubit>().save()
                    : null,
                child: const Text('Save'),
              ),
            ],
          ),
          body: Column(
            children: [
              if (state.floors.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.space16,
                    AppDimens.space8,
                    AppDimens.space16,
                    0,
                  ),
                  child: FloorPicker(
                    floors: state.floors,
                    selectedId: state.floorId,
                    onChanged: context.read<PlanEditorCubit>().changeFloor,
                  ),
                ),
              Expanded(
                child: switch (state.status) {
                  PlanEditorStatus.loading || PlanEditorStatus.saving =>
                    const Center(child: CircularProgressIndicator()),
                  PlanEditorStatus.empty => const _Empty(),
                  _ => const _Editor(),
                },
              ),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppDimens.space24),
      child: Text(
        'Nothing has been captured on this floor yet. Scan it or trace it '
        'from a photo first.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}

class _Editor extends StatelessWidget {
  const _Editor();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PlanEditorCubit>();
    final state = context.watch<PlanEditorCubit>().state;

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          if (state.hasWings) _WingPicker(cubit: cubit, state: state),
          Expanded(
            child: RoomPlanView(
              plan: state.plan,
              highlightedRoomId: state.selectedRoomId ?? state.editingRoomId,
              // While a shape is open, a tap on the plan picks a handle rather
              // than opening another room's sheet — otherwise every miss throws
              // the contributor out of the edit they are halfway through.
              onRoomTap: state.editingRoomId != null || state.settingScale
                  ? null
                  : (id) => _editRoom(context, cubit, id),
              // And while the scale is being measured, a tap is a position
              // rather than a room. The two ends of a known span are a
              // corridor's ends or a doorway's jambs, neither of which is a
              // room's middle.
              onPlanTap: state.settingScale ? cubit.tapScalePoint : null,
              markedPoints: state.scalePoints,
              editingRoomId: state.editingRoomId,
              selectedPoint: state.selectedPoint,
              onPointSelected: cubit.selectPoint,
              onPointMoved: (index, to) =>
                  cubit.movePoint(state.editingRoomId!, index, to),
            ),
          ),
          // The controls take the height they need, up to half the screen, and
          // scroll past that.
          //
          // They used to be plain children of this column, which meant their
          // combined natural height had to fit whatever was left after the
          // plan — and with a wing selected, a problem list, and the floor
          // actions, it already very nearly did not. Every addition was one
          // overflow stripe away from being a layout bug, on the screen whose
          // job is fixing other people's mistakes.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.settingScale)
                    _ScaleControls(cubit: cubit, state: state)
                  else if (state.editingRoomId != null)
                    _ShapeControls(cubit: cubit, state: state)
                  else ...[
                    _Problems(cubit: cubit, state: state),
                    _FloorControls(cubit: cubit, state: state),
                  ],
                  if (state.hasWings &&
                      state.selectedWingId != null &&
                      !state.settingScale)
                    _WingControls(cubit: cubit, state: state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Controls for the shape currently open for editing.
///
/// Replaces the problem list and floor actions rather than sitting under them:
/// while somebody is reshaping one corridor, "three rooms share a wall with no
/// door" is not what they are doing, and a "Square up floor" button one thumb
/// away from "Remove point" is an accident waiting.
class _ShapeControls extends StatelessWidget {
  const _ShapeControls({required this.cubit, required this.state});

  final PlanEditorCubit cubit;
  final PlanEditorState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = state.plan.roomOf(state.editingRoomId!);
    if (room == null) return const SizedBox.shrink();

    final isCorridor = room.hasSpine;
    final index = state.selectedPoint;
    final points = isCorridor ? room.spine.length : room.corners.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageGutter,
        AppDimens.space8,
        AppDimens.pageGutter,
        AppDimens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  index == null
                      ? 'Editing ${room.displayName} — $points '
                            '${isCorridor ? "points" : "corners"}. '
                            'Drag one, or tap it to remove or trim.'
                      : 'Point ${index + 1} of $points selected.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => cubit.editShape(null),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space8),
          Wrap(
            spacing: AppDimens.space8,
            runSpacing: AppDimens.space8,
            children: [
              OutlinedButton.icon(
                onPressed: index == null
                    ? null
                    : () => cubit.deletePoint(room.id, index),
                icon: const Icon(PhosphorIcons.minusCircle, size: 18),
                label: const Text('Remove point'),
              ),
              if (isCorridor) ...[
                // The fix for a corridor traced past the end of the building.
                OutlinedButton.icon(
                  onPressed: index == null
                      ? null
                      : () => cubit.trimAfter(room.id, index),
                  icon: const Icon(PhosphorIcons.scissors, size: 18),
                  label: const Text('Trim after'),
                ),
                OutlinedButton.icon(
                  onPressed: index == null
                      ? null
                      : () => cubit.trimBefore(room.id, index),
                  icon: const Icon(PhosphorIcons.scissors, size: 18),
                  label: const Text('Trim before'),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: index == null
                      ? null
                      : () => cubit.addCorner(room.id, index),
                  icon: const Icon(PhosphorIcons.plusCircle, size: 18),
                  label: const Text('Add corner'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Floor-wide geometry actions.
///
/// Separate from [_WingControls] because the scope is different and mixing them
/// would be a trap: "Square up" there rotates the *selected wing*, this squares
/// every room on the floor. Outside the wing panel, so it is reachable on the
/// floors that have no wings at all — which is every traced floor.
class _FloorControls extends StatelessWidget {
  const _FloorControls({required this.cubit, required this.state});

  final PlanEditorCubit cubit;
  final PlanEditorState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageGutter,
        AppDimens.space8,
        AppDimens.pageGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Each room was squared against its own walls as you traced it, so '
            'no two quite agree. This squares the whole floor at once.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppDimens.space8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: cubit.squareUpFloor,
                  icon: const Icon(PhosphorIcons.gridFour),
                  label: const Text('Square up floor'),
                ),
              ),
              const SizedBox(width: AppDimens.space8),
              Expanded(
                child: OutlinedButton.icon(
                  // Only offered once the geometry actually differs from what
                  // was traced, so it never reads as a way to undo something
                  // that has not happened.
                  onPressed: state.isDirty ? cubit.undoSquaring : null,
                  icon: const Icon(PhosphorIcons.arrowUUpLeft),
                  label: const Text('Undo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The scale menu, in the app bar.
///
/// Up here rather than under the floor controls, for the reason the tracing
/// screen puts it in a menu too: the controls column already carries the
/// squaring buttons, the problem list and the wing nudges, and on a phone it
/// is one addition away from overflowing. What the floor's scale *is* still
/// belongs on screen — [_Problems] carries that, and only when it is missing.
class _ScaleMenu extends StatelessWidget {
  const _ScaleMenu({required this.cubit, required this.state});

  final PlanEditorCubit cubit;
  final PlanEditorState state;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_ScaleAction>(
    icon: const Icon(PhosphorIcons.ruler),
    tooltip: 'Scale',
    onSelected: (action) => switch (action) {
      _ScaleAction.measure => cubit.setScaleMode(on: true),
      _ScaleAction.clear => cubit.clearScale(),
    },
    itemBuilder: (context) => [
      PopupMenuItem(
        value: _ScaleAction.measure,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(PhosphorIcons.ruler),
          title: Text(state.hasScale ? 'Change the scale' : 'Set the scale'),
          subtitle: Text(
            state.hasScale
                // The floor's own width, not the raw metres-per-unit: nobody
                // knows what a plan unit is, so every way of showing them one
                // is a number they cannot check. How wide the building is,
                // they can.
                ? 'Set — this floor is about '
                      '${(state.plan.bounds.longestSide * state.plan.metresPerUnit!).round()} m across'
                : 'Not set — distances cannot be spoken',
          ),
        ),
      ),
      if (state.hasScale)
        const PopupMenuItem(
          value: _ScaleAction.clear,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(PhosphorIcons.x),
            title: Text('Clear the scale'),
          ),
        ),
    ],
  );
}

enum _ScaleAction { measure, clear }

/// The two-tap measurement itself.
///
/// Replaces the problem list and the floor actions while it is open, for the
/// same reason [_ShapeControls] does: a tap on the plan means something
/// different in here, and leaving the controls that assume the other meaning
/// on screen is how somebody squares up a floor they meant to measure.
class _ScaleControls extends StatelessWidget {
  const _ScaleControls({required this.cubit, required this.state});

  final PlanEditorCubit cubit;
  final PlanEditorState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placed = state.scalePoints.length;
    final underCurrent = state.spanUnderCurrentScale;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageGutter,
          AppDimens.space4,
          AppDimens.pageGutter,
          AppDimens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    switch (placed) {
                      0 =>
                        'Mark two points you know the real distance between — '
                            'the ends of a corridor, or the sides of one '
                            'doorway.',
                      1 => 'One end placed. Tap the other.',
                      _ => 'Both ends placed. Say how far apart they really '
                          'are.',
                    },
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => cubit.setScaleMode(on: false),
                  child: const Text('Done'),
                ),
              ],
            ),
            if (underCurrent != null)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.space4),
                child: Text(
                  // The check that catches a scale set off the wrong pair of
                  // points: if the floor already claims a scale, this span
                  // should measure roughly what the contributor can see it is.
                  'Under the current scale that span is '
                  '${underCurrent.toStringAsFixed(1)} m.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: AppDimens.space4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: placed == 0
                        ? null
                        : () => cubit.setScaleMode(on: true),
                    icon: const Icon(PhosphorIcons.arrowUUpLeft, size: 18),
                    label: const Text('Start again'),
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: placed < 2
                        ? null
                        : () => _askForDistance(context, cubit),
                    icon: const Icon(PhosphorIcons.ruler, size: 18),
                    label: const Text('Set distance'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks what the marked span really measures.
///
/// The same question the tracing screen asks, worded the same way: a
/// contributor who has set a scale while tracing should recognise this, and
/// the hints about doorways and ceiling tiles are the part that makes it
/// answerable without a tape measure.
Future<void> _askForDistance(
  BuildContext context,
  PlanEditorCubit cubit,
) async {
  var metres = '';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // The field brings a keyboard up under the dialog, which then needs the
      // height its content asks for.
      scrollable: true,
      title: const Text('How far apart?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The real-world distance between the two points you marked. This '
            'sets the scale for the whole floor.',
          ),
          const SizedBox(height: AppDimens.space12),
          SheetTextField(
            label: 'Metres',
            hint: '10.5',
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) => metres = value,
          ),
          const SizedBox(height: AppDimens.space12),
          Text(
            'No tape measure? A single doorway is about 0.9 m, a standard '
            'ceiling tile 0.6 m, and a scale bar printed on the board is best '
            'of all.',
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Set scale'),
        ),
      ],
    ),
  );

  final parsed = double.tryParse(metres.trim());
  if ((confirmed ?? false) && parsed != null) cubit.declareScale(parsed);
}

class _WingPicker extends StatelessWidget {
  const _WingPicker({required this.cubit, required this.state});

  final PlanEditorCubit cubit;
  final PlanEditorState state;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(
      horizontal: AppDimens.space16,
      vertical: AppDimens.space8,
    ),
    child: Row(
      children: [
        for (final wingId in state.plan.wingIds)
          Padding(
            padding: const EdgeInsets.only(right: AppDimens.space8),
            child: ChoiceChip(
              label: Text(
                // Numbered by capture order, which is the order somebody
                // walked them and therefore how they remember them.
                'Wing ${state.plan.wingIds.indexOf(wingId) + 1}',
              ),
              selected: state.selectedWingId == wingId,
              onSelected: (selected) =>
                  cubit.selectWing(selected ? wingId : null),
            ),
          ),
      ],
    ),
  );
}

/// Drag, rotate, square up, put back.
///
/// Nudge buttons rather than a free drag on the canvas: the plan is already
/// pan-and-tap for selecting rooms, and a gesture that means "move the wing" on
/// top of one that means "select a room" is how a contributor moves a wing by
/// accident and cannot tell what changed.
class _WingControls extends StatelessWidget {
  const _WingControls({required this.cubit, required this.state});

  final PlanEditorCubit cubit;
  final PlanEditorState state;

  /// One nudge, as a fraction of the floor's own extent.
  ///
  /// Scaled rather than fixed because a captured plan is in metres and a traced
  /// one in image fractions — a 0.5 step would be half a metre in one and half
  /// the building in the other.
  double get _step {
    final span = state.plan.bounds.longestSide;
    return span <= 0 ? 1 : span / 100;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wingId = state.selectedWingId!;
    final canSnap = state.snapCorrectionFor(wingId) != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Move Wing ${state.plan.wingIds.indexOf(wingId) + 1} into place',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: AppDimens.space8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Nudge(
                  icon: PhosphorIcons.arrowLeft,
                  tooltip: 'West',
                  onPressed: () => cubit.nudgeWing(Offset(-_step, 0)),
                ),
                _Nudge(
                  icon: PhosphorIcons.arrowUp,
                  tooltip: 'North',
                  onPressed: () => cubit.nudgeWing(Offset(0, _step)),
                ),
                _Nudge(
                  icon: PhosphorIcons.arrowDown,
                  tooltip: 'South',
                  onPressed: () => cubit.nudgeWing(Offset(0, -_step)),
                ),
                _Nudge(
                  icon: PhosphorIcons.arrowRight,
                  tooltip: 'East',
                  onPressed: () => cubit.nudgeWing(Offset(_step, 0)),
                ),
                _Nudge(
                  icon: PhosphorIcons.arrowCounterClockwise,
                  tooltip: 'Rotate left',
                  onPressed: () => cubit.rotateWing(
                    PlanEditorCubit.rotateStepDeg * math.pi / 180,
                  ),
                ),
                _Nudge(
                  icon: PhosphorIcons.arrowClockwise,
                  tooltip: 'Rotate right',
                  onPressed: () => cubit.rotateWing(
                    -PlanEditorCubit.rotateStepDeg * math.pi / 180,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canSnap ? cubit.snapWing : null,
                    icon: const Icon(PhosphorIcons.magnet),
                    label: const Text('Square up'),
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: cubit.resetWing,
                    icon: const Icon(PhosphorIcons.arrowUUpLeft),
                    label: const Text('Reset'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space8),
            // Its own row, and worded as a statement about the building rather
            // than an operation on coordinates: somebody reaching for this has
            // found their work sitting in a field beside the floor and wants to
            // say "that is not a separate wing", not to compute a translation.
            OutlinedButton.icon(
              onPressed: cubit.unparkWing,
              icon: const Icon(PhosphorIcons.arrowsInLineHorizontal),
              label: const Text('Not a separate wing — put it back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nudge extends StatelessWidget {
  const _Nudge({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    icon: Icon(icon),
    tooltip: tooltip,
    onPressed: onPressed,
  );
}

/// What is still wrong with the floor, and how to fix it.
class _Problems extends StatelessWidget {
  const _Problems({required this.cubit, required this.state});

  final PlanEditorCubit cubit;
  final PlanEditorState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stranded = state.strandedRooms;
    final missing = state.missingConnections;

    if (stranded.isEmpty && missing.isEmpty && state.hasScale) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!state.hasScale)
            Row(
              children: [
                Expanded(
                  child: Text(
                    // Listed with the problems because that is what it is, and
                    // it is the one nothing else on the screen would reveal: a
                    // floor with no scale draws perfectly and routes perfectly,
                    // and then cannot tell anybody how far anything is or put
                    // an arrow on the floor pointing at it.
                    'This floor has no scale. Distances cannot be spoken and '
                    'the AR arrow cannot follow it.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => cubit.setScaleMode(on: true),
                  child: const Text('Set scale'),
                ),
              ],
            ),
          if (stranded.isNotEmpty)
            Text(
              // The point most easily missed after a good alignment: two wings
              // can sit perfectly side by side and route as badly as if they
              // were miles apart. Geometry is not connectivity.
              '${stranded.length} room${stranded.length == 1 ? "" : "s"} cannot '
              'be walked to. Lining wings up does not join them — they need a '
              'door.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          for (final pair in missing.take(3))
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.space4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_name(pair.roomA)} and ${_name(pair.roomB)} share a '
                      'wall with no door.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        cubit.addDoorBetween(pair.roomA, pair.roomB, pair.near),
                    child: const Text('Add door'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _name(String roomId) =>
      state.plan.roomOf(roomId)?.spokenName ?? roomId;
}

/// Change what a room is, rename it, or remove it.
Future<void> _editRoom(
  BuildContext context,
  PlanEditorCubit cubit,
  String roomId,
) async {
  cubit.selectRoom(roomId);
  final room = cubit.state.plan.roomOf(roomId);
  if (room == null) return;

  var category = room.category;
  var label = room.label ?? "";

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SheetBody(
      child: StatefulBuilder(
        builder: (builderContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              room.displayName,
              style: Theme.of(builderContext).textTheme.titleMedium,
            ),
            const SizedBox(height: AppDimens.space12),
            Wrap(
              spacing: AppDimens.space8,
              runSpacing: AppDimens.space8,
              children: [
                for (final option in RoomCategory.values)
                  ChoiceChip(
                    label: Text(RoomPalette.labelFor(option)),
                    selected: category == option,
                    onSelected: (_) => setSheetState(() => category = option),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.space12),
            SheetTextField(
              label: "Name on the door",
              initial: label,
              textCapitalization: TextCapitalization.words,
              onChanged: (value) => label = value,
            ),
            const SizedBox(height: AppDimens.space16),
            FilledButton(
              onPressed: () {
                cubit.editRoom(roomId, category: category, label: label);
                Navigator.of(sheetContext).pop();
              },
              child: const Text('Save changes'),
            ),
            // Reshaping happens on the plan, not in a sheet, so this closes
            // and hands the floor back with the handles showing.
            OutlinedButton.icon(
              onPressed: () {
                cubit.editShape(roomId);
                Navigator.of(sheetContext).pop();
              },
              icon: const Icon(PhosphorIcons.polygon, size: 18),
              label: const Text('Edit its shape'),
            ),
            TextButton(
              onPressed: () {
                cubit.deleteRoom(roomId);
                Navigator.of(sheetContext).pop();
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete this room'),
            ),
          ],
        ),
      ),
    ),
  );
}
