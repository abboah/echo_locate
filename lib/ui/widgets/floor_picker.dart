import 'package:flutter/material.dart';

import '../../core/models/building.dart' show BuildingFloor;

/// Chooses which floor of a building a screen is working on.
///
/// Shared by capture, the editor and the evaluation screen because all three
/// had the same gap: every one of them took `floors.first` or a hard-coded
/// `'floor-g'`, so **no floor above the ground could be reached at all**. A
/// multi-storey building could be mapped exactly once, on its ground floor.
///
/// Disabled rather than hidden when [enabled] is false — capture switches it
/// off once rooms have been placed, and a control that vanishes leaves somebody
/// hunting for it rather than understanding why it cannot be used.
class FloorPicker extends StatelessWidget {
  const FloorPicker({
    super.key,
    required this.floors,
    required this.selectedId,
    required this.onChanged,
    this.enabled = true,
    this.disabledReason,
  });

  final List<BuildingFloor> floors;
  final String? selectedId;
  final ValueChanged<String> onChanged;
  final bool enabled;

  /// Shown under the picker when it is disabled, so "why can I not change
  /// this" has an answer on screen.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    // One floor is not a choice, and a dropdown offering it is furniture.
    if (floors.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final value = floors.any((f) => f.id == selectedId)
        ? selectedId
        : floors.first.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Floor', isDense: true),
          items: [
            for (final floor in floors)
              DropdownMenuItem(value: floor.id, child: Text(_label(floor))),
          ],
          onChanged: enabled
              ? (id) {
                  if (id != null) onChanged(id);
                }
              : null,
        ),
        if (!enabled && disabledReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(disabledReason!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  /// `'G'` reads as "Ground", a bare number as "Floor 2".
  static String _label(BuildingFloor floor) {
    final label = floor.label.trim();
    if (label.isEmpty) return 'Floor';
    if (label.toUpperCase() == 'G') return 'Ground floor';
    return 'Floor $label';
  }
}
