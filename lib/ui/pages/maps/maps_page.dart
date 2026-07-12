import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/maps/bloc/maps_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/building_list_tile.dart';
import '../../widgets/section_label.dart';

/// Maps tab: floor plans saved for offline use (cached community maps).
class MapsPage extends StatelessWidget {
  const MapsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<MapsBloc>()..add(const MapsStarted()),
      child: const _MapsView(),
    );
  }
}

class _MapsView extends StatelessWidget {
  const _MapsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppDimens.pageGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppDimens.space16),
              Text('Maps', style: theme.textTheme.displaySmall),
              const SizedBox(height: AppDimens.space4),
              Text(
                'Floor plans available offline on this phone.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppDimens.space24),
              const SectionLabel('Saved maps'),
              const SizedBox(height: AppDimens.space8),
              Expanded(
                child: BlocBuilder<MapsBloc, MapsState>(
                  builder: (context, state) => switch (state.status) {
                    MapsStatus.initial ||
                    MapsStatus.loading =>
                      const Center(child: CircularProgressIndicator()),
                    MapsStatus.failure => Center(
                        child: Text(
                          state.error ?? 'Could not load saved maps',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    MapsStatus.success when state.saved.isEmpty =>
                      const _EmptyMaps(),
                    MapsStatus.success => ListView.separated(
                        padding: const EdgeInsets.only(
                          top: AppDimens.space8,
                          bottom: AppDimens.space24,
                        ),
                        itemCount: state.saved.length,
                        separatorBuilder: (_, __) => Divider(
                          height: AppDimens.space24,
                          color: theme.dividerColor,
                        ),
                        itemBuilder: (context, index) => BuildingListTile(
                          building: state.saved[index],
                          trailing: const Icon(
                            Icons.download_done,
                            color: AppColors.coral,
                            size: 20,
                          ),
                        ),
                      ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMaps extends StatelessWidget {
  const _EmptyMaps();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.map_outlined,
            size: 48,
            color: theme.textTheme.bodyMedium?.color,
          ),
          const SizedBox(height: AppDimens.space12),
          Text('No saved maps yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.space4),
          Text(
            'Maps you save appear here and work offline.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimens.space16),
          OutlinedButton(
            onPressed: () => context.goNamed(RouteNames.explore),
            child: const Text('Explore buildings'),
          ),
        ],
      ),
    );
  }
}
