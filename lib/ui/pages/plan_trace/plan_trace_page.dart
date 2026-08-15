import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart';
import '../../../core/models/landmark.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/plan_trace/bloc/plan_trace_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/plan_trace_painter.dart';

/// Turning the floor plan posted on a building's wall into its map.
///
/// Two steps: photograph the plan, then tap the landmarks onto it. Nobody is
/// asked how big anything is — see [PlanTraceStage] for why the map does not
/// need to know, and why asking would be the same unanswerable question as
/// asking a user to tap when they have walked ten metres.
class PlanTracePage extends StatelessWidget {
  const PlanTracePage({
    super.key,
    required this.buildingId,
    this.floorId = 'floor-g',
  });

  final String buildingId;
  final String floorId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<PlanTraceBloc>()
            ..add(PlanTraceStarted(buildingId, floorId: floorId)),
      child: const _TraceView(),
    );
  }
}

class _TraceView extends StatelessWidget {
  const _TraceView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlanTraceBloc, PlanTraceState>(
      listenWhen: (before, after) =>
          before.stage != after.stage || before.error != after.error,
      listener: (context, state) {
        if (state.error != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.error!)));
        }
        if (state.stage == PlanTraceStage.saved) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('Plan saved. It is the map now.')),
            );
          context.pop();
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(PhosphorIconsRegular.x),
              onPressed: () => context.pop(),
            ),
            title: Text(switch (state.stage) {
              PlanTraceStage.photo => 'Photograph the plan',
              _ => 'Trace the plan',
            }),
            actions: [
              if (state.stage == PlanTraceStage.trace)
                TextButton(
                  onPressed: state.canSave
                      ? () => context.read<PlanTraceBloc>().add(
                          const PlanTraceSaved(),
                        )
                      : null,
                  child: const Text('Save'),
                ),
            ],
          ),
          body: SafeArea(
            child: switch (state.stage) {
              PlanTraceStage.photo => const _PhotoStep(),
              PlanTraceStage.saving => const Center(
                child: CircularProgressIndicator(),
              ),
              _ => const _TraceStep(),
            },
          ),
        );
      },
    );
  }
}

/// Pointing the camera at the plan on the wall.
class _PhotoStep extends StatelessWidget {
  const _PhotoStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<PlanTraceBloc>();
    final state = context.watch<PlanTraceBloc>().state;
    final controller = bloc.photos.camera;

