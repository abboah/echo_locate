import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/room_plan.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/room_trace/bloc/room_trace_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/room_plan_palette.dart';
import '../../widgets/sheet_body.dart';
import '../../widgets/sheet_text_field.dart';
import '../../widgets/room_plan_view.dart';
import '../../widgets/room_trace_painter.dart';
import '../../widgets/zoomable_plan.dart';

/// Tracing room shapes off a photographed wall board — floorplan spec §9.
///
/// The screen the whole room layer was waiting for: everything downstream of it
/// — cleanup, the nav graph, door-counted directions, the schematic renderer —
/// is built and tested, and until now had no way to be given a real building.
/// Nothing here needs ARCore, which is the point: it runs on the phone the team
/// actually has.
class RoomTracePage extends StatelessWidget {
  const RoomTracePage({super.key, required this.buildingId, this.floorId = ''});

  final String buildingId;

  /// Which floor to trace. Empty falls back to the building’s first.
  final String floorId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    // From the service locator, not `context.read` — the repositories live
    // in GetIt, not in a Provider above this route, so reading them off the
    // widget tree threw the moment the screen opened.
    //
    // And the whole bloc rather than its three arguments, because
    // `PlanPhotoService` is deliberately *not* a singleton: it holds a
    // camera, and the registered factory hands each tracing session its own.
    create: (_) =>
        getIt<RoomTraceBloc>()
          ..add(RoomTraceStarted(buildingId: buildingId, floorId: floorId)),
    child: const RoomTraceView(),
  );
}

/// The screen itself, given a [RoomTraceBloc] already in the tree.
///
/// Public and separate from [RoomTracePage] so it can be rendered against a
/// bloc built from mocks. The page resolves three repositories off the widget
/// tree, and standing all of those up is not what a test of this screen is
/// trying to check.
class RoomTraceView extends StatelessWidget {
  const RoomTraceView({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<RoomTraceBloc, RoomTraceState>(
        listenWhen: (before, after) =>
            before.warning != after.warning ||
            before.error != after.error ||
            before.stage != after.stage,
        listener: (context, state) {
          final message = state.error ?? state.warning;
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
          if (state.stage == RoomTraceStage.saved) context.pop();
        },
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(PhosphorIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
            title: Text(
              state.stage == RoomTraceStage.photo
                  ? 'Photograph the plan'
                  // Short because three actions sit beside it, and no longer
                  // "the rooms" because this screen also draws halls and marks
                  // stairs.
                  : 'Trace floor',
            ),
            actions: [
              if (state.stage != RoomTraceStage.photo) const _SetupMenu(),
              // Lives here rather than beside the mode bar, which needs the
              // whole width for its four segments.
              if (state.stage != RoomTraceStage.photo)
                IconButton(
                  tooltip: 'Preview the plan',
                  icon: const Icon(PhosphorIcons.mapTrifold),
                  onPressed: state.plan.drawableRooms.isEmpty
                      ? null
                      : () => _showPreview(context, state.plan),
                ),
              if (state.stage != RoomTraceStage.photo)
                TextButton(
                  onPressed: state.canSave
                      ? () => context.read<RoomTraceBloc>().add(
                          const RoomTraceSaved(),
                        )
                      : null,
                  child: const Text('Save'),
                ),
            ],
          ),
          body: switch (state.stage) {
            RoomTraceStage.photo => const _PhotoStep(),
            RoomTraceStage.saving => const Center(
              child: CircularProgressIndicator(),
            ),
            _ => const _TraceStep(),
          },
        ),
      );
}

class _PhotoStep extends StatelessWidget {
  const _PhotoStep();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RoomTraceBloc>();
    final state = context.watch<RoomTraceBloc>().state;
    final camera = bloc.photos.camera;

