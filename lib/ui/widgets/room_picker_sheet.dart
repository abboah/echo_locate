import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/models/room_plan.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import 'app_search_field.dart';
import 'responsive.dart';
import 'room_plan_palette.dart';

/// Choosing a room to walk from or to.
///
/// Replaces a `DropdownButtonFormField`, which is the wrong control for this
/// entirely. A dropdown opens a floating menu the width of the field, sized to
/// its contents — on a floor with forty rooms that is a list nearly the height
/// of the screen, in 15-point text, with no way to search it and every entry
/// clipped to the width of half a row. It is also close to unusable with a
/// screen reader, which is the audience this screen exists for.
///
/// A sheet can be searched, can group rooms by what they are, gives every entry
/// a full-width target, and can say which one is currently chosen.
class RoomPickerSheet extends StatefulWidget {
  const RoomPickerSheet({
    super.key,
    required this.title,
    required this.rooms,
    this.selectedId,
  });

  final String title;
  final List<Room> rooms;
  final String? selectedId;

  /// Opens the picker, returning the chosen room id or null if dismissed.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required List<Room> rooms,
    String? selectedId,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // Tall enough to be worth opening, short enough that the floor behind it
      // stays visible — this screen is often used while looking at the map.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) =>
          RoomPickerSheet(title: title, rooms: rooms, selectedId: selectedId),
    );
  }

  @override
  State<RoomPickerSheet> createState() => _RoomPickerSheetState();
}

class _RoomPickerSheetState extends State<RoomPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Room> get _matches {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return widget.rooms;
    return [
      for (final room in widget.rooms)
        if (room.spokenName.toLowerCase().contains(needle) ||
            room.code.toLowerCase().contains(needle) ||
            room.category.title.toLowerCase().contains(needle))
          room,
    ];
  }

  /// Rooms under the kind of thing they are.
  ///
  /// A floor's rooms are not a flat list to somebody looking for one — "the
  /// lecture halls" and "the washrooms" are how people ask. Sorted by category
  /// title so the grouping is stable between openings.
  Map<RoomCategory, List<Room>> _grouped(List<Room> rooms) {
    final byCategory = <RoomCategory, List<Room>>{};
    for (final room in rooms) {
      byCategory.putIfAbsent(room.category, () => []).add(room);
    }
    for (final list in byCategory.values) {
      list.sort((a, b) => a.spokenName.compareTo(b.spokenName));
    }
    return Map.fromEntries(
      byCategory.entries.toList()
        ..sort((a, b) => a.key.title.compareTo(b.key.title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = _matches;
    final grouped = _grouped(matches);
    final gutter = Responsive.gutter(context);

    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the sheet clear of the keyboard when the search field has
        // focus; without it the list is behind it and the field is at the edge.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppDimens.space12),
            // Grab handle. Decorative, so it is hidden from the reader.
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                AppDimens.space16,
                gutter,
                AppDimens.space12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(PhosphorIconsRegular.x, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Only worth the space once the list is long enough to hunt
            // through; on a five-room floor the search field is noise.
            if (widget.rooms.length > 8)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: AppSearchField(
                  controller: _controller,
                  hint: 'Search rooms',
                  onChanged: (value) => setState(() => _query = value),
                  onClear: _query.isEmpty
                      ? null
                      : () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                ),
              ),
            const SizedBox(height: AppDimens.space8),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppDimens.space32),
                      child: Text(
                        'No room matches "$_query".',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        0,
                        gutter,
                        AppDimens.space16,
                      ),
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AppDimens.space12,
                              bottom: AppDimens.space4,
                            ),
                            child: Text(
                              entry.key.title.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final room in entry.value)
                            _RoomRow(
                              room: room,
                              selected: room.id == widget.selectedId,
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, required this.selected});

  final Room room;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = RoomPalette.of(theme.brightness);

    return Semantics(
      button: true,
      selected: selected,
      label: '${room.spokenName}, ${room.category.title}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
            onTap: () => Navigator.of(context).pop(room.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppDimens.space12,
                horizontal: AppDimens.space8,
              ),
              child: Row(
                children: [
                  // The category's own colour, the same one the room is drawn
                  // in on the map — so the list and the plan agree at a glance.
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.fillFor(room.category),
                      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                      border: Border.all(
                        color: palette.outline.withValues(alpha: 0.25),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      room.code,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.labelOn(palette.fillFor(room.category)),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Text(
                      room.spokenName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    const Icon(
                      PhosphorIconsFill.checkCircle,
                      size: 20,
                      color: AppColors.coral,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
