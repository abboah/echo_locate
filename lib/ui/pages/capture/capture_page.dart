import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart';
import '../../../core/models/landmark.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/buildings/building_repository.dart';
import '../../../features/capture/bloc/capture_bloc.dart';
import '../../../features/profile/profile_repository.dart';
import '../../../features/routing/route_repository.dart';
import '../../../services/injection_container.dart';
import '../../../services/motion/stride_profile.dart';

/// Recording a building by walking it once.
///
/// The contributor confirms the sign they are standing at, walks to the next
/// one while the phone counts steps, taps the turn they took and types what
/// they would tell someone else. Fifteen to twenty minutes buys a floor's
/// worth of directions — and the floor plan, which is derived from the same
/// walk rather than sensed.
class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.buildingId});

  final String buildingId;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

/// What the capture needs before it can start: which floors exist, what has
/// already been recorded here, and how long this contributor's step is.
class _CaptureContext {
  const _CaptureContext({
    required this.floors,
    required this.known,
    required this.stride,
  });

  final List<BuildingFloor> floors;
  final List<Landmark> known;
  final StrideProfile stride;
}

class _CapturePageState extends State<CapturePage> {
  late final Future<_CaptureContext> _context = _load();
  BuildingFloor? _floor;

  Future<_CaptureContext> _load() async {
    final floors = await getIt<BuildingRepository>().floorsOf(widget.buildingId);
    // Existing landmarks are advisory: a sign already recorded should be
    // captured under the name it already has, or the upload creates a second
    // landmark standing in the same spot.
    List<Landmark> known;
    try {
      known = await getIt<RouteRepository>().landmarksOf(widget.buildingId);
    } catch (_) {
      known = const [];
    }

    var stride = StrideProfile.fallback;
    try {
      final metres =
          (await getIt<ProfileRepository>().currentProfile()).strideLengthM;
      if (metres != null) {
        final calibrated =
            StrideProfile(metres: metres, source: StrideSource.calibrated);
        if (calibrated.isPlausible) stride = calibrated;
      }
    } catch (_) {
      // Uncalibrated: the walk is still worth recording, and the raw step
      // count is stored alongside so the distances can be re-derived later.
    }

    return _CaptureContext(floors: floors, known: known, stride: stride);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CaptureContext>(
      future: _context,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Shell(
            child: _Message(
              icon: PhosphorIconsRegular.cloudSlash,
              title: 'Could not open this building',
              detail: 'Recording a route needs its floor list. Try again '
                  'with a connection.',
            ),
          );
        }
        final ready = snapshot.data;
        if (ready == null) {
          return const _Shell(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (ready.floors.isEmpty) {
          return const _Shell(
            child: _Message(
              icon: PhosphorIconsRegular.stairs,
              title: 'This building has no floors listed',
              detail: 'Landmarks belong to a floor, so one has to exist '
                  'before a route can be recorded.',
            ),
          );
        }

        final floor = _floor;
        if (floor == null) {
          return _Shell(
            child: _FloorChooser(
              floors: ready.floors,
              onChosen: (chosen) => setState(() => _floor = chosen),
            ),
          );
        }

        return BlocProvider(
          create: (_) => getIt<CaptureBloc>()
            ..add(
              CaptureStarted(
                buildingId: widget.buildingId,
                floorId: floor.id,
                stride: ready.stride,
                knownLandmarks: ready.known,
              ),
            ),
          child: _CaptureView(floor: floor),
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(PhosphorIconsRegular.x),
            onPressed: () => context.pop(),
          ),
          title: const Text('Record a route'),
        ),
        body: SafeArea(child: child),
      );
}

class _FloorChooser extends StatelessWidget {
  const _FloorChooser({required this.floors, required this.onChosen});

  final List<BuildingFloor> floors;
  final ValueChanged<BuildingFloor> onChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppDimens.space16),
      children: [
        Text('Which floor are you starting on?',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppDimens.space8),
        Text(
          'Every landmark you record belongs to this floor. Take the stairs '
          'mid-route if you need to — the leg is recorded, the floor stays '
          'as recorded here.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppDimens.space16),
        for (final floor in floors)
          Card(
            child: ListTile(
              title: Text('Floor ${floor.label}'),
              subtitle: Text('${floor.rooms.length} rooms listed'),
              trailing: const Icon(PhosphorIconsRegular.caretRight),
              // A floor cached before floors carried ids cannot be uploaded
              // against; better to refuse than to attach landmarks to nothing.
              enabled: floor.id.isNotEmpty,
              onTap: floor.id.isEmpty ? null : () => onChosen(floor),
            ),
          ),
      ],
    );
  }
}

class _CaptureView extends StatelessWidget {
  const _CaptureView({required this.floor});

