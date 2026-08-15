import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../services/injection_container.dart';

/// Entry points for the two camera experiences. Both show the camera
/// permission primer once, then continue to their destination.
///
/// - Assist Mode (shell FAB, Home banner) — the headline experience:
///   obstacle alerts + voice guidance while moving.
/// - Scan (Home card, Explore CTA) — the contributor flow that maps spaces.
void openAssistFlow(BuildContext context) =>
    _viaPrimer(context, RouteNames.assist);

void openScanFlow(BuildContext context) => _viaPrimer(context, RouteNames.scan);

void _viaPrimer(BuildContext context, String destinationName) {
  final settings = getIt<SettingsRepository>();
  if (settings.cameraPrimerSeen) {
    context.pushNamed(destinationName);
  } else {
    context.pushNamed(RouteNames.cameraPrimer, extra: destinationName);
  }
}