    return Column(
      children: [
        Expanded(
          child: state.cameraReady && camera != null
              ? CameraPreview(camera)
              : const _BlankGrid(),
        ),
        Padding(
          padding: const EdgeInsets.all(AppDimens.space16),
          child: Column(
            children: [
              Text(
                'Point at the floor plan posted on the wall. You will trace the '
                'rooms onto the photo.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppDimens.space12),
              if (state.cameraReady)
                FilledButton.icon(
                  onPressed: () => bloc.add(const RoomPhotoTaken()),
                  icon: const Icon(PhosphorIcons.camera),
                  label: const Text('Take the photo'),
                ),
              const SizedBox(height: AppDimens.space8),
              // Often the better source. Boards get photographed
              // opportunistically — you are standing in front of one — and the
              // trip back to trace it happens later, somewhere else. It also
              // lets a contributor pick their squarest shot, which is exactly
              // what makes the perspective correction have less to undo.
              OutlinedButton.icon(
                onPressed: () => bloc.add(const RoomPhotoPicked()),
                icon: const Icon(PhosphorIcons.image),
                label: const Text('Choose a photo from your gallery'),
              ),
              const SizedBox(height: AppDimens.space8),
              // Always offered. A contributor with no camera permission, or a
              // building with no posted plan, can still lay out a floor from
              // memory on the grid — and it is the only way this screen is
              // usable on a desktop or in a test.
              TextButton(
                onPressed: () => bloc.add(const RoomPhotoSkipped()),
                child: const Text('Trace without a photo'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The tappable plan area. See the note where it is attached.
const Key traceSurfaceKey = Key('room-trace-surface');

class _TraceStep extends StatelessWidget {
  const _TraceStep();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RoomTraceBloc>();
    final state = context.watch<RoomTraceBloc>().state;

    return Column(
      children: [
        const _ModeBar(),
        // Sized from the **screen**, never from what is left over.
        //
        // Taps are stored as fractions of this box's width and drawn back the
        // same way, so the box has to sit exactly where the photograph does and
        // stay there. Two things follow, and both were wrong before:
        //
        //   * It is given the photograph's own shape, so the picture fills it
        //     rather than being letter-boxed inside it. Otherwise the overlay
        //     is measured from the top of the box and the photo floats in the
        //     middle of it, a fixed distance apart.
        //   * Its size depends only on the screen and that shape. It used to be
        //     an `Expanded`, taking whatever the mode bar and the controls left
        //     — and the controls are a different height for every tool. So
        //     switching from Rooms to Doors resized the box and slid the
        //     photograph out from under rooms that stayed where they were put.
        //
        // Capped at a little over half the screen so the controls always have
        // somewhere to be; the cap reduces width and height together, because
        // keeping the shape matters more than filling the width.
        Builder(
          builder: (context) {
            final screen = MediaQuery.sizeOf(context);
            final aspect = state.surfaceAspect;
            final width = math.min(screen.width, screen.height * 0.58 * aspect);

            return SizedBox(
              width: width,
              height: width / aspect,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;

                  void handleTap(Offset local) {
                    // Both axes normalised by the box's *width*, so a room
                    // traced square stays square. The bloc flips v into plan
                    // space; nothing here knows about that.
                    final u = local.dx / width;
                    final v = local.dy / width;

                    switch (state.mode) {
                      case RoomTraceMode.board:
                        bloc.add(BoardCornerTapped(u, v));
                      case RoomTraceMode.scale:
                        bloc.add(ScalePointTapped(u, v));
                      case RoomTraceMode.rooms:
                        bloc.add(RoomCornerTapped(u, v));
                      case RoomTraceMode.corridor:
                        // Its own event, not a room corner: a hallway must not
                        // snap to the rooms it runs between. See
                        // [HallPointTapped].
                        bloc.add(HallPointTapped(u, v));
                      case RoomTraceMode.doors:
                        bloc.add(RoomDoorTapped(u, v));
                      case RoomTraceMode.stairs:
                        bloc.add(StairsTapped(u, v));
                    }
                  }

                  // Zoom wraps the tap target rather than the other way round,
                  // so `localPosition` still arrives in the box's own
                  // coordinates and nothing below here knows the plan was
                  // magnified. See [ZoomablePlan].
                  return ZoomablePlan(
                    builder: (context, zoom) => GestureDetector(
                      // Keyed so a test can aim at the tracing surface itself.
                      // The screen is full of other gesture detectors and
                      // custom paints, and a finder that picks the wrong one
                      // taps a button instead of the plan while still looking
                      // like it worked.
                      key: traceSurfaceKey,
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => handleTap(details.localPosition),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (state.photoPath != null)
                            // `fill`, because the box was just given the
                            // photo's own aspect ratio — anything else would
                            // reintroduce the letter-boxing this is here to
                            // remove.
                            Image.file(File(state.photoPath!), fit: BoxFit.fill)
                          else
                            const _BlankGrid(),
                          CustomPaint(
                            painter: RoomTracePainter(
                              plan: state.plan,
                              draft: state.draft,
                              rectification: state.rectification,
                              boardCorners: state.boardCorners,
                              scalePoints: state.scalePoints,
                              selectedRoomId: state.selectedRoomId,
                              mode: state.mode,
                              zoom: zoom,
                              onDark:
                                  Theme.of(context).brightness ==
                                  Brightness.dark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        // Scrollable, because the surface above now takes a fixed share of the
        // screen and the tools below it are not all the same height. Without
        // this the tallest of them overflows a short phone.
        const Expanded(child: SingleChildScrollView(child: _TraceControls())),
      ],
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RoomTraceBloc>();
    final state = context.watch<RoomTraceBloc>().state;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space8,
      ),
      // Four segments is what fits, and these are the four: the things a
      // contributor picks between hundreds of times while tracing a floor.
      // Squaring the board and setting the scale are each done once, at the
      // start, so they moved to the app bar's setup menu — see [_SetupMenu].
      //
      // No icons either. Labelled segments plus icons overflow a 720 px phone:
      // "Rooms" rendered as "Roo" and **"Doors" was entirely off-screen**, so
      // door placement — without which a floor is a picture rather than a map —
      // could not be reached at all. The row is still scrollable, but nothing
      // should depend on discovering that.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<RoomTraceMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: RoomTraceMode.rooms, label: Text('Rooms')),
            ButtonSegment(value: RoomTraceMode.corridor, label: Text('Halls')),
            ButtonSegment(value: RoomTraceMode.doors, label: Text('Doors')),
            ButtonSegment(value: RoomTraceMode.stairs, label: Text('Stairs')),
          ],
          selected: {
            // Board and scale are still real modes and still take taps on the
            // plan; they simply have no segment. Showing the drawing mode they
            // will return to would light up a segment that is not active, so
            // nothing is selected while one of them is running.
            if (state.mode != RoomTraceMode.board &&
                state.mode != RoomTraceMode.scale)
              state.mode,
          },
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) => bloc.add(
            RoomTraceModeChanged(
              selection.isEmpty ? RoomTraceMode.rooms : selection.first,
            ),
          ),
        ),
      ),
    );
  }
}

/// The two steps that are done once per floor, before the tracing starts.
///
/// In a menu rather than the mode bar because that is what they are: squaring
/// the board is worth doing before the first room and pointless after the last,
/// and the scale is one measurement for the whole floor. Giving each a
/// permanent segment cost two of the four slots the constantly-used tools need.
///
/// Badged until the board has been squared up, because that one is easy to skip
/// and expensive to skip — every room traced first keeps the photograph's
/// perspective, and there is no way to fix them afterwards.
class _SetupMenu extends StatelessWidget {
  const _SetupMenu();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RoomTraceBloc>();
    final state = context.watch<RoomTraceBloc>().state;

    return PopupMenuButton<RoomTraceMode>(
      tooltip: 'Set the board up',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(PhosphorIcons.slidersHorizontal),
          if (!state.isRectified)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.coral,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      onSelected: (mode) => bloc.add(RoomTraceModeChanged(mode)),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: RoomTraceMode.board,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(PhosphorIcons.frameCorners),
            title: const Text('Square the board up'),
            subtitle: Text(
              state.isRectified ? 'Done — tap to redo it' : 'Do this first',
            ),
          ),
        ),
        PopupMenuItem(
          value: RoomTraceMode.scale,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(PhosphorIcons.ruler),
            title: const Text('Set the scale'),
            subtitle: Text(
              state.hasScale ? 'Set — distances can be spoken' : 'Optional',
            ),
          ),
        ),
      ],
    );
  }
}

class _TraceControls extends StatelessWidget {
  const _TraceControls();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RoomTraceBloc>();
    final state = context.watch<RoomTraceBloc>().state;
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(switch (state.mode) {
              RoomTraceMode.board =>
                state.isRectified
                    ? 'Squared up. Tap the four corners again to redo it.'
                    : 'Tap the four corners of the plan on the board, '
                          'clockwise from its top left. '
                          '${state.boardCorners.length} of 4.',
              RoomTraceMode.scale =>
                state.scalePoints.length < 2
                    ? 'Tap two points you know the real distance between. '
                          '${state.scalePoints.length} of 2.'
                    : 'Now say how far apart they really are.',
              RoomTraceMode.rooms =>
                state.isTracing
                    ? 'Tap each corner of the room. ${state.draft.length} placed.'
                    : 'Tap the corners of a room to trace it.',
              RoomTraceMode.corridor =>
                state.isTracing
                    ? 'Tap along the middle of the hallway. '
                          '${state.draft.length} placed.'
                    : 'Tap along the middle of a hallway — not its corners. '
                          'Routes follow the line you draw.',
              RoomTraceMode.doors =>
                'Tap each door where it opens onto the corridor. Rooms that '
                'only share a wall do not need one.',
              RoomTraceMode.stairs =>
                state.verticalLinks.isEmpty
                    ? 'Tap where the stairs are. One tap each.'
                    : 'Tap where the stairs are. '
                          '${state.verticalLinks.length} marked so far.',
            }, style: theme.textTheme.bodyMedium),
            if (state.mode == RoomTraceMode.rooms ||
                state.mode == RoomTraceMode.corridor ||
                state.mode == RoomTraceMode.stairs)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.space4),
                child: Text(
                  'Pinch to zoom in — the corners are easier to hit.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (state.mode == RoomTraceMode.rooms && !state.isRectified)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.space4),
                child: Text(
                  // Said in Rooms mode rather than only in Board mode, because
                  // that is where somebody who has not thought about it is
                  // standing — and every room traced now keeps the skew.
                  'Tip: square the board up first. A photo taken at an angle '
                  'skews every room traced from it.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (state.hasScale)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.space4),
                child: Text(
                  'Scale set — distances will be spoken.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ),
            if (!state.ordinalsAreSafe && state.incompleteCorridors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.space8),
                child: Text(
                  // Surfaced here, on the tracing screen, because this is
                  // where it can still be fixed. Discovered later it is just
                  // an app that has quietly stopped saying which door.
                  '${state.incompleteCorridors.values.fold(0, (a, b) => a + b)} '
                  'declared door(s) not yet placed — spoken door counts stay '
                  'off until they are.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),
            const SizedBox(height: AppDimens.space12),
            if (state.mode == RoomTraceMode.board)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.boardCorners.isEmpty
                          ? null
                          : () => bloc.add(const BoardCornerUndone()),
                      icon: const Icon(PhosphorIcons.arrowUUpLeft),
                      label: const Text('Undo'),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.isRectified
                          ? () => bloc.add(const BoardRectificationCleared())
                          : null,
                      icon: const Icon(PhosphorIcons.x),
                      label: const Text('Clear'),
                    ),
                  ),
                ],
              )
            else if (state.mode == RoomTraceMode.scale)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.hasScale
                          ? () => bloc.add(const ScaleCleared())
                          : null,
                      icon: const Icon(PhosphorIcons.x),
                      label: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: state.scalePoints.length < 2
                          ? null
                          : () => _askForDistance(context, bloc),
                      icon: const Icon(PhosphorIcons.ruler),
                      label: const Text('Set distance'),
                    ),
                  ),
                ],
              )
            else if (state.mode == RoomTraceMode.rooms)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.isTracing
                          ? () => bloc.add(const RoomCornerUndone())
                          : null,
                      icon: const Icon(PhosphorIcons.arrowUUpLeft),
                      label: const Text('Undo'),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: state.canCloseRoom
                          ? () => _askForRoom(context, bloc)
                          : null,
                      icon: const Icon(PhosphorIcons.check),
                      label: const Text('Close room'),
                    ),
                  ),
                ],
              )
            else if (state.mode == RoomTraceMode.corridor)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.isTracing
                          ? () => bloc.add(const RoomCornerUndone())
                          : null,
                      icon: const Icon(PhosphorIcons.arrowUUpLeft),
                      label: const Text('Undo'),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: state.canCloseCorridor
                          ? () => _askForCorridor(context, bloc)
                          : null,
                      icon: const Icon(PhosphorIcons.check),
                      label: const Text('Finish hall'),
                    ),
                  ),
                ],
              )
            else if (state.mode == RoomTraceMode.stairs)
              _StairsList(state: state, bloc: bloc)
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _askForDoorCount(context, bloc, state),
                      icon: const Icon(PhosphorIcons.listNumbers),
                      label: const Text('Declare door count'),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => bloc.add(const StubRoomAdded()),
                      icon: const Icon(PhosphorIcons.plus),
                      label: const Text('Untraced room'),
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