  final BuildingFloor floor;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CaptureBloc, CaptureState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(PhosphorIconsRegular.x),
              onPressed: () => _confirmExit(context, state),
            ),
            title: Text('Floor ${floor.label}'),
            actions: [
              if (state.canFinish && state.status != CaptureStatus.saved)
                TextButton(
                  onPressed: () => _finish(context, state),
                  child: const Text('Finish'),
                ),
            ],
          ),
          body: SafeArea(
            child: switch (state.status) {
              CaptureStatus.preparing =>
                const Center(child: CircularProgressIndicator()),
              CaptureStatus.saving =>
                const Center(child: CircularProgressIndicator()),
              CaptureStatus.saved => _Saved(state: state),
              CaptureStatus.describing => _DescribeLeg(state: state),
              _ => _Sighting(state: state),
            },
          ),
        );
      },
    );
  }

  Future<void> _confirmExit(BuildContext context, CaptureState state) async {
    if (state.steps.isEmpty || state.status == CaptureStatus.saved) {
      context.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this walk?'),
        content: Text(
          '${state.steps.length} '
          '${state.steps.length == 1 ? 'leg' : 'legs'} recorded. Leaving now '
          'throws the walk away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep recording'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && context.mounted) context.pop();
  }

  Future<void> _finish(BuildContext context, CaptureState state) async {
    final bloc = context.read<CaptureBloc>();
    final room = await showDialog<Room>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Which room does this route end at?'),
        children: [
          for (final room in floor.rooms)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(room),
              child: Text(room.name),
            ),
        ],
      ),
    );
    if (room == null) return;
    bloc.add(CaptureFinished(destinationRoomId: room.id));
  }
}

class _Sighting extends StatelessWidget {
  const _Sighting({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = state.landmarks.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(AppDimens.space16),
      children: [
        Text(
          first
              ? 'Point the camera at the sign where the route starts'
              : 'Walk to the next sign',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppDimens.space8),
        if (!first)
          Row(
            children: [
              const Icon(PhosphorIconsFill.footprints,
                  size: 18, color: AppColors.coral),
              const SizedBox(width: AppDimens.space8),
              Text(
                state.stepCounting
                    ? '${state.stepsThisLeg} steps since '
                        '${state.landmarks.last.displayName}'
                    : 'No step counter — you will be asked for the distance',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        const SizedBox(height: AppDimens.space16),
        if (!state.signReading)
          const _Message(
            icon: PhosphorIconsRegular.cameraSlash,
            title: 'No camera',
            detail: 'Type each landmark instead — the route still records.',
          ),
        if (state.proposals.isNotEmpty) ...[
          Text('The camera can read:', style: theme.textTheme.labelSmall),
          const SizedBox(height: AppDimens.space8),
          for (final proposal in state.proposals)
            Card(
              child: ListTile(
                leading: Icon(
                  proposal.existing == null
                      ? PhosphorIconsRegular.textAa
                      : PhosphorIconsFill.mapPin,
                  color: proposal.existing == null ? null : AppColors.coral,
                ),
                title: Text(proposal.text),
                subtitle: proposal.existing == null
                    ? null
                    : Text('Already recorded as '
                        '"${proposal.existing!.displayName}"'),
                onTap: () => _addLandmark(context, state, proposal: proposal),
              ),
            ),
        ],
        const SizedBox(height: AppDimens.space16),
        OutlinedButton.icon(
          onPressed: () => _addLandmark(context, state),
          icon: const Icon(PhosphorIconsRegular.plus, size: 18),
          label: Text(first ? 'Type the starting sign' : 'Type this sign'),
        ),
        const SizedBox(height: AppDimens.space24),
        if (state.steps.isNotEmpty) _Recorded(state: state),
        if (state.error != null) ...[
          const SizedBox(height: AppDimens.space16),
          Text(
            state.error!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  Future<void> _addLandmark(
    BuildContext context,
    CaptureState state, {
    CaptureProposal? proposal,
  }) async {
    final bloc = context.read<CaptureBloc>();
    final result = await showModalBottomSheet<CaptureLandmarkAccepted>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _LandmarkSheet(proposal: proposal),
    );
    if (result != null) bloc.add(result);
  }
}

class _LandmarkSheet extends StatefulWidget {
  const _LandmarkSheet({this.proposal});

  final CaptureProposal? proposal;

  @override
  State<_LandmarkSheet> createState() => _LandmarkSheetState();
}

class _LandmarkSheetState extends State<_LandmarkSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.proposal?.existing?.labelText ?? widget.proposal?.text ?? '',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.proposal?.existing?.displayName ?? widget.proposal?.text ?? '',
  );
  LandmarkKind _kind =
      LandmarkKind.sign;

  @override
  void initState() {
    super.initState();
    final existing = widget.proposal?.existing;
    if (existing != null) _kind = existing.kind;
  }

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: AppDimens.space16,
        right: AppDimens.space16,
        top: AppDimens.space16,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppDimens.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This landmark', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.space12),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'What the sign says',
              helperText: 'What the camera must read here, e.g. 204',
            ),
          ),
          const SizedBox(height: AppDimens.space12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'What to call it out loud',
              helperText: 'Spoken on arrival, e.g. Reading Hall door',
            ),
          ),
          const SizedBox(height: AppDimens.space16),
          Wrap(
            spacing: AppDimens.space8,
            children: [
              for (final kind in LandmarkKind.values)
                ChoiceChip(
                  label: Text(kind.name),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.space16),
          ElevatedButton(
            onPressed: () {
              final label = _label.text.trim();
              final name = _name.text.trim();
              if (label.isEmpty || name.isEmpty) return;
              Navigator.of(context).pop(
                CaptureLandmarkAccepted(
                  labelText: label,
                  displayName: name,
                  kind: _kind,
                ),
              );
            },
            child: const Text("I'm standing here"),
          ),
        ],
      ),
    );
  }
}

