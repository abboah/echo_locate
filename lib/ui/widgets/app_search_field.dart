import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Rounded search input used on Home and Explore.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: readOnly,
      autofocus: autofocus,
      onTap: onTap,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(
          PhosphorIconsRegular.magnifyingGlass,
          size: 20,
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    );
  }
}
