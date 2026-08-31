import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_dimens.dart';

/// Rounded search input used on Home and Explore.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onTap,
    this.onClear,
    this.readOnly = false,
    this.autofocus = false,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  /// Shows a clear button when non-null. Null means there is nothing to clear,
  /// so no button appears and the field keeps its full width.
  final VoidCallback? onClear;

  final bool readOnly;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      readOnly: readOnly,
      autofocus: autofocus,
      onTap: onTap,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      // Named for the screen reader: the hint is placeholder text, which
      // TalkBack stops reading the moment there is a character in the field.
      decoration: InputDecoration(
        hintText: hint,
        labelText: null,
        prefixIcon: Icon(
          PhosphorIconsRegular.magnifyingGlass,
          size: 20,
          color: theme.textTheme.bodyMedium?.color,
        ),
        suffixIcon: onClear == null
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(PhosphorIconsRegular.x, size: 18),
                onPressed: onClear,
              ),
        // Keeps the field on the theme's input shape while giving the prefix
        // icon room; without it the icon crowds the first character.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space12,
          vertical: AppDimens.space12,
        ),
      ),
    );
  }
}
