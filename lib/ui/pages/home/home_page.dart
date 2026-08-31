import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/home/bloc/home_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/building_glyph.dart';
import '../../widgets/percent_badge.dart';
import '../../widgets/section_label.dart';
import '../camera_flow.dart';

/// Home tab (Figma 7:488, assist-first): greeting, search, assistance
/// banner, trace card, recently mapped.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HomeBloc>()..add(const HomeStarted()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.watch<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.pageGutter),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('KNUST, Kumasi', style: theme.textTheme.bodyMedium),
                      Text('Where to?', style: theme.textTheme.displaySmall),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.coralSoft,
                  child: Text(
                    user?.initial ?? '?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.coral,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space20),
            AppSearchField(
              hint: 'Search a building or room',
              readOnly: true,
              onTap: () => context.goNamed(RouteNames.explore),
            ),
            const SizedBox(height: AppDimens.space20),
            const _AssistBanner(),
            const SizedBox(height: AppDimens.space12),
            const _TraceCard(),
            const SizedBox(height: AppDimens.space24),
            SectionLabel(
              'Recently mapped',
              trailing: GestureDetector(
                onTap: () => context.goNamed(RouteNames.explore),
                child: Text(
                  'See all',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.coral,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimens.space12),
            BlocBuilder<HomeBloc, HomeState>(
              builder: (context, state) => switch (state.status) {
                HomeStatus.initial || HomeStatus.loading => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppDimens.space48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                HomeStatus.failure => _LoadError(
                  message: state.error ?? 'Could not load buildings',
                  onRetry: () =>
                      context.read<HomeBloc>().add(const HomeStarted()),
                ),
                HomeStatus.success => GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppDimens.space16,
                  crossAxisSpacing: AppDimens.space16,
                  childAspectRatio: 0.82,
                  children: [
                    for (final building in state.recent)
                      _BuildingCard(building: building),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Dark "Start assistance" banner — the headline action.
class _AssistBanner extends StatelessWidget {
  const _AssistBanner();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.darkElevated : AppColors.ink;

    return Semantics(
      button: true,
      label:
          'Start assistance. Obstacle alerts and voice guidance as you walk.',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: InkWell(
          onTap: () => openAssistFlow(context),
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.space16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.coral,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsFill.eye,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start assistance',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                      Text(
                        'Obstacle alerts and voice guidance as you walk',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  PhosphorIconsRegular.caretRight,
                  color: Colors.white70,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The contributor action that maps a building: trace the floor plan posted on
/// its wall.
///
/// The only authoring path, and deliberately so. Traced coordinates are
/// absolute, it needs neither ARCore nor a working pedometer, and it therefore
/// works identically on every phone — which is what keeps contributing open to
/// the handsets most contributors actually own.
///
/// Goes to the "what are you mapping" chooser rather than Explore: Explore
/// only lists buildings somebody has already added, which strands the
/// contributor standing in one nobody has — the case mapping exists for.
class _TraceCard extends StatelessWidget {
  const _TraceCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: 'Map a building. Trace its rooms off the plan posted on its wall.',
      child: Material(
        color: AppColors.coralSoft,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: InkWell(
          // No `extra`: this card means tracing, so the picker keeps its
          // default destination. Only the scan card asks for the hub.
          onTap: () => context.pushNamed(RouteNames.mapBuilding),
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.space16),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsFill.mapTrifold,
                  size: 22,
                  color: AppColors.coral,
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Map a building',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        'Trace its rooms off the plan posted on its wall',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 20,
                  color: AppColors.coral,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The AR half of contributing: walk the rooms and tap their corners.
///
/// Goes through the same building picker as [_TraceCard] — the two differ in
/// the method they set an expectation of, not the destination, and the mapping
/// hub past the picker offers whichever the device can do.
///
/// It used to open the mock scan screen, which is now
/// removed, so this is now the only thing "scan" means. Gated on ARCore
/// because *this* card promises AR; the trace card beside it is deliberately
/// ungated, so a phone that cannot scan still has a way to contribute.
class _BuildingCard extends StatelessWidget {
  const _BuildingCard({required this.building});

  final Building building;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      child: InkWell(
        onTap: () => context.pushNamed(
          RouteNames.buildingDetail,
          pathParameters: {'id': building.id},
          extra: building,
        ),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(AppDimens.space8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(
                          BuildingGlyph.iconFor(building.glyph),
                          size: 40,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      Positioned(
                        top: AppDimens.space8,
                        right: AppDimens.space8,
                        child: PercentBadge(building.mappedPercent),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.space12,
                  AppDimens.space4,
                  AppDimens.space12,
                  AppDimens.space12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(building.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppDimens.space2),
                    Text(
                      '${building.floorsCount} floors · ${building.mappers} mappers',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space24),
      child: Column(
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppDimens.space12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
