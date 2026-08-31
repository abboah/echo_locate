import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/explore/bloc/explore_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/building_list_tile.dart';
import '../../widgets/responsive.dart';

/// Explore tab (Figma 7:372): search, category chips, nearby buildings,
/// pinned "Map a new building" CTA.
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
          padding: Responsive.horizontalPadding(context),
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
                          onTap: () => context.read<ExploreBloc>().add(
                            ExploreCategoryChanged(id),
                          ),
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
                    ExploreStatus.initial || ExploreStatus.loading =>
                      const Center(child: CircularProgressIndicator()),
                    ExploreStatus.failure => Center(
                      child: Text(
                        state.error ?? 'Could not load buildings',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    ExploreStatus.success when state.buildings.isEmpty =>
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppDimens.space24),
                          child: Text(
                            // "Nothing here" and "you have saved nothing" are
                            // different facts, and only one of them tells the
                            // user what to do about it.
                            state.category == savedCategory
                                ? 'Nothing saved yet. Open a building and tap '
                                      'the bookmark to keep it here.'
                                : 'No buildings found. Try another search, or '
                                      'add the one you are standing in.',
                            style: theme.textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    // Pull to refresh. The index is crowdsourced, so what is
                    // on it changes while somebody is looking at it — and the
                    // distances re-sort as they walk. Waiting for a tab switch
                    // to see either is not a refresh anybody would guess at.
                    ExploreStatus.success => RefreshIndicator(
                      onRefresh: () async => context.read<ExploreBloc>().add(
                        const ExploreStarted(),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(
                          top: AppDimens.space8,
                          bottom: AppDimens.space24,
                        ),
                        itemCount: state.buildings.length,
                        separatorBuilder: (_, _) => Divider(
                          height: AppDimens.space24,
                          color: theme.dividerColor,
                        ),
                        itemBuilder: (context, index) {
                          final building = state.buildings[index];
                          return BuildingListTile(
                            building: building,
                            onChanged: (_) => context.read<ExploreBloc>().add(
                              const ExploreStarted(),
                            ),
                            // Only shown once there is a real position. Without
                            // one every row is measured from the server's
                            // default origin, and a confident "0.4 km" that is
                            // not relative to the reader is worse than silence.
                            metaSuffix: state.located
                                ? ' · '
                                      '${building.distanceKm.toStringAsFixed(1)}'
                                      ' km'
                                : '',
                          );
                        },
                      ),
                    ),
                  },
                ),
              ),
              // Shown on every phone. Tracing needs no ARCore, so gating this
              // on AR capability hid the contributor entry point from exactly
              // the handsets most contributors own.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.space12),
                  // The building picker. A contributor standing in a building
                  // nobody has listed has to be able to add it, which is
                  // exactly what the picker is for.
                  //
                  // No `extra`. This used to send the picker to the per-floor
                  // hub, which made it describe an AR scan — a capture path
                  // that no longer exists. Same words as Home's card, so now
                  // the same thing happens.
                  child: ElevatedButton.icon(
                    onPressed: () => context.pushNamed(RouteNames.mapBuilding),
                    icon: const Icon(PhosphorIconsBold.plus, size: 18),
                    label: const Text('Map a new building'),
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

    // Without this a screen reader met a filter row as five bare words with
    // no way to tell which one was on — the state is carried only by a fill
    // colour, which is exactly the information sight-free use loses.
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '$label filter',
      child: ExcludeSemantics(
        child: Material(
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
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
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
        ),
      ),
    );
  }
}
