import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart' show BuildingFloor;
import '../../../core/models/room_plan.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/buildings/building_repository.dart';
import '../../../features/room_trace/room_plan_repository.dart';
import '../../../services/evaluation/plan_evaluation.dart';
import '../../../services/injection_container.dart';
import '../../widgets/floor_picker.dart';

/// Running the §10 field evaluation on a traced floor.
///
/// Built to be used **in the building**, standing in front of the board it is
/// measuring against: read the adjacencies off the plan on the wall, type them
/// in, and get back precision and recall over the doors plus the list of routes
/// to walk. The report copies out as Markdown for the write-up.
///
/// The one thing it will not do is produce a number it has not measured. With
/// no ground truth typed in, the topology section says "not measured" rather
/// than defaulting to something flattering — a distinction that matters more
/// here than anywhere else in the app, because these figures get published.
class PlanEvaluationPage extends StatefulWidget {
  const PlanEvaluationPage({
    super.key,
    required this.buildingId,
    required this.floorId,
  });

  final String buildingId;
  final String floorId;

  @override
  State<PlanEvaluationPage> createState() => _PlanEvaluationPageState();
}

class _PlanEvaluationPageState extends State<PlanEvaluationPage> {
  final TextEditingController _truth = TextEditingController();

  RoomPlan? _plan;
  EvaluationReport? _report;
  bool _loading = true;
  String? _error;

  List<BuildingFloor> _floors = const [];
  late String _floorId = widget.floorId;

  @override
  void initState() {
    super.initState();
    _loadFloors();
    _load();
  }

  /// The building's floors, so a floor above the ground can be measured.
  Future<void> _loadFloors() async {
    try {
      final floors = await getIt<BuildingRepository>().floorsOf(
        widget.buildingId,
      );
      if (!mounted || floors.isEmpty) return;
      setState(() {
        _floors = floors;
        if (!floors.any((f) => f.id == _floorId)) _floorId = floors.first.id;
      });
      await _load();
    } catch (_) {
      // A floor list that will not load is not a reason to refuse to evaluate
      // the floor already asked for.
    }
  }

  @override
  void dispose() {
    _truth.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final plan = await getIt<RoomPlanRepository>().planFor(
        widget.buildingId,
        _floorId,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _report = null;
        _loading = false;
        _error = plan == null ? 'No traced plan for this floor yet.' : null;
      });
      if (plan != null) _run();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _run() {
    final plan = _plan;
    if (plan == null) return;
    setState(() {
      _report = PlanEvaluation.run(
        plan,
        groundTruth: PlanGroundTruth.parse(_truth.text),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(PhosphorIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Evaluate this floor'),
        actions: [
          if (report != null)
            IconButton(
              tooltip: 'Copy the report',
              icon: const Icon(PhosphorIcons.copy),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: report.toMarkdown()),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report copied as Markdown')),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppDimens.space16),
              children: [
                if (_error != null)
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                if (_floors.length > 1) ...[
                  FloorPicker(
                    floors: _floors,
                    selectedId: _floorId,
                    onChanged: (id) {
                      setState(() {
                        _floorId = id;
                        _loading = true;
                      });
                      _load();
                    },
                  ),
                  const SizedBox(height: AppDimens.space16),
                ],
                if (_plan != null) ...[
                  Text('Ground truth', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    'Copy the doors off the board on the wall — one pair of '
                    'room names per line, separated by a comma. Use whatever '
                    'the board calls each room.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppDimens.space8),
                  TextField(
                    controller: _truth,
                    minLines: 4,
                    maxLines: 10,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText:
                          'Corridor, Reading Hall\n'
                          'Corridor, 204\n'
                          '# lines starting with # are notes',
                    ),
                  ),
                  const SizedBox(height: AppDimens.space12),
                  FilledButton.icon(
                    onPressed: _run,
                    icon: const Icon(PhosphorIcons.calculator),
                    label: const Text('Measure'),
                  ),
                  const SizedBox(height: AppDimens.space24),
                ],
                if (report != null) ..._results(theme, report),
              ],
            ),
    );
  }

  List<Widget> _results(ThemeData theme, EvaluationReport report) {
    final score = report.topology;

    return [
      Text('Topological accuracy', style: theme.textTheme.titleMedium),
      const SizedBox(height: AppDimens.space8),
      if (score == null)
        Container(
          padding: const EdgeInsets.all(AppDimens.space12),
          decoration: BoxDecoration(
            color: AppColors.warningSoft,
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          ),
          child: Text(
            'Not measured — no ground truth typed in yet. Do not report a '
            'figure without it.',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.ink),
          ),
        )
      else ...[
        Row(
          children: [
            _Metric(label: 'Precision', value: score.precision),
            _Metric(label: 'Recall', value: score.recall),
            _Metric(label: 'F1', value: score.f1),
          ],
        ),
        const SizedBox(height: AppDimens.space12),
        if (score.missing.isNotEmpty)
          _Findings(
            title: 'Missing from the plan',
            subtitle: 'The board shows these doors and the plan does not.',
            pairs: score.missing,
            colour: AppColors.error,
          ),
        if (score.spurious.isNotEmpty)
          _Findings(
            title: 'Not on the board',
            subtitle: 'Check the building itself — boards omit real doors.',
            pairs: score.spurious,
            colour: AppColors.warning,
          ),
      ],
      if (report.unreachableRooms.isNotEmpty) ...[
        const SizedBox(height: AppDimens.space16),
        Text('Drawn but unreachable', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppDimens.space4),
        for (final room in report.unreachableRooms)
          Text('· $room', style: theme.textTheme.bodyMedium),
      ],
      const SizedBox(height: AppDimens.space24),
      Text('Routes to walk', style: theme.textTheme.titleMedium),
      const SizedBox(height: AppDimens.space4),
      Text(
        'A left/right swap passes every test in this project. Walking these is '
        'the only thing that finds one.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: AppDimens.space8),
      for (var i = 0; i < report.routes.length; i++)
        _RouteCard(index: i + 1, audit: report.routes[i]),
    ];
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            '${(value * 100).toStringAsFixed(1)}%',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.coral,
            ),
          ),
        ],
      ),
    );
  }
}

class _Findings extends StatelessWidget {
  const _Findings({
    required this.title,
    required this.subtitle,
    required this.pairs,
    required this.colour,
  });

  final String title;
  final String subtitle;
  final Set<({String a, String b})> pairs;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(color: colour),
          ),
          Text(subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppDimens.space4),
          // Named, not just counted: the number is a grade, the pair is a fix.
          for (final pair in pairs)
            Text('· ${pair.a} ↔ ${pair.b}', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.index, required this.audit});

  final int index;
  final RouteAudit audit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.space8),
      child: ExpansionTile(
        title: Text(
          '$index. ${audit.fromName} → ${audit.toName}',
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          audit.reachable
              ? '${audit.roomsPassed} rooms'
                    '${audit.ordinalsTrusted ? "" : " · ordinals withheld"}'
              : 'No route',
          style: theme.textTheme.bodySmall?.copyWith(
            color: audit.reachable && audit.ordinalsTrusted
                ? null
                : AppColors.warning,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.space16,
              0,
              AppDimens.space16,
              AppDimens.space12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!audit.reachable)
                  Text(
                    'The plan does not connect these two rooms.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  for (final instruction in audit.instructions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '· $instruction',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
