import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../data/repository_mixin.dart';
import '../../../features/feedback/feedback_repository.dart';
import '../../../features/profile/bloc/profile_bloc.dart';
import '../../../features/profile/profile_repository.dart';
import '../../../services/injection_container.dart';
import '../../widgets/report_problem_sheet.dart';
import '../../widgets/responsive.dart';
import '../../widgets/section_label.dart';

/// Profile tab: contributor identity + stats, preferences (dark mode),
/// sign out.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ProfileBloc>()..add(const ProfileStarted()),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state.status == ProfileStatus.loading ||
                state.status == ProfileStatus.initial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == ProfileStatus.failure ||
                state.profile == null) {
              return Center(
                child: Text(
                  state.error ?? 'Could not load profile',
                  style: theme.textTheme.bodyMedium,
                ),
              );
            }
            final profile = state.profile!;

            return RefreshIndicator(
              onRefresh: () async {
                final bloc = context.read<ProfileBloc>()
                  ..add(const ProfileStarted());
                await bloc.stream.firstWhere(
                  (state) => state.status != ProfileStatus.loading,
                );
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: Responsive.pagePadding(context),
                children: [
                  Text('Profile', style: theme.textTheme.displaySmall),
                  const SizedBox(height: AppDimens.space24),
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: AppColors.coralSoft,
                          child: Text(
                            profile.fullName.isEmpty
                                ? '?'
                                : profile.fullName[0].toUpperCase(),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: AppColors.coral,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppDimens.space12),
                        Text(
                          profile.fullName,
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(profile.email, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: AppDimens.space8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.space12,
                            vertical: AppDimens.space4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.coralSoft,
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusPill,
                            ),
                          ),
                          child: Text(
                            profile.rankLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.coral,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimens.space24),
                  Row(
                    children: [
                      _StatCard(
                        value: '${profile.buildingsMapped}',
                        label: 'Buildings',
                      ),
                      const SizedBox(width: AppDimens.space12),
                      _StatCard(
                        value: '${profile.floorsMapped}',
                        label: 'Floors',
                      ),
                      const SizedBox(width: AppDimens.space12),
                      _StatCard(
                        value: '${profile.roomsMapped}',
                        label: 'Rooms',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.space32),
                  const SectionLabel('Preferences'),
                  const SizedBox(height: AppDimens.space8),
                  // "Measure your step" and "View the intro again" used to sit
                  // here. The intro replay is a one-off nobody returns for.
                  //
                  // Step measurement is not gone — it moved to the walk screen,
                  // where it is the difference between a spoken distance that is
                  // yours and one that is a generic adult's. Asking for it in
                  // Settings, before somebody has walked anywhere, is asking a
                  // question they have no reason to care about yet.
                  Card(
                    child: SwitchListTile(
                      title: Text(
                        'Dark mode',
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        'Easier on the eyes at night',
                        style: theme.textTheme.bodyMedium,
                      ),
                      activeThumbColor: AppColors.coral,
                      value: theme.brightness == Brightness.dark,
                      onChanged: (dark) => context.read<ThemeCubit>().setMode(
                        dark ? ThemeMode.dark : ThemeMode.light,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.space24),
                  const SectionLabel('Account'),
                  const SizedBox(height: AppDimens.space8),
                  Card(
                    child: Column(
                      children: [
                        _ActionRow(
                          icon: PhosphorIconsRegular.userCircle,
                          title: 'Edit your name',
                          subtitle: profile.fullName.isEmpty
                              ? 'Not set'
                              : profile.fullName,
                          onTap: () => _editName(context, profile.fullName),
                        ),
                        const _RowDivider(),
                        _ActionRow(
                          icon: PhosphorIconsRegular.bug,
                          title: 'Report a problem',
                          subtitle:
                              'A wrong map, or something not working as it '
                              'should',
                          onTap: () => _report(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimens.space24),
                  const SectionLabel('About'),
                  const SizedBox(height: AppDimens.space8),
                  Card(
                    child: Column(
                      children: [
                        _ActionRow(
                          icon: PhosphorIconsRegular.info,
                          title: 'About EchoLocate',
                          subtitle: 'What the app does, and what it cannot do',
                          onTap: () => _about(context),
                        ),
                        // The probes, in debug builds only.
                        //
                        // Six of these used to ship in the release Profile, each
                        // labelled "(dev)". One was not a probe at all — acoustic
                        // room classification is a headline capability, and being
                        // filed beside an ARCore depth readout was the only
                        // reason it had no way in. It is on Home now. What is
                        // left is instrumentation: it exists to be pointed at
                        // hardware and read, and a user has no use for any of it.
                        if (kDebugMode) ...[
                          const _RowDivider(),
                          _ActionRow(
                            icon: PhosphorIconsRegular.wrench,
                            title: 'Developer tools',
                            subtitle: 'Probes and hand-built fixtures',
                            onTap: () => _devTools(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimens.space24),
                  OutlinedButton.icon(
                    onPressed: () => context.read<AuthBloc>().add(
                      const AuthSignOutRequested(),
                    ),
                    icon: const Icon(PhosphorIconsRegular.signOut, size: 20),
                    label: const Text('Sign out'),
                  ),
                  const SizedBox(height: AppDimens.space8),
                  // Below the fold and in the destructive colour, because it is
                  // the one action on this screen that cannot be undone.
                  TextButton.icon(
                    onPressed: () => _deleteAccount(context),
                    icon: const Icon(
                      PhosphorIconsRegular.trash,
                      color: AppColors.error,
                      size: 18,
                    ),
                    label: const Text(
                      'Delete my account',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Renaming yourself.
  ///
  /// The name comes from whatever was typed at sign-up, or from a Google
  /// account — often a legal name somebody would rather not have attached to
  /// every building they map.
  Future<void> _editName(BuildContext context, String current) async {
    final bloc = context.read<ProfileBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _EditNameDialog(current: current),
    );
    if (name == null) return;

    bloc.add(ProfileNameChanged(name));
    // Waits for the write rather than assuming it: telling somebody their name
    // is saved when it is not is the failure this screen can least afford.
    final state = await bloc.stream.firstWhere(
      (state) => state.status != ProfileStatus.saving,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            state.error ?? 'Your name is now ${state.profile?.fullName}.',
          ),
        ),
      );
  }

  /// Telling somebody something is wrong.
  Future<void> _report(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final report = await showModalBottomSheet<FeedbackReport>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ReportProblemSheet(),
    );
    if (report == null) return;

    final sent = await getIt<FeedbackRepository>().submit(report);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            // Says which actually happened. "Thanks for your report" over a
            // failed request is the kind of lie that makes somebody stop
            // reporting things.
            sent
                ? 'Thank you — your report was sent.'
                : 'Saved on your phone. It will send when you are back '
                      'online.',
          ),
        ),
      );
  }

  /// Leaving.
  ///
  /// Two steps on purpose. The first says what actually happens — including
  /// the part people do not expect, that the floors they traced stay on the
  /// map — and the second asks them to type the word, because a single
  /// mis-tap should not end an account.
  Future<void> _deleteAccount(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true) return;

    try {
      await getIt<ProfileRepository>().deleteAccount();
      if (!context.mounted) return;
      // The router's redirect sends the guest tree in as soon as auth clears.
      context.read<AuthBloc>().add(const AuthSignOutRequested());
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(OperationFailure.from(error).message)),
        );
    }
  }

  Future<void> _about(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const _AboutDialog());

  Future<void> _devTools(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _DevToolsSheet(),
  );
}

/// A row in one of the Profile cards.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        PhosphorIconsRegular.caretRight,
        size: 18,
        color: theme.textTheme.bodyMedium?.color,
      ),
      onTap: onTap,
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).dividerColor);
}

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.current});

  final String current;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final _controller = TextEditingController(text: widget.current);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your name'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Full name'),
        validator: (value) =>
            (value ?? '').trim().isEmpty ? 'Your name cannot be empty.' : null,
        onFieldSubmitted: (_) => _submit(),
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

