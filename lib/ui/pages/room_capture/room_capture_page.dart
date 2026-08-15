import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/room_plan.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/room_capture/bloc/room_capture_cubit.dart';
import '../../../services/injection_container.dart';
import '../../../services/vision/depth_frame.dart' show ArCoreAvailability;
import '../../widgets/floor_picker.dart';
import '../../widgets/room_plan_palette.dart';
import '../../widgets/sheet_body.dart';
import '../../widgets/sheet_text_field.dart';
import '../../widgets/room_plan_view.dart';

/// Capturing rooms in AR — floorplan spec §2.
///
/// Tap the floor at the base of each corner while walking the room. The
/// interaction is built on the floor rather than on the corners themselves
/// because ARCore's floor planes are its most reliable output and its
/// wall-to-wall boundaries its least — see `FloorHitTester`.
///
/// Rooms whose floors are hidden by furniture can be traced around the
/// **ceiling** instead — the walls are vertical, so the polygon is the same one.
/// Which surface a room is on is decided by its first corner and shown on
/// screen; undoing back to no corners releases it.
///
/// The honest path when a device cannot scan at all is the one this screen
/// takes by default: it says so and offers photo tracing, which produces the
/// same [RoomPlan] and is fully exercised.
class RoomCapturePage extends StatelessWidget {
  const RoomCapturePage({
    super.key,
    required this.buildingId,
    this.floorId = '',
  });

  final String buildingId;

  /// Which floor to scan. Empty falls back to the building’s first, which is
  /// what happens when the screen is opened outside the mapping hub.
  final String floorId;

  @override
  Widget build(BuildContext context) {
    // The view ARCore is told it is drawing into. Measured here, before the
    // session starts, because `setDisplayGeometry` needs it at resume — and a
    // session started against the wrong viewport maps every tap wrongly with
    // nothing on screen to suggest it. The display *rotation* is not passed:
    // native reads it from the activity, since Dart cannot.
    final media = MediaQuery.of(context);
    final size = media.size;
    final ratio = media.devicePixelRatio;

    return BlocProvider(
      create: (_) => RoomCaptureCubit(getIt(), getIt(), getIt())
        ..start(
          buildingId: buildingId,
          floorId: floorId,
          viewWidth: (size.width * ratio).round(),
          viewHeight: (size.height * ratio).round(),
        ),
      child: RoomCaptureView(buildingId: buildingId),
    );
  }
}

/// The screen itself, given a cubit already in the tree.
///
/// Public and separate from [RoomCapturePage] so it can be rendered against a
/// cubit built from fakes — the only way any of this is testable without a
/// certified device.
class RoomCaptureView extends StatelessWidget {
  const RoomCaptureView({super.key, required this.buildingId});

  final String buildingId;

  /// The tappable camera area. Keyed so a test can aim at it: the screen is
  /// full of other gesture targets and a finder that picks the wrong one taps a
  /// button while still looking like it worked.
  static const Key captureSurfaceKey = Key('room-capture-surface');

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<RoomCaptureCubit, RoomCaptureState>(
        listenWhen: (before, after) =>
            before.error != after.error || before.stage != after.stage,
        listener: (context, state) {
          final error = state.error;
          if (error != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(error),
                  backgroundColor: AppColors.error,
                ),
              );
          }
          if (state.stage == RoomCaptureStage.saved) context.pop();
        },
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(PhosphorIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
            title: const Text('Scan the rooms'),
            actions: [
              if (state.stage == RoomCaptureStage.capturing)
                TextButton(
                  onPressed: state.canSave
                      ? () => context.read<RoomCaptureCubit>().save()
                      : null,
                  child: const Text('Save'),
                ),
            ],
          ),
          body: switch (state.stage) {
            RoomCaptureStage.checking => const Center(
              child: CircularProgressIndicator(),
            ),
            RoomCaptureStage.unavailable => _Unavailable(
              buildingId: buildingId,
              state: state,
            ),
            RoomCaptureStage.saving => const Center(
              child: CircularProgressIndicator(),
            ),
            _ => const _CaptureStep(),
          },
        ),
      );
}

