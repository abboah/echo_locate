import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';

/// Vibration, as a service so Blocs can be tested without a plugin.
///
/// Guidance speaks over a phone held at chest height in a corridor that may be
/// noisy, and its user may be wearing headphones or hard of hearing as well as
/// blind. Every announcement that matters is therefore also felt: a short pulse
/// on arriving at a landmark, a hard double pulse for something in the way.
class HapticService {
  const HapticService();

  /// Something is in the user's path. Deliberately the heaviest pattern the
  /// platform offers — this one has to cut through a pocket.
  Future<void> alert() async {
    try {
      await HapticFeedback.heavyImpact();
      await HapticFeedback.heavyImpact();
    } catch (e) {
      AppLogger.debug('Haptics unavailable: $e');
    }
  }

  /// A landmark was confirmed, or a leg completed. Light: it is good news.
  Future<void> confirm() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (e) {
      AppLogger.debug('Haptics unavailable: $e');
    }
  }
}
