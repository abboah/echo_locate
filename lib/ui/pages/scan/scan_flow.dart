import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../services/injection_container.dart';

/// Entry point for every "scan" affordance (shell FAB, Home banner, Explore
/// button). Shows the camera permission primer once, then goes straight to
/// the scanner.
void openScanFlow(BuildContext context) {
  final settings = getIt<SettingsRepository>();
  if (settings.cameraPrimerSeen) {
    context.pushNamed(RouteNames.scan);
  } else {
    context.pushNamed(RouteNames.cameraPrimer);
  }
}
