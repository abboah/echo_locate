import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
import '../scan/scan_flow.dart';

/// Home tab (Figma 7:488): greeting, search, scan banner, recently mapped.
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
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppColors.coral),
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
            const _ScanBanner(),
            const SizedBox(height: AppDimens.space24),
            SectionLabel(
              'Recently mapped',
              trailing: GestureDetector(
                onTap: () => context.goNamed(RouteNames.explore),
                child: Text(
                  'See all',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.coral),
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

/// Dark "Scan a space" banner card.
class _ScanBanner extends StatelessWidget {
  const _ScanBanner();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.darkElevated : AppColors.ink;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      child: InkWell(
        onTap: () => openScanFlow(context),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.space16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
                child: const Icon(
                  Icons.filter_center_focus,
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
                      'Scan a space',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    Text(
                      'Map a building in minutes',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

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
