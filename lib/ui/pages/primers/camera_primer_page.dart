import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../services/injection_container.dart';

/// Camera permission primer (Figma 7:939), shown once before the first
/// camera experience (Assist Mode or Scan — [destinationName] decides).
/// The real runtime permission request happens when the camera feed lands
/// in the Phase 1 sensing step; this pre-prompt sets expectations first.
class CameraPrimerPage extends StatelessWidget {
  const CameraPrimerPage({super.key, required this.destinationName});

  final String destinationName;

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
                  PhosphorIconsRegular.camera,
                  color: AppColors.coral,
                  size: 40,
                ),
              ),
              const SizedBox(height: AppDimens.space24),
              Text(
                'Allow camera access',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppDimens.space12),
              Text(
                'EchoLocate uses your camera to detect obstacles and read '
                'signs aloud as you move. It can also map spaces. Frames are '
                'processed on-device and never stored.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              ElevatedButton(
                onPressed: () async {
                  await getIt<SettingsRepository>().setCameraPrimerSeen();
                  // Real system prompt; if denied, Assist falls back to
                  // demo mode rather than blocking.
                  await Permission.camera.request();
                  if (context.mounted) {
                    context.pushReplacementNamed(destinationName);
                  }
                },
                child: const Text('Allow camera'),
              ),
              TextButton(
                onPressed: () => context.pop(),
                child: Text('Not now', style: theme.textTheme.labelLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