/// Every staircase and lift on the floor, with a way to remove a mis-tap.
///
/// The list is the answer to "where are all the stairs" — a marker on a plan is
/// only findable if you already know where to look, and a contributor checking
/// their work against the board wants to count them.
class _StairsList extends StatelessWidget {
  const _StairsList({required this.state, required this.bloc});

  final RoomTraceState state;
  final RoomTraceBloc bloc;

  @override
  Widget build(BuildContext context) {
    final marked = state.verticalLinks;
    if (marked.isEmpty) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(PhosphorIcons.stairs),
        label: const Text('No stairs marked yet'),
      );
    }

    return Wrap(
      spacing: AppDimens.space8,
      runSpacing: AppDimens.space8,
      children: [
        for (final room in marked)
          InputChip(
            avatar: Icon(
              room.category == RoomCategory.elevator
                  ? PhosphorIcons.elevator
                  : PhosphorIcons.stairs,
              size: 16,
            ),
            label: Text(room.displayName),
            // Deleting takes the door with it — see [RoomDeleted]. A stairs
            // marker placed on the wrong side of a corridor is a mis-tap, and
            // mis-taps have to be undoable or the whole mode is a trap.
            onDeleted: () => bloc.add(RoomDeleted(room.id)),
          ),
      ],
    );
  }
}

