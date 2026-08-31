import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/models/building.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/repository_mixin.dart';
import '../../features/buildings/building_repository.dart';
import '../../services/injection_container.dart';
import 'responsive.dart';

/// What changed, so a list knows whether to reload itself.
enum BuildingChange { none, renamed, deleted }

/// Renaming or removing a building, from wherever it is listed.
///
/// Both actions belong together and both belong on the lists. The index is
/// crowdsourced, so a building's name is whatever the first contributor typed
/// — and anybody who can add one by mistake, or add a test entry, needs a way
/// to take it back out. Until this existed the entry sat in everybody's
/// Explore list forever.
Future<BuildingChange> showBuildingActions(
  BuildContext context,
  Building building,
) async {
  final action = await showModalBottomSheet<_BuildingAction>(
    context: context,
    builder: (_) => _BuildingActionsSheet(building: building),
  );
  if (action == null) return BuildingChange.none;
  // Separate from the null check so the analyzer can see the guard: the sheet
  // is awaited, and the list underneath it may have gone in the meantime.
  if (!context.mounted) return BuildingChange.none;

  // Plain branching rather than a `switch` expression: an `await` in either
  // arm makes the analyzer treat the other as sitting after an async gap, and
  // it cannot see that only one of them runs.
  if (action == _BuildingAction.rename) return _rename(context, building);
  return _delete(context, building);
}

enum _BuildingAction { rename, delete }

class _BuildingActionsSheet extends StatelessWidget {
  const _BuildingActionsSheet({required this.building});

  final Building building;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              Responsive.gutter(context),
              AppDimens.space20,
              Responsive.gutter(context),
              AppDimens.space8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(building.name, style: theme.textTheme.titleLarge),
                Text(building.area, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.pencilSimple, size: 20),
            title: Text('Rename', style: theme.textTheme.titleMedium),
            subtitle: Text(
              'Correct what this building is called',
              style: theme.textTheme.bodyMedium,
            ),
            onTap: () => Navigator.of(context).pop(_BuildingAction.rename),
          ),
          ListTile(
            leading: const Icon(
              PhosphorIconsRegular.trash,
              size: 20,
              color: AppColors.error,
            ),
            title: Text(
              'Remove building',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.error,
              ),
            ),
            subtitle: Text(
              'Deletes its floors and traced plans too',
              style: theme.textTheme.bodyMedium,
            ),
            onTap: () => Navigator.of(context).pop(_BuildingAction.delete),
          ),
          const SizedBox(height: AppDimens.space8),
        ],
      ),
    );
  }
}

Future<BuildingChange> _rename(BuildContext context, Building building) async {
  final messenger = ScaffoldMessenger.of(context);
  final edited = await showDialog<({String name, String area})>(
    context: context,
    builder: (_) =>
        RenameBuildingDialog(name: building.name, area: building.area),
  );
  if (edited == null) return BuildingChange.none;

  try {
    final renamed = await getIt<BuildingRepository>().rename(
      building.id,
      name: edited.name,
      area: edited.area,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Renamed to ${renamed.name}.')));
    return BuildingChange.renamed;
  } catch (error) {
    // Says which building could not be renamed and why. The rename used to
    // fail silently — a bare `update` filtered away by RLS reports success —
    // so the screen claimed the new name and the building kept the old one.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(OperationFailure.from(error).message)),
      );
    return BuildingChange.none;
  }
}

Future<BuildingChange> _delete(BuildContext context, Building building) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Text('Remove ${building.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The building, its floors and every plan traced on them are '
              'deleted for everybody.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppDimens.space8),
            Text(
              // The rule, stated before the attempt rather than as an error
              // afterwards.
              'Only works on a building you added, and only while nobody else '
              'has mapped a floor here.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return BuildingChange.none;

  try {
    await getIt<BuildingRepository>().delete(building.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${building.name} removed.')));
    return BuildingChange.deleted;
  } catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(OperationFailure.from(error).message)),
      );
    return BuildingChange.none;
  }
}

/// Correcting what a building is called.
///
/// Public and shared: the building screen's app bar opens the same dialog, and
/// two copies would drift on the one line that matters — the warning that the
/// floors stay put.
class RenameBuildingDialog extends StatefulWidget {
  const RenameBuildingDialog({
    super.key,
    required this.name,
    required this.area,
  });

  final String name;
  final String area;

  @override
  State<RenameBuildingDialog> createState() => _RenameBuildingDialogState();
}

class _RenameBuildingDialogState extends State<RenameBuildingDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _area = TextEditingController(text: widget.area);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(
      context,
    ).pop((name: _name.text.trim(), area: _area.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename building'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'A building needs a name.'
                  : null,
            ),
            const SizedBox(height: AppDimens.space12),
            TextFormField(
              controller: _area,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Area'),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppDimens.space12),
            Text(
              // The one surprising thing about this edit, said before it
              // happens rather than wondered about afterwards.
              'The floors and plans already traced here stay with the '
              'building.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
