import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../services/injection_container.dart';

/// Camera permission primer (Figma 7:939), shown once before the first scan.
/// The real runtime permission request happens when the camera feed lands
/// in Phase 2 sensing; this pre-prompt sets expectations first.
class CameraPrimerPage extends StatelessWidget {
  const CameraPrimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.pageGutter),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? AppColors.coral.withValues(alpha: 0.16)
                      : AppColors.coralSoft,
                  borderRadius: BorderRadius.circular(AppDimens.radiusXl),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  color: AppColors.coral,
                  size: 40,
                ),
              ),
              const SizedBox(height: AppDimens.space24),
              Text('Allow camera access',
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: AppDimens.space12),
              Text(
                'EchoLocate uses your camera to map spaces and detect '
                'obstacles. Frames are processed on-device and never stored.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              ElevatedButton(
                onPressed: () async {
                  await getIt<SettingsRepository>().setCameraPrimerSeen();
                  if (context.mounted) {
                    context.pushReplacementNamed(RouteNames.scan);
                  }
                },
                child: const Text('Allow camera'),
              ),
              TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'Not now',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