/// Asks what a just-drawn hallway is called.
///
/// Shorter than the room sheet on purpose: a hallway is a hallway, and the one
/// thing worth typing is the name on the board, when it has one. The category
/// choice is between the two things this shape is ever used for.
Future<void> _askForCorridor(BuildContext context, RoomTraceBloc bloc) async {
  var category = RoomCategory.corridor;
  var label = "";

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SheetBody(
      child: StatefulBuilder(
        builder: (builderContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Name this hallway',
              style: Theme.of(builderContext).textTheme.titleMedium,
            ),
            const SizedBox(height: AppDimens.space12),
            Wrap(
              spacing: AppDimens.space8,
              children: [
                for (final option in [
                  RoomCategory.corridor,
                  RoomCategory.balcony,
                ])
                  ChoiceChip(
                    label: Text(RoomPalette.labelFor(option)),
                    selected: category == option,
                    onSelected: (_) => setSheetState(() => category = option),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.space12),
            SheetTextField(
              label: "Name on the board (optional)",
              hint: "Ground floor west",
              textCapitalization: TextCapitalization.sentences,
              onChanged: (value) => label = value,
            ),
            const SizedBox(height: AppDimens.space16),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: const Text('Add hallway'),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed ?? false) {
    bloc.add(CorridorPathClosed(category: category, label: label));
  }
}

/// Asks what the just-traced shape is.
///
/// Category first and required, label second and optional — a contributor
/// standing in a corridor can always say "that is an office" and often cannot
/// read the name off the board.
Future<void> _askForRoom(BuildContext context, RoomTraceBloc bloc) async {
  var category = RoomCategory.office;
  var label = "";

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SheetBody(
      child: StatefulBuilder(
        builder: (builderContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What is this room?',
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
              label: "Name on the door (optional)",
              hint: "Digital Forensic Office",
              textCapitalization: TextCapitalization.words,
              onChanged: (value) => label = value,
            ),
            const SizedBox(height: AppDimens.space16),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: const Text('Add room'),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed ?? false) {
    bloc.add(RoomClosed(category: category, label: label));
  }
}

/// Asks how far apart the two tapped points really are.
///
/// The one measurement in the whole tracing path, and it turns the plan from
/// unitless to metric — after which guidance may speak distances and the
/// evaluation report has real areas. The suggestions matter as much as the
/// field: most people have no tape measure and every one of these is available
/// standing in front of the board.
Future<void> _askForDistance(BuildContext context, RoomTraceBloc bloc) async {
  var metres = "";

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // Same reason as SheetBody: this dialog has a field, so a keyboard comes
      // up under it and takes the height its content needs.
      scrollable: true,
      title: const Text('How far apart?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The real-world distance between the two points you tapped. This '
            'sets the scale for the whole floor.',
          ),
          const SizedBox(height: AppDimens.space12),
          SheetTextField(
            label: "Metres",
            hint: "10.5",
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
  if ((confirmed ?? false) && parsed != null) {
    bloc.add(ScaleDeclared(parsed));
  }
}

/// Asks how many doors the contributor counted on a corridor's walls.
///
/// The one number anybody is asked to type, and the guard on the only
/// instruction the app can get confidently, silently wrong. See
/// [RoomPlan.corridorIsComplete].
Future<void> _askForDoorCount(
  BuildContext context,
  RoomTraceBloc bloc,
  RoomTraceState state,
) async {
  final corridors = state.plan.drawableRooms
      .where((room) => room.isCirculation)
      .toList();

  if (corridors.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Trace a corridor first.')));
    return;
  }

  var corridor = corridors.first;
  var count = "${state.plan.declaredDoorCounts[corridor.id] ?? ""}";

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (builderContext, setDialogState) => AlertDialog(
        scrollable: true,
        title: const Text('Doors on this corridor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Stand in the corridor and count every door on its walls — '
              'including ones you cannot go through. Spoken directions say '
              '"the second door on your left", and that is only right if the '
              'map knows about all of them.',
            ),
            const SizedBox(height: AppDimens.space12),
            DropdownButtonFormField<String>(
              initialValue: corridor.id,
              isExpanded: true,
              items: [
                for (final option in corridors)
                  DropdownMenuItem(
                    value: option.id,
                    child: Text(option.displayName),
                  ),
              ],
              onChanged: (id) => setDialogState(() {
                corridor = corridors.firstWhere((room) => room.id == id);
                count = "${state.plan.declaredDoorCounts[corridor.id] ?? ""}";
              }),
            ),
            const SizedBox(height: AppDimens.space8),
            SheetTextField(
              // Keyed on the corridor so switching which one is being counted
              // rebuilds the field with that corridor.s number rather than
              // leaving the previous one.s in place.
              key: ValueKey(corridor.id),
              label: "How many doors",
              initial: count,
              keyboardType: TextInputType.number,
              onChanged: (value) => count = value,
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
            child: const Text('Save count'),
          ),
        ],
      ),
    ),
  );

  final parsed = int.tryParse(count.trim());
  if ((confirmed ?? false) && parsed != null && parsed >= 0) {
    bloc.add(CorridorDoorCountDeclared(corridorId: corridor.id, count: parsed));
  }
}

/// The traced plan as the schematic it will become.
///
/// Worth having on this screen rather than only after saving: a room traced
/// slightly wrong is obvious as a schematic and invisible as an overlay on the
/// photograph it was traced from.
void _showPreview(BuildContext context, RoomPlan plan) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.of(sheetContext).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppDimens.space16),
            child: Text(
              'Plan preview',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          Expanded(child: RoomPlanView(plan: plan)),
        ],
      ),
    ),
  );
}

/// What tracing happens on when there is no photo.
class _BlankGrid extends StatelessWidget {
  const _BlankGrid();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _GridPainter(
        line: theme.dividerColor,
        background: theme.brightness == Brightness.dark
            ? AppColors.darkSurface
            : AppColors.surface,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.line, required this.background});

  final Color line;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..color = line.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final step = size.width / 12;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.line != line || old.background != background;
}
