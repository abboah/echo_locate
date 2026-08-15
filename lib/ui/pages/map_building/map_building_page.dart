import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/map_building/bloc/map_building_cubit.dart';
import '../../../services/injection_container.dart';
import '../../widgets/section_label.dart';

/// What are you mapping?
///
/// Stands between "Map a building" and tracing because the index is
/// crowdsourced: a contributor standing in a building nobody has listed has to
/// be able to add it. Sending them to Explore only ever offers buildings
/// somebody already thought of, which is the one case mapping is not for.
class MapBuildingPage extends StatelessWidget {
  const MapBuildingPage({super.key, this.nextRoute = RouteNames.roomTrace});

  /// Where a chosen building goes next.
  ///
  /// This picker serves two entry points that mean different things.
  /// "Map a building" means tracing, and goes straight to the tool.
  /// **"Scan a space" means AR**, and the only place "Scan in AR" exists is the
  /// per-floor hub — so it goes there instead. Before this existed, every path
  /// out of this screen ended in tracing, and the scan entry point could not
  /// reach AR at all no matter what its card promised.
  final String nextRoute;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<MapBuildingCubit>()..load(),
      child: _MapBuildingView(nextRoute: nextRoute),
    );
  }
}

class _MapBuildingView extends StatelessWidget {
  const _MapBuildingView({required this.nextRoute});

  final String nextRoute;

  bool get _isScanning => nextRoute == RouteNames.buildingMapping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<MapBuildingCubit, MapBuildingState>(
      listenWhen: (before, after) =>
          before.status != after.status || before.error != after.error,
      listener: (context, state) {
        if (state.error != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.error!)));
        }
        final created = state.created;
        if (state.status == MapBuildingStatus.created && created != null) {
          // Replacing this screen rather than stacking on it: coming "back"
          // to a chooser you have already answered is a dead end.
          //
          // Deliberately no `extra`: roomTrace reads it as a floor id and the
          // hub reads it as a building name, so anything passed here is
          // misread by one of them. Left off, each opens its own sensible
          // default, which for a building just created is its first floor.
          context.pushReplacementNamed(
            nextRoute,
            pathParameters: {'id': created.id},
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(PhosphorIconsRegular.x),
              onPressed: () => context.pop(),
            ),
            title: const Text('Map a building'),
          ),
          body: SafeArea(
            child: state.status == MapBuildingStatus.creating
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(AppDimens.pageGutter),
                    children: [
                      Text(
                        'Which building are you in?',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppDimens.space4),
                      Text(
                        // Says what actually happens next, which now depends
                        // on which card opened this picker.
                        _isScanning
                            ? 'Add it if nobody has yet. Then pick a floor and '
                                  'walk its rooms in AR, tapping each corner.'
                            : 'Add it if nobody has yet. You will photograph '
                                  'the floor plan on its wall and trace its '
                                  'rooms onto it.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppDimens.space20),
                      const _NewBuildingForm(),
                      const SizedBox(height: AppDimens.space32),
                      if (state.listed.isNotEmpty) ...[
                        const SectionLabel('Or add to one already listed'),
                        const SizedBox(height: AppDimens.space8),
                        for (final building in state.listed)
                          _ListedBuilding(
                            building: building,
                            nextRoute: nextRoute,
                          ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _NewBuildingForm extends StatefulWidget {
  const _NewBuildingForm();

  @override
  State<_NewBuildingForm> createState() => _NewBuildingFormState();
}

class _NewBuildingFormState extends State<_NewBuildingForm> {
  final _name = TextEditingController();
  final _area = TextEditingController(text: 'KNUST, Kumasi');
  int _floors = 1;
  String _category = 'campus';

  static const _categories = ['campus', 'hospital', 'mall', 'office', 'other'];

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('A building nobody has added', style: theme.textTheme.labelSmall),
        const SizedBox(height: AppDimens.space8),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Building name',
            hintText: 'Great Hall Annexe',
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        TextField(
          controller: _area,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Area',
            hintText: 'KNUST, Kumasi',
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _category,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: [
                  for (final category in _categories)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? 'campus'),
              ),
            ),
            const SizedBox(width: AppDimens.space12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _floors,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Floors'),
                items: [
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: (value) => setState(() => _floors = value ?? 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space16),
        ElevatedButton.icon(
          onPressed: () => context.read<MapBuildingCubit>().create(
            name: _name.text,
            area: _area.text,
            floors: _floors,
            category: _category,
          ),
          icon: const Icon(PhosphorIconsFill.mapTrifold, size: 18),
          label: const Text('Add it and start tracing'),
        ),
        const SizedBox(height: AppDimens.space8),
        Text(
          'Floors can be traced one at a time — you do not have to do them all '
          'now.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ListedBuilding extends StatelessWidget {
  const _ListedBuilding({required this.building, required this.nextRoute});

  final Building building;
  final String nextRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(PhosphorIconsRegular.buildings, size: 22),
      title: Text(building.name, style: theme.textTheme.titleMedium),
      subtitle: Text(
        '${building.area} · ${building.floorsCount} floors',
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(
        PhosphorIconsRegular.caretRight,
        size: 18,
        color: AppColors.coral,
      ),
      // Wherever this picker was opened to go — tracing for "Map a building",
      // the per-floor hub for "Scan a space". No `extra`: that slot is a floor
      // id for tracing and a building name for the hub, and guessing wrong
      // sends one of them a string it will misread.
      onTap: () => context.pushReplacementNamed(
        nextRoute,
        pathParameters: {'id': building.id},
      ),
    );
  }
}