/// What most phones will see, and not an error.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.buildingId, required this.state});

  final String buildingId;
  final RoomCaptureState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIcons.cube, size: 48, color: AppColors.inkMuted),
            const SizedBox(height: AppDimens.space16),
            Text(
              'This phone cannot scan in AR',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.space8),
            Text(
              state.error ??
                  'Google has not certified this device for ARCore. Most '
                      'budget Android phones are in the same position.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.space24),
            // A refused permission is fixable, unlike an uncertified device —
            // so it gets the primer rather than being told to go and trace a
            // photo instead.
            if (state.availability == ArCoreAvailability.supported) ...[
              FilledButton.icon(
                onPressed: () => context.pushReplacementNamed(
                  RouteNames.cameraPrimer,
                  extra: RouteNames.roomCapture,
                ),
                icon: const Icon(PhosphorIcons.camera),
                label: const Text('Allow the camera'),
              ),
              const SizedBox(height: AppDimens.space8),
            ],
            // The point of the fallback: it is not a lesser path. It produces
            // the same plan, and it is the one that has actually been proven.
            FilledButton.icon(
              onPressed: () => context.pushReplacementNamed(
                RouteNames.roomTrace,
                pathParameters: {'id': buildingId},
              ),
              icon: const Icon(PhosphorIcons.image),
              label: const Text('Trace from a photo instead'),
            ),
            const SizedBox(height: AppDimens.space8),
            Text(
              'Photograph the plan on the wall and trace the rooms onto it. '
              'Same map, any phone.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The live half of the screen.
///
/// Stateful only to report its own size. The camera area is not the whole
/// screen — there is a mode bar above it and controls below — and **ARCore has
/// to be told about the area taps are actually normalised against**, or every
/// tap is mapped through a viewport taller than the one the finger is in and
/// lands progressively further off towards the edges. It was previously handed
/// the full screen size measured at page build.
class _CaptureStep extends StatefulWidget {
  const _CaptureStep();

  @override
  State<_CaptureStep> createState() => _CaptureStepState();
}

class _CaptureStepState extends State<_CaptureStep>
    with WidgetsBindingObserver {
  /// Last size handed to ARCore, in device pixels.
  Size? _reported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Hands the camera back when the app leaves, and takes it again on return.
  ///
  /// `MainActivity.onPause` stops the ARCore session natively whether Dart asks
  /// or not — it has to, because ARCore holds the camera exclusively and a
  /// backgrounded app that keeps it locked breaks every other camera on the
  /// phone. Nothing restarted it, so coming back to this screen showed a
  /// `Texture` pointing at a released id: a blank rectangle where the camera
  /// was, no crash, and nothing in the log.
  ///
  /// `inactive` is deliberately not handled. It fires for transients — the
  /// notification shade, a permission dialog — and tearing the session down for
  /// those would restart tracking from nothing every time one appeared.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (!mounted) return;
    final cubit = context.read<RoomCaptureCubit>();

    switch (lifecycle) {
      case AppLifecycleState.resumed:
        final size = _reported;
        if (size == null) return;
        cubit.resumeSession(
          viewWidth: size.width.round(),
          viewHeight: size.height.round(),
        );
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        cubit.pauseSession();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Tells the session how big the camera area is, once per real change.
  ///
  /// Deferred to after the frame because it runs from inside `build`, and
  /// because the size that matters is the one the widget was actually laid out
  /// at. Rotating the phone changes it, which is also what prompts native to
  /// re-read the display rotation.
  void _reportViewport(BoxConstraints constraints) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final size = Size(
      (constraints.maxWidth * ratio).roundToDouble(),
      (constraints.maxHeight * ratio).roundToDouble(),
    );
    if (size.isEmpty || size == _reported) return;
    _reported = size;

    final cubit = context.read<RoomCaptureCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cubit.setViewport(
        viewWidth: size.width.round(),
        viewHeight: size.height.round(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RoomCaptureCubit>();
    final state = context.watch<RoomCaptureCubit>().state;

    return Column(
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
              enabled: !state.wingHasRooms && !state.isCapturing,
              disabledReason:
                  'Save this wing before moving to another floor — a plan '
                  'belongs to one floor.',
              onChanged: cubit.changeFloor,
            ),
          ),
        _ModeBar(cubit: cubit, state: state),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _reportViewport(constraints);
              return GestureDetector(
                key: RoomCaptureView.captureSurfaceKey,
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  // Normalised, so neither Dart nor the widget has to know the
                  // camera image's size — native scales into the geometry
                  // ARCore was configured with.
                  final u = details.localPosition.dx / constraints.maxWidth;
                  final v = details.localPosition.dy / constraints.maxHeight;
                  switch (state.mode) {
                    case RoomCaptureMode.rooms:
                      cubit.tapCorner(u, v);
                    case RoomCaptureMode.doors:
                      cubit.tapDoor(u, v);
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The camera itself, composited straight from the GPU.
                    //
                    // No `BoxFit`, no `RotatedBox`, no bytes: native draws the
                    // ARCore camera texture into this surface using ARCore's
                    // own display transform, which is the *same* mapping
                    // `setDisplayGeometry` uses for hit-testing. The picture and
                    // the taps therefore come from one calculation and cannot
                    // drift apart. The previous version decoded a throttled JPEG
                    // here and rotated it from a separately-derived sensor
                    // orientation, which is two calculations that only happened
                    // to agree.
                    if (state.textureId != null)
                      Texture(textureId: state.textureId!)
                    else
                      const ColoredBox(color: AppColors.ink),
                    CustomPaint(
                      painter: _CaptureOverlay(
                        cornerCount: state.draft.length,
                        canPlace: state.canPlace,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _Guidance(state: state),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        _CaptureControls(cubit: cubit, state: state),
      ],
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.cubit, required this.state});

  final RoomCaptureCubit cubit;
  final RoomCaptureState state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppDimens.space16,
      vertical: AppDimens.space8,
    ),
    child: SegmentedButton<RoomCaptureMode>(
      segments: const [
        ButtonSegment(
          value: RoomCaptureMode.rooms,
          label: Text('Rooms'),
          icon: Icon(PhosphorIcons.polygon),
        ),
        ButtonSegment(
          value: RoomCaptureMode.doors,
          label: Text('Doors'),
          icon: Icon(PhosphorIcons.door),
        ),
      ],
      selected: {state.mode},
      onSelectionChanged: (selection) => cubit.setMode(selection.first),
    ),
  );
}

/// A crosshair and the corner count, over the camera.
///
/// The corners themselves are deliberately *not* drawn in place: doing that
/// needs each captured anchor projected back into the current camera view every
/// frame. Now that there is a real GL context drawing the camera, that has
/// become a normal thing to add rather than an architectural problem — it would
/// live in `CameraBackgroundRenderer` beside the quad. Showing how many have
/// been placed, plus the plan preview a tap away, gives most of the confidence
/// for none of the work, so it stays the next thing rather than this thing.
class _CaptureOverlay extends CustomPainter {
  const _CaptureOverlay({required this.cornerCount, required this.canPlace});

  final int cornerCount;
  final bool canPlace;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final colour = canPlace ? AppColors.coral : AppColors.inkMuted;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colour;

    canvas.drawCircle(centre, 14, paint);
    canvas.drawLine(
      centre - const Offset(22, 0),
      centre - const Offset(6, 0),
      paint,
    );
    canvas.drawLine(
      centre + const Offset(6, 0),
      centre + const Offset(22, 0),
      paint,
    );
    canvas.drawLine(
      centre - const Offset(0, 22),
      centre - const Offset(0, 6),
      paint,
    );
    canvas.drawLine(
      centre + const Offset(0, 6),
      centre + const Offset(0, 22),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CaptureOverlay old) =>
      old.cornerCount != cornerCount || old.canPlace != canPlace;
}

class _Guidance extends StatelessWidget {
  const _Guidance({required this.state});

  final RoomCaptureState state;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppDimens.space12),
    color: AppColors.ink.withValues(alpha: 0.65),
    child: Row(
      children: [
        Icon(
          state.canPlace
              ? PhosphorIcons.checkCircle
              : PhosphorIcons.warningCircle,
          size: 18,
          color: state.canPlace ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: AppDimens.space8),
        Expanded(
          child: Text(
            // Always an instruction, never a diagnosis: "insufficient
            // features" is not something a person can act on.
            state.guidance,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.white),
          ),
        ),
        // Said out loud because nobody chose it. The first corner decides which
        // surface a room is traced on, so a room that locked overhead by
        // accident is otherwise invisible until the plan comes out wrong — by
        // which time the contributor has left the building. Undo clears it.
        if (state.isTracingCeiling) ...[
          const SizedBox(width: AppDimens.space8),
          const Icon(
            PhosphorIcons.arrowUp,
            size: 16,
            color: AppColors.coral,
          ),
          const SizedBox(width: AppDimens.space4),
          Text(
            'Ceiling',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.coral),
          ),
        ],
      ],
    ),
  );
}

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({required this.cubit, required this.state});

  final RoomCaptureCubit cubit;
  final RoomCaptureState state;

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
                Text(
                  '${state.plan.drawableRooms.length} room'
                  '${state.plan.drawableRooms.length == 1 ? "" : "s"} captured',
                  style: theme.textTheme.labelLarge,
                ),
                const Spacer(),
                if (state.lowConfidenceCorners > 0)
                  Text(
                    '${state.lowConfidenceCorners} weak',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                const SizedBox(width: AppDimens.space8),
                IconButton(
                  tooltip: 'Preview the plan',
                  icon: const Icon(PhosphorIcons.mapTrifold),
                  onPressed: state.plan.drawableRooms.isEmpty
                      ? null
                      : () => _showPreview(context, state.plan),
                ),
              ],
            ),
            _Warnings(state: state),
            const SizedBox(height: AppDimens.space8),
            if (state.mode == RoomCaptureMode.rooms)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.isCapturing ? cubit.undoCorner : null,
                      icon: const Icon(PhosphorIcons.arrowUUpLeft),
                      label: const Text('Undo'),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: state.canCloseRoom
                          ? () => _askForRoom(context, cubit)
                          : null,
                      icon: const Icon(PhosphorIcons.check),
                      label: const Text('Close room'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _askForDoorCount(context, cubit, state),
                      icon: const Icon(PhosphorIcons.listNumbers),
                      label: const Text('Declare door count'),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: cubit.addStubRoom,
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

/// The two things worth knowing before walking away from a building.
///
/// Shown while capturing rather than at save time, because both are fixed by
/// standing somewhere in the building — and neither is fixable from home.
class _Warnings extends StatelessWidget {
  const _Warnings({required this.state});

  final RoomCaptureState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doorless = state.roomsWithoutDoors;
    final stranded = state.strandedRooms;
    final drifting =
        state.capturedSpanMetres > RoomCaptureCubit.driftWarningSpanMetres;

    if (doorless.isEmpty && stranded.isEmpty && !drifting) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (doorless.isNotEmpty)
            Text(
              // Until a door is placed this is every room, which is precisely
              // the state a capture sits in — a picture of a floor rather than
              // a map of one.
              '${doorless.length} room${doorless.length == 1 ? "" : "s"} with '
              'no door yet — switch to Doors and stand in the doorways.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          if (stranded.isNotEmpty)
            Text(
              // Every room has a door and the floor is still in two pieces.
              '${stranded.length} room${stranded.length == 1 ? "" : "s"} '
              'cut off from the rest — a door between the two halves is '
              'missing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          if (drifting)
            Text(
              'This session now spans ${state.capturedSpanMetres.round()} m. '
              'Save and start a fresh scan for the next wing — heading error '
              'grows with distance.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks how many doors the contributor counted on a corridor's walls.
///
/// The one number anybody is asked to type, and the guard on the only
/// instruction the app can get confidently, silently wrong.
Future<void> _askForDoorCount(
  BuildContext context,
  RoomCaptureCubit cubit,
  RoomCaptureState state,
) async {
  final corridors = state.plan.drawableRooms
      .where((room) => room.isCirculation)
      .toList();

  if (corridors.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Capture a corridor first.')));
    return;
  }

  var corridor = corridors.first;
  var count = "${state.plan.declaredDoorCounts[corridor.id] ?? ""}";

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (builderContext, setDialogState) => AlertDialog(
        title: const Text('Doors on this corridor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Count every door on the corridor walls — including ones you '
              'cannot go through. Spoken directions say "the second door on '
              'your left", and that is only right if the map knows about all '
              'of them.',
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
    cubit.declareDoorCount(corridorId: corridor.id, count: parsed);
  }
}

/// Asks what the just-captured shape is.
///
/// The same sheet the tracing flow uses, and deliberately so: a contributor who
/// has learned one screen has learned both.
Future<void> _askForRoom(BuildContext context, RoomCaptureCubit cubit) async {
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
    await cubit.closeRoom(category: category, label: label);
  }
}

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
