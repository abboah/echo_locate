import 'package:bloc/bloc.dart';

import '../../../core/utils/logger.dart';
import '../../../services/vision/arcore_depth_service.dart';
import '../../../services/vision/depth_frame.dart';

/// Whether this device can contribute scans.
///
/// Scanning is the one feature with a hard hardware floor: it needs ARCore,
/// which Google certifies per device. Everything else in the app — Assist
/// Mode (plain camera + ML Kit), sonar, browsing, navigation — runs anywhere.
enum ScanCapability {
  /// Still asking ARCore. Entry points stay hidden until this resolves, so
  /// they never appear and then vanish under the user's finger.
  checking,

  /// Scanning can run, or could after the user installs/updates ARCore. The
  /// scan flow itself handles prompting in the latter case.
  available,

  /// Google has not certified this device. No user action changes this, so
  /// the entry points are hidden rather than shown-and-disabled: offering a
  /// control that can never work is worse than not offering it, and a
  /// disabled control still occupies the screen-reader focus order for a
  /// user who can do nothing about it.
  unavailable;

  /// The gating decision, kept pure so it can be tested without a device or a
  /// platform channel.
  ///
  /// Fails CLOSED: only a positive answer from ARCore — it works, or it would
  /// after an install the user can perform — shows the entry point.
  ///
  /// This started out failing open, on the reasoning that a transient error
  /// shouldn't strip scanning from capable hardware. On-device that proved
  /// backwards. An uncertified Infinix X657C does not report
  /// `UNSUPPORTED_DEVICE_NOT_CAPABLE`; ARCore's install service fails to
  /// resolve it at all (`requestInfo returned: -100`) and the query settles
  /// on UNKNOWN_ERROR. Failing open therefore showed a scan entry point on
  /// precisely the devices that can never use it. Capable hardware, by
  /// contrast, answers definitively — `supported` when ARCore is present,
  /// `supportedNotInstalled` when it is not — so nothing is lost by
  /// requiring a positive answer.
  static ScanCapability fromAvailability(ArCoreAvailability availability) =>
      switch (availability) {
        ArCoreAvailability.supported ||
        ArCoreAvailability.supportedNotInstalled ||
        ArCoreAvailability.supportedApkTooOld =>
          ScanCapability.available,
        // Includes `checking`: an unsettled answer is not a positive one.
        // [ScanCapabilityCubit.resolve] polls so this is only reached once
        // ARCore has genuinely stopped saying "checking".
        ArCoreAvailability.unsupported ||
        ArCoreAvailability.checking ||
        ArCoreAvailability.unknown =>
          ScanCapability.unavailable,
      };
}

/// Resolves [ScanCapability] once at startup and holds it for the app.
///
/// A Cubit rather than a plain cached bool because the answer arrives
/// asynchronously and several screens rebuild on it — the same reason
/// ThemeCubit is app-wide.
class ScanCapabilityCubit extends Cubit<ScanCapability> {
  ScanCapabilityCubit(this._depth) : super(ScanCapability.checking);

  final ArCoreDepthService _depth;

  /// How long to keep re-asking while ARCore answers `checking`.
  ///
  /// `ArCoreApk.checkAvailability` is asynchronous on first call: it may
  /// return UNKNOWN_CHECKING and expects the caller to query again rather
  /// than treat that as the answer. Without this the very first query decides
  /// the feature's fate, which on a cold start is a coin flip.
  static const Duration _pollInterval = Duration(milliseconds: 200);
  static const int _maxPolls = 15; // ~3s

  /// Asks ARCore whether this device qualifies. Safe to call more than once —
  /// a user who installs ARCore and returns can be re-checked.
  Future<void> resolve() async {
    var availability = await _depth.checkAvailability();

    var polls = 0;
    while (availability == ArCoreAvailability.checking && polls < _maxPolls) {
      await Future<void>.delayed(_pollInterval);
      if (isClosed) return;
      availability = await _depth.checkAvailability();
      polls++;
    }

    final capability = ScanCapability.fromAvailability(availability);
    AppLogger.info(
      'SCAN-CAPABILITY $capability :: arcore=${availability.name} '
      'polls=$polls',
    );
    if (!isClosed) emit(capability);
  }
}
