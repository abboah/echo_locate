import 'package:flutter/material.dart';

/// A text field for a dialog or bottom sheet that owns its own controller.
///
/// ## The bug this exists to prevent
///
/// The obvious way to get text out of a sheet is to make a
/// `TextEditingController` beside the `showModalBottomSheet` call, read
/// `.text` when it returns, and dispose it:
///
/// ```dart
/// final label = TextEditingController();
/// final ok = await showModalBottomSheet<bool>(...);
/// if (ok) use(label.text);
/// label.dispose();            // ← throws
/// ```
///
/// It throws **"A TextEditingController was used after being disposed"**. The
/// future completes when the sheet is *dismissed*, not when it is gone: the
/// exit animation is still running, the `TextField` is still mounted, and it
/// rebuilds against a controller that has just been destroyed. It is timing
/// dependent, so it survives every test that does not pump the animation, and
/// it took driving the app on a phone to surface.
///
/// Holding the controller inside the field fixes it by construction — the
/// controller lives exactly as long as the widget does, and the caller keeps a
/// plain `String` that no lifecycle can invalidate.
class SheetTextField extends StatefulWidget {
  const SheetTextField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initial = '',
    this.hint,
    this.keyboardType,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.minLines,
    this.maxLines = 1,
    this.monospace = false,
  });

  final String label;
  final ValueChanged<String> onChanged;
  final String initial;
  final String? hint;
  final TextInputType? keyboardType;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final int? minLines;
  final int? maxLines;

  /// For the evaluation screen's ground-truth box, where alignment helps.
  final bool monospace;

  @override
  State<SheetTextField> createState() => _SheetTextFieldState();
}

class _SheetTextFieldState extends State<SheetTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    // Runs when this widget leaves the tree, which is after the sheet has
    // finished animating out — the whole point.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    autofocus: widget.autofocus,
    keyboardType: widget.keyboardType,
    textCapitalization: widget.textCapitalization,
    minLines: widget.minLines,
    maxLines: widget.maxLines,
    style: widget.monospace ? const TextStyle(fontFamily: 'monospace') : null,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      border: widget.monospace ? const OutlineInputBorder() : null,
    ),
    onChanged: widget.onChanged,
  );
}
