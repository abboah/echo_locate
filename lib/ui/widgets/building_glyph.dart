import 'package:flutter/material.dart';

import '../../core/theme/app_dimens.dart';

/// Rounded-square building illustration used on cards and list tiles.
/// `glyph` comes from `Building.glyph`.
class BuildingGlyph extends StatelessWidget {
  const BuildingGlyph(this.glyph, {super.key, this.size = 64});

  final String glyph;
  final double size;

  static IconData iconFor(String glyph) => switch (glyph) {
        'door' => Icons.meeting_room_outlined,
        'home' => Icons.home_outlined,
        'hall' => Icons.account_balance_outlined,
        'book' => Icons.menu_book_outlined,
        _ => Icons.apartment_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Icon(
        iconFor(glyph),
        size: size * 0.45,
        color: theme.textTheme.bodyMedium?.color,
      ),
    );
  }
}
