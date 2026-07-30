import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/profile/bloc/profile_bloc.dart';
import '../../../services/injection_container.dart';
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

            return ListView(
              padding: const EdgeInsets.all(AppDimens.pageGutter),
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
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(color: AppColors.coral),
                        ),
                      ),
                      const SizedBox(height: AppDimens.space12),
                      Text(profile.fullName,
                          style: theme.textTheme.titleLarge),
                      Text(profile.email, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: AppDimens.space8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space12,
                          vertical: AppDimens.space4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.coralSoft,
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusPill),
                        ),
                        child: Text(
                          profile.rankLabel,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: AppColors.coral),
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
                        label: 'Buildings'),
                    const SizedBox(width: AppDimens.space12),
                    _StatCard(
                        value: '${profile.floorsMapped}', label: 'Floors'),
                    const SizedBox(width: AppDimens.space12),
                    _StatCard(
                        value: '${profile.roomsMapped}', label: 'Rooms'),
                  ],
                ),
                const SizedBox(height: AppDimens.space32),
                const SectionLabel('Preferences'),
                const SizedBox(height: AppDimens.space8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text('Dark mode',
                            style: theme.textTheme.titleMedium),
                        subtitle: Text('Easier on the eyes at night',
                            style: theme.textTheme.bodyMedium),
                        activeThumbColor: AppColors.coral,
                        value: theme.brightness == Brightness.dark,
                        onChanged: (dark) => context
                            .read<ThemeCubit>()
                            .setMode(
                                dark ? ThemeMode.dark : ThemeMode.light),
                      ),
                      Divider(height: 1, color: theme.dividerColor),
                      ListTile(
                        title: Text('View the intro again',
                            style: theme.textTheme.titleMedium),
                        subtitle: Text('Replay the 3-step welcome tour',
                            style: theme.textTheme.bodyMedium),
                        trailing: Icon(
                          PhosphorIconsRegular.caretRight,
                          size: 18,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                        onTap: () async {
                          await getIt<SettingsRepository>()
                              .resetOnboarding();
                          if (context.mounted) {
                            context.goNamed(RouteNames.onboarding);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimens.space24),
                OutlinedButton.icon(
                  onPressed: () => context
                      .read<AuthBloc>()
                      .add(const AuthSignOutRequested()),
                  icon: const Icon(PhosphorIconsRegular.signOut,
                      color: AppColors.error, size: 20),
                  label: const Text(
                    'Sign out',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            );
          },
        ),
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
