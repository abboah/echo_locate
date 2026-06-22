import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/theme_cubit.dart';

/// Temporary foundation/smoke screen.
///
/// Exists only to prove the design system + theming + dark-mode toggle work
/// end-to-end (a Phase 1 acceptance check). Replaced by the real Home screen
/// (Figma 7-488) when feature work starts.
class FoundationHomePage extends StatelessWidget {
  const FoundationHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = context.watch<ThemeCubit>().state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EchoLocate'),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            icon: Icon(
              theme.brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: () => context.read<ThemeCubit>().toggle(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.pageGutter),
        children: [
          Text('Foundation ready', style: theme.textTheme.displaySmall),
          const SizedBox(height: AppDimens.space8),
          Text(
            'Bloc + Achieve repos + GetIt + go_router + Hive-persisted theme. '
            'Current mode: ${mode.name}.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppDimens.space24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.space20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tokens', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppDimens.space16),
                  const Wrap(
                    spacing: AppDimens.space12,
                    runSpacing: AppDimens.space12,
                    children: [
                      _Swatch('Coral', AppColors.coral),
                      _Swatch('Ink', AppColors.ink),
                      _Swatch('Surface', AppColors.surface),
                      _Swatch('White', AppColors.white),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space24),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Primary action'),
          ),
          const SizedBox(height: AppDimens.space12),
          OutlinedButton(
            onPressed: () {},
            child: const Text('Secondary action'),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
        ),
        const SizedBox(height: AppDimens.space4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
