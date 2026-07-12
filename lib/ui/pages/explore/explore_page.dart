import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/explore/bloc/explore_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/building_list_tile.dart';
import '../scan/scan_flow.dart';

/// Explore tab (Figma 7:372): search, category chips, nearby buildings,
/// pinned "Scan a new building" CTA.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  @override
  void initState() {
    super.initState();
    // One-time location primer before the first nearby browse.
    final settings = getIt<SettingsRepository>();
    if (!settings.locationPrimerSeen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pushNamed(RouteNames.locationPrimer);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ExploreBloc>()..add(const ExploreStarted()),
      child: const _ExploreView(),
    );
  }
}

class _ExploreView extends StatelessWidget {
  const _ExploreView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.pageGutter,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppDimens.space16),
              Text('Explore', style: theme.textTheme.displaySmall),
              const SizedBox(height: AppDimens.space16),
              AppSearchField(
                hint: 'Search buildings near you',
                onChanged: (q) =>
                    context.read<ExploreBloc>().add(ExploreQueryChanged(q)),
              ),
              const SizedBox(height: AppDimens.space12),
              BlocBuilder<ExploreBloc, ExploreState>(
                buildWhen: (a, b) => a.category != b.category,
                builder: (context, state) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (id, label) in exploreCategories) ...[
                        _FilterChip(
                          label: label,
                          selected: state.category == id,
                          onTap: () => context
                              .read<ExploreBloc>()
                              .add(ExploreCategoryChanged(id)),
                        ),
                        const SizedBox(width: AppDimens.space8),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.space8),
              Expanded(
                child: BlocBuilder<ExploreBloc, ExploreState>(
                  builder: (context, state) => switch (state.status) {
                    ExploreStatus.initial ||
                    ExploreStatus.loading =>
                      const Center(child: CircularProgressIndicator()),
                    ExploreStatus.failure => Center(
                        child: Text(
                          state.error ?? 'Could not load buildings',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ExploreStatus.success when state.buildings.isEmpty =>
                      Center(
                        child: Text(
                          'No buildings found',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ExploreStatus.success => ListView.separated(
                        padding: const EdgeInsets.only(
                          top: AppDimens.space8,
                          bottom: AppDimens.space24,
                        ),
                        itemCount: state.buildings.length,
                        separatorBuilder: (_, __) => Divider(
                          height: AppDimens.space24,
                          color: theme.dividerColor,
                        ),
                        itemBuilder: (context, index) {
                          final building = state.buildings[index];
                          return BuildingListTile(
                            building: building,
                            metaSuffix:
                                ' · ${building.distanceKm.toStringAsFixed(1)} km',
                          );
                        },
                      ),
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.only(bottom: AppDimens.space12),
                  child: ElevatedButton.icon(
                    onPressed: () => openScanFlow(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Scan a new building'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = isDark ? AppColors.darkElevated : AppColors.ink;
    const selectedFg = Colors.white;

    return Material(
      color: selected
          ? selectedBg
          : (isDark ? AppColors.darkSurface : AppColors.white),
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space8,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.transparent : theme.dividerColor,
            ),
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? selectedFg : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
