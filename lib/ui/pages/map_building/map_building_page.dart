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
  const MapBuildingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<MapBuildingCubit>()..load(),
      child: const _MapBuildingView(),
    );
  }
}

class _MapBuildingView extends StatelessWidget {
  const _MapBuildingView();

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
          // Straight into tracing, replacing this screen: coming "back" to a
          // chooser you have already answered is a dead end.
          context.pushReplacementNamed(
            RouteNames.planTrace,
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
                        'Add it if nobody has yet. You will photograph the '
                        'floor plan on its wall and tap the landmarks onto it.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppDimens.space20),
                      const _NewBuildingForm(),
                      const SizedBox(height: AppDimens.space32),
                      if (state.listed.isNotEmpty) ...[
                        const SectionLabel('Or add to one already listed'),
                        const SizedBox(height: AppDimens.space8),
                        for (final building in state.listed)
                          _ListedBuilding(building: building),
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
  const _ListedBuilding({required this.building});

  final Building building;

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
      onTap: () => context.pushReplacementNamed(
        RouteNames.planTrace,
        pathParameters: {'id': building.id},
      ),
    );
  }
}