    return Column(
      children: [
        Expanded(
          child: state.cameraReady && controller != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  child: CameraPreview(controller),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.space32),
                    child: Text(
                      'No camera available. You can still trace the plan on a '
                      'blank grid — the map is the taps, not the photo.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppDimens.space16),
          child: Column(
            children: [
              Text(
                'Fill the frame with the plan, straight on. A photo taken at an '
                'angle traces skewed.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppDimens.space12),
              if (state.cameraReady)
                ElevatedButton.icon(
                  onPressed: () => bloc.add(const PlanPhotoTaken()),
                  icon: const Icon(PhosphorIconsFill.camera, size: 18),
                  label: const Text('Take the photo'),
                ),
              const SizedBox(height: AppDimens.space8),
              TextButton(
                onPressed: () => bloc.add(const PlanPhotoSkipped()),
                child: const Text('Trace without a photo'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Placing landmarks on the photographed plan.
class _TraceStep extends StatelessWidget {
  const _TraceStep();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PlanTraceBloc>();
    final state = context.watch<PlanTraceBloc>().state;

    return Column(
      children: [
        const _Instructions(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final box = Size(constraints.maxWidth, constraints.maxHeight);

              void handleTap(Offset local) {
                // The box is the plan's coordinate space, and both axes are
                // normalised by its width so a corridor drawn square stays
                // square in a box that is not.
                final u = local.dx / box.width;
                final v = local.dy / box.width;

                final hit = bloc.pointAt(u, v);
                if (hit != null) {
                  bloc.add(PlanNodeTapped(hit.ref));
                  return;
                }
                _askForLandmark(context, bloc, u, v);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => handleTap(details.localPosition),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (state.photoPath != null)
                      Image.file(File(state.photoPath!), fit: BoxFit.contain)
                    else
                      const _BlankGrid(),
                    CustomPaint(
                      painter: PlanTracePainter(
                        // This floor's trace only — the rest of the building
                        // is still in state.points, waiting to be saved with
                        // it, but it does not belong on this plan.
                        points: state.pointsOnFloor,
                        links: state.linksOnFloor,
                        selectedRef: state.selectedRef,
                        onDark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const _TraceControls(),
      ],
    );
  }
}

class _Instructions extends StatelessWidget {
  const _Instructions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<PlanTraceBloc>().state;

    // A selection on another floor is invisible on this one, so the only way
    // a contributor knows the stairwell join is still armed is being told.
    final selected = state.pointOf(state.selectedRef);
    final text = switch (state.selectedRef) {
      null => 'Tap a doorway or junction to place a landmark.',
      _ when state.joiningFromAnotherFloor =>
        'Joining from ${selected!.displayName} on the other floor — tap where '
            'the stairs come out and the two are linked.',
      _ =>
        'Tap again to place the next one — it joins to the last. Tap a '
            'placed landmark to join or unjoin it.',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space8,
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

class _TraceControls extends StatelessWidget {
  const _TraceControls();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<PlanTraceBloc>();
    final state = context.watch<PlanTraceBloc>().state;
    final selected = state.pointOf(state.selectedRef);

    return Padding(
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // This floor, then the building, because the second number
                  // is the reassurance that switching floor did not throw the
                  // first one away.
                  '${state.pointsOnFloor.length} on this floor · '
                  '${state.points.length} landmarks · '
                  '${state.links.length} corridors',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (selected != null)
                IconButton(
                  tooltip: 'Remove ${selected.displayName}',
                  icon: const Icon(PhosphorIconsRegular.trash, size: 20),
                  color: AppColors.error,
                  onPressed: () => bloc.add(PlanNodeRemoved(selected.ref)),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.space8),
          Row(
            children: [
              Expanded(
                child: _FloorPicker(
                  floors: state.floors,
                  floorId: state.floorId,
                  onChanged: (value) => bloc.add(PlanFloorChanged(value)),
                ),
              ),
              const SizedBox(width: AppDimens.space8),
              TextButton(
                onPressed: () => bloc.add(const PlanPhotoRetaken()),
                child: const Text('Re-shoot'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Which floor the next landmarks belong to.
///
/// Switchable mid-trace on purpose: that is how one plan spans a building.
/// Place the ground-floor stairwell, switch floor, place the landing above it,
/// and join the two — A* then climbs it like any other corridor.
///
/// A picker over the building's real floors rather than a text field, because
/// a traced node stores a `floors.id`. Typing one would produce a plan the
/// server rejects, and only after the whole floor had been traced.
class _FloorPicker extends StatelessWidget {
  const _FloorPicker({
    required this.floors,
    required this.floorId,
    required this.onChanged,
  });

  final List<BuildingFloor> floors;
  final String floorId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (floors.isEmpty) {
      return Text(
        'This building has no floors recorded yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: floors.any((f) => f.id == floorId)
          ? floorId
          : floors.first.id,
      isDense: true,
      decoration: const InputDecoration(labelText: 'Floor', isDense: true),
      items: [
        for (final floor in floors)
          DropdownMenuItem(
            value: floor.id,
            child: Text('Floor ${floor.label}'),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _BlankGrid extends StatelessWidget {
  const _BlankGrid();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? AppColors.darkSurface : AppColors.surface,
      child: const SizedBox.expand(),
    );
  }
}

/// Asks what the landmark just tapped actually is.
Future<void> _askForLandmark(
  BuildContext context,
  PlanTraceBloc bloc,
  double u,
  double v,
) async {
  final result = await showDialog<_LandmarkDraft>(
    context: context,
    builder: (dialogContext) => const _LandmarkDialog(),
  );
  if (result == null) return;

  bloc.add(
    PlanNodeAdded(
      u: u,
      v: v,
      kind: result.kind,
      // What OCR must read on the door itself. Defaulted from the name so the
      // common case — a room whose sign says exactly its number — is one field.
      labelText: result.labelText.isEmpty
          ? Landmark.normalise(result.displayName)
          : Landmark.normalise(result.labelText),
      displayName: result.displayName,
      roomId: result.roomId?.isEmpty ?? true ? null : result.roomId,
    ),
  );
}

class _LandmarkDraft {
  const _LandmarkDraft({
    required this.displayName,
    required this.labelText,
    required this.kind,
    this.roomId,
  });

  final String displayName;
  final String labelText;
  final LandmarkKind kind;
  final String? roomId;
}

class _LandmarkDialog extends StatefulWidget {
  const _LandmarkDialog();

  @override
  State<_LandmarkDialog> createState() => _LandmarkDialogState();
}

class _LandmarkDialogState extends State<_LandmarkDialog> {
  final _name = TextEditingController();
  final _label = TextEditingController();
  final _room = TextEditingController();
  LandmarkKind _kind = LandmarkKind.door;

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('What is here?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Room 204',
              ),
            ),
            const SizedBox(height: AppDimens.space12),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Sign text (optional)',
                hintText: '204 — what the camera must read',
              ),
            ),
            const SizedBox(height: AppDimens.space12),
            DropdownButtonFormField<LandmarkKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Kind'),
              items: [
                for (final kind in LandmarkKind.values)
                  DropdownMenuItem(value: kind, child: Text(kind.name)),
              ],
              onChanged: (value) =>
                  setState(() => _kind = value ?? LandmarkKind.door),
            ),
            const SizedBox(height: AppDimens.space12),
            TextField(
              controller: _room,
              decoration: const InputDecoration(
                labelText: 'Room id (optional)',
                hintText: 'Set when this door is a route\'s destination',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(
              _LandmarkDraft(
                displayName: name,
                labelText: _label.text.trim(),
                kind: _kind,
                roomId: _room.text.trim(),
              ),
            );
          },
          child: const Text('Place'),
        ),
      ],
    );
  }
}
