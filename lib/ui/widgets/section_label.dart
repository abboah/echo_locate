import 'package:flutter/material.dart';

import '../../core/theme/app_dimens.dart';

/// Muted uppercase section header ("RECENTLY MAPPED", "ROOMS ON FLOOR 2").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w600,
      ),
    );
    if (trailing == null) return label;
    // The heading takes the room that is left, not half the row.
    //
    // Both children used to be unflexed, so on a narrow phone a long heading
    // and its action overflowed rather than one of them giving way — the
    // heading is the part that can shrink, and the action is a fixed control.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: label),
        const SizedBox(width: AppDimens.space8),
        trailing!,
      ],
    );
  }
}
