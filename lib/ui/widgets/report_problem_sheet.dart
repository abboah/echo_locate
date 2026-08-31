import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_dimens.dart';
import '../../features/feedback/feedback_repository.dart';
import 'responsive.dart';

/// Telling somebody something is wrong.
///
/// Worth more in this app than in most. The people it is built for cannot
/// point at the screen and show somebody what happened, and a wrong map is
/// invisible from the outside — the app will confidently guide somebody into a
/// wall and report success. This is the only channel that says otherwise.
///
/// Pops a [FeedbackReport], or null if dismissed. Sending is the caller's job,
/// so the sheet has no repository and no async state to get wrong.
class ReportProblemSheet extends StatefulWidget {
  const ReportProblemSheet({super.key, this.buildingId});

  /// Pre-filled when the report is opened from a building or a walk, so a map
  /// error arrives attached to the map it is about.
  final String? buildingId;

  @override
  State<ReportProblemSheet> createState() => _ReportProblemSheetState();
}

class _ReportProblemSheetState extends State<ReportProblemSheet> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  FeedbackKind _kind = FeedbackKind.problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      FeedbackReport(
        kind: _kind,
        message: _controller.text.trim(),
        buildingId: widget.buildingId,
        // Enough to tie a fault to a build without asking the user anything.
        context: 'debug=$kDebugMode; platform=${defaultTargetPlatform.name}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        // Lifts clear of the keyboard, which otherwise covers the field this
        // sheet exists for.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: Responsive.pagePadding(context),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Report a problem',
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
                  const SizedBox(height: AppDimens.space12),
                  Text(
                    'What kind of problem?',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: AppDimens.space8),
                  Wrap(
                    spacing: AppDimens.space8,
                    runSpacing: AppDimens.space8,
                    children: [
                      for (final kind in FeedbackKind.values)
                        ChoiceChip(
                          label: Text(kind.label),
                          selected: _kind == kind,
                          onSelected: (_) => setState(() => _kind = kind),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.space16),
                  TextFormField(
                    controller: _controller,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'What happened?',
                      hintText: switch (_kind) {
                        FeedbackKind.mapError =>
                          'Which building and floor, and what was wrong?',
                        FeedbackKind.idea => 'What would you like it to do?',
                        FeedbackKind.problem =>
                          'What were you doing when it went wrong?',
                      },
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Please say what went wrong.'
                        : null,
                  ),
                  const SizedBox(height: AppDimens.space8),
                  Text(
                    // No surprises about what is attached. An accessibility
                    // app asking for a bug report should not quietly collect
                    // anything the user has not been told about.
                    'Sent with your account and the app version. Nothing else.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppDimens.space16),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(
                      PhosphorIconsFill.paperPlaneTilt,
                      size: 18,
                    ),
                    label: const Text('Send report'),
                  ),
                  const SizedBox(height: AppDimens.space8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