class _DescribeLeg extends StatefulWidget {
  const _DescribeLeg({required this.state});

  final CaptureState state;

  @override
  State<_DescribeLeg> createState() => _DescribeLegState();
}

class _DescribeLegState extends State<_DescribeLeg> {
  final _instruction = TextEditingController();
  final _distance = TextEditingController();
  int _turnDeg = 0;

  /// The taps a contributor is offered instead of a compass reading. Indoor
  /// magnetic interference makes a heading worse than useless, and a person
  /// always knows which way they just turned.
  static const _turns = <String, int>{
    'Straight': 0,
    'Left': -90,
    'Right': 90,
    'Sharp left': -135,
    'Sharp right': 135,
  };

  @override
  void dispose() {
    _instruction.dispose();
    _distance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final from = state.landmarks.last.displayName;
    final to = state.pendingLandmark?.displayName ?? '';

    return ListView(
      padding: const EdgeInsets.all(AppDimens.space16),
      children: [
        Text('$from → $to', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppDimens.space8),
        Text(
          state.needsManualDistance
              ? (state.stepCounting
                  ? 'No steps were counted for this leg — enter how far you '
                      'walked.'
                  : 'No step counter — enter the distance you walked.')
              : '${state.pendingSteps} steps · about '
                  '${state.stride.distanceFor(state.pendingSteps).toStringAsFixed(1)} m',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppDimens.space16),
        Text('Which way did you turn to start this leg?',
            style: theme.textTheme.labelSmall),
        const SizedBox(height: AppDimens.space8),
        Wrap(
          spacing: AppDimens.space8,
          children: [
            for (final entry in _turns.entries)
              ChoiceChip(
                label: Text(entry.key),
                selected: _turnDeg == entry.value,
                onSelected: (_) => setState(() => _turnDeg = entry.value),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.space16),
        TextField(
          controller: _instruction,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'What would you tell someone walking this?',
            helperText: 'Spoken as-is, e.g. "straight past the help desk"',
          ),
        ),
        if (state.needsManualDistance) ...[
          const SizedBox(height: AppDimens.space12),
          TextField(
            controller: _distance,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Distance in metres',
            ),
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: AppDimens.space12),
          Text(
            state.error!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppDimens.space24),
        ElevatedButton(
          onPressed: () {
            final instruction = _instruction.text.trim();
            if (instruction.isEmpty) return;
            context.read<CaptureBloc>().add(
                  CaptureLegDescribed(
                    turnDeg: _turnDeg,
                    instruction: instruction,
                    distanceM: state.needsManualDistance
                        ? double.tryParse(_distance.text.trim())
                        : null,
                  ),
                );
          },
          child: const Text('Save this leg'),
        ),
      ],
    );
  }
}

class _Recorded extends StatelessWidget {
  const _Recorded({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recorded so far · ${state.totalDistanceM.round()} m',
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: AppDimens.space8),
        for (final step in state.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.space4),
            child: Text(
              '${step.seq}. ${step.instruction} '
              '(${step.distanceM.round()} m)',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Saved extends StatelessWidget {
  const _Saved({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsFill.checkCircle,
                size: 56, color: AppColors.coral),
            const SizedBox(height: AppDimens.space16),
            Text('Route uploaded', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppDimens.space8),
            Text(
              '${state.steps.length} '
              '${state.steps.length == 1 ? 'leg' : 'legs'} · '
              '${state.totalDistanceM.round()} m. It is on the building’s map '
              'now, and anyone can be guided along it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppDimens.space24),
            ElevatedButton(
              onPressed: () => context.pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

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
            const SizedBox(height: AppDimens.space12),
            Text(title, textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.space8),
            Text(detail,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
