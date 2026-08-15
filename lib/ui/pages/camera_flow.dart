import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes/app_routes.dart';
import '../../core/settings/settings_repository.dart';
import '../../services/injection_container.dart';

/// Entry point for Assist Mode — the app's one camera experience.
///
/// Shows the camera permission primer once, then continues to the destination.
///
/// Mapping does **not** come through here. "Scan a space" and "Scan a new
/// building" go to the building picker, which is not a camera screen itself;
/// the tools past it ask for the camera when they actually need it.
void openAssistFlow(BuildContext context) =>
    _viaPrimer(context, RouteNames.assist);

void _viaPrimer(BuildContext context, String destinationName) {
  final settings = getIt<SettingsRepository>();
  if (settings.cameraPrimerSeen) {
    context.pushNamed(destinationName);
  } else {
    context.pushNamed(RouteNames.cameraPrimer, extra: destinationName);
  }
}
