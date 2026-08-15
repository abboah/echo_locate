import 'package:flutter/material.dart';

import '../../core/theme/app_dimens.dart';

/// The padded, scrollable body of a modal bottom sheet.
///
/// ## The bug this exists to prevent
///
/// The obvious way to write one of these sheets is a `Padding` holding a
/// `Column(mainAxisSize: MainAxisSize.min)`, with `viewInsets.bottom` added to
/// the bottom padding so the keyboard does not cover the field:
///
/// ```dart
/// Padding(
///   padding: EdgeInsets.only(
///     bottom: MediaQuery.of(context).viewInsets.bottom + 16,
///     ...
///   ),
///   child: Column(mainAxisSize: MainAxisSize.min, children: [...]),
/// )
/// ```
///
/// That handles the keyboard *overlapping* the sheet but not the keyboard
/// *shrinking* it. On a short screen the room-category sheet is fifteen chips,
/// a text field and two buttons; raise a keyboard under it and the column wants
/// more height than is left, so it overflows — the yellow-and-black stripe,
/// with the confirm button clipped underneath it and untappable. It only
/// appears once somebody taps the optional name field, which is why it survived
/// the tests and turned up while driving the app on a phone.
///
/// Making the content scroll fixes it for every sheet at once: the column keeps
/// its natural height when it fits, and scrolls when the keyboard takes the
/// room. [SafeArea] covers the gesture bar, which the hand-written paddings
/// were also missing.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.only(
        left: AppDimens.space16,
        right: AppDimens.space16,
        top: AppDimens.space16,
        // Lifts the content clear of the keyboard; the scroll view above
        // absorbs whatever height that leaves.
        bottom: MediaQuery.of(context).viewInsets.bottom + AppDimens.space16,
      ),
      child: child,
    ),
  );
}
