import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../services/injection_container.dart';
import '../../../services/location/location_service.dart';
import '../../widgets/responsive.dart';

/// Location permission primer (Figma 7:895), shown once before first Explore.
///
/// **It now actually asks.** Both buttons used to run identical code — set the
/// "primer seen" flag and pop — so the screen explained why location was
/// useful, offered "Allow while using app", and then never put the question to
/// Android. The permission was never granted however many times somebody
/// allowed it, which is why every distance in the app was measured from the
/// server's default origin.
class LocationPrimerPage extends StatelessWidget {
  const LocationPrimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: Responsive.pagePadding(context, top: AppDimens.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const _Benefit(
                icon: PhosphorIconsRegular.mapPin,
                title: 'Find nearby buildings',
                body: 'See maps for the buildings around you',
              ),
              const SizedBox(height: AppDimens.space16),
              const _Benefit(
                icon: PhosphorIconsRegular.navigationArrow,
                title: 'Tag your scans',
                body: 'Place new maps in the right location',
              ),
              const SizedBox(height: AppDimens.space16),
              const _Benefit(
                icon: PhosphorIconsRegular.shieldCheck,
                title: 'Private by default',
                body: 'Location is only used while you map',
              ),
              const Spacer(),
              Text('Use your location?', style: theme.textTheme.headlineMedium),
              const SizedBox(height: AppDimens.space8),
              Text(
                'We use it to surface nearby maps and position your scans.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppDimens.space24),
              ElevatedButton(
                onPressed: () => _finish(context, ask: true),
                child: const Text('Allow while using app'),
              ),
              TextButton(
                // Declining is a real answer and costs nothing: nearby
                // ordering falls back to a fixed origin and the header simply
                // says less. Nothing about walking a building needs this.
                onPressed: () => _finish(context, ask: false),
                child: Text("Don't allow", style: theme.textTheme.labelLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finish(BuildContext context, {required bool ask}) async {
    // The flag is set either way: it records that the explanation has been
    // shown, not that permission was granted. Android owns the second answer
    // and will not ask twice.
    await getIt<SettingsRepository>().setLocationPrimerSeen();
    if (ask) await getIt<LocationService>().request();
    if (context.mounted) context.pop();
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          ),
          child: Icon(icon, size: 20, color: theme.textTheme.bodyMedium?.color),
        ),
        const SizedBox(width: AppDimens.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