/// Deleting an account, with the consequences stated first.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  static const _word = 'DELETE';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _ready => _controller.text.trim().toUpperCase() == _word;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your account and your name are deleted and cannot be restored.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppDimens.space12),
          Text(
            // The part nobody expects, said before they decide rather than
            // after. Somebody who wants their traced floors removed too needs
            // to know that this is not what does it.
            'The floors you traced stay on the map — other people are using '
            'them — but they will no longer be credited to you.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppDimens.space16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Type DELETE to confirm',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep my account'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: _ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// What the app does, and — as importantly — what it does not.
class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('About EchoLocate'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Crowdsourced indoor mapping and navigation, built as an '
              'accessibility aid. GPS stops at the front door; this is a map '
              'of the spaces it cannot reach.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppDimens.space12),
            Text('What it cannot do', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppDimens.space4),
            Text(
              // Stated plainly, in the app, rather than only in a report
              // nobody using it will read. A user who knows the limits can
              // work around them; one who does not will trust a wrong answer.
              'A floor traced without a scale routes correctly but cannot '
              'speak distances. The AR arrow needs an ARCore-certified phone. '
              'Directions are only as good as the plan somebody traced — if '
              'one is wrong, please report it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppDimens.space12),
            Text(
              'Final-year project, Department of Computer Science, KNUST.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// The debug-only probes, behind one row rather than five.
class _DevToolsSheet extends StatelessWidget {
  const _DevToolsSheet();

  static const String _demoBuildingId = 'knust-library';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: Responsive.pagePadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Developer tools', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppDimens.space12),
            const _DevTile(
              title: 'Landmark map + routing',
              subtitle:
                  'The schematic recovered from recorded walks, and A* '
                  'between any two landmarks on it',
              route: RouteNames.navigate,
              buildingId: _demoBuildingId,
            ),
            const SizedBox(height: AppDimens.space8),
            const _DevTile(
              title: 'Trace landmarks onto a plan',
              subtitle: 'The landmark tracer, as distinct from tracing rooms',
              route: RouteNames.planTrace,
              buildingId: _demoBuildingId,
            ),
            const SizedBox(height: AppDimens.space8),
            const _DevTile(
              title: 'Room plan probe',
              subtitle:
                  'A hand-built floor: pick two rooms, read the route and '
                  'the directions it generates',
              route: RouteNames.roomPlanProbe,
            ),
            const SizedBox(height: AppDimens.space8),
            const _DevTile(
              title: 'Sonar',
              subtitle: 'Acoustic distance ping and radar',
              route: RouteNames.sonar,
            ),
            const SizedBox(height: AppDimens.space8),
            const _DevTile(
              title: 'Depth probe',
              subtitle: 'ARCore availability and a live depth readout',
              route: RouteNames.depthProbe,
            ),
          ],
        ),
      ),
    );
  }
}

/// One debug-build shortcut to a probe screen.
///
/// Shared rather than repeated, because these were six near-identical
/// `Card(child: ListTile(...))` blocks — about ninety lines of copy in the
/// middle of the user's Profile.
class _DevTile extends StatelessWidget {
  const _DevTile({
    required this.title,
    required this.subtitle,
    required this.route,
    this.buildingId,
  });

  final String title;
  final String subtitle;
  final String route;

  /// Set for the probes that need somewhere to point at.
  final String? buildingId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle, style: theme.textTheme.bodyMedium),
        trailing: Icon(
          PhosphorIconsRegular.caretRight,
          size: 18,
          color: theme.textTheme.bodyMedium?.color,
        ),
        onTap: () {
          // Close the sheet first: pushing from inside it leaves the probe
          // screen underneath a modal barrier.
          Navigator.of(context).pop();
          context.pushNamed(
            route,
            pathParameters: buildingId == null ? const {} : {'id': buildingId!},
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.space16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppDimens.space2),
            Text(label, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
