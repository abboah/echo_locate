import 'package:echo_locate/features/scan/bloc/scan_capability_cubit.dart';
import 'package:echo_locate/services/vision/arcore_depth_service.dart';
import 'package:echo_locate/services/vision/depth_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanCapability.fromAvailability', () {
    test('an uncertified device is the only one that loses the feature', () {
      expect(
        ScanCapability.fromAvailability(ArCoreAvailability.unsupported),
        ScanCapability.unavailable,
      );
    });

    test('a certified, ready device can scan', () {
      expect(
        ScanCapability.fromAvailability(ArCoreAvailability.supported),
        ScanCapability.available,
      );
    });

    test('a device only missing or outdating ARCore keeps the entry point', () {
      // These are user-fixable. Hiding the entry point would strand a capable
      // device with no route to installing ARCore.
      expect(
        ScanCapability.fromAvailability(ArCoreAvailability.supportedNotInstalled),
        ScanCapability.available,
      );
      expect(
        ScanCapability.fromAvailability(ArCoreAvailability.supportedApkTooOld),
        ScanCapability.available,
      );
    });

    test('an inconclusive answer hides the entry point', () {
      // Fails closed, and this is the case that matters most in practice: an
      // uncertified Infinix X657C does not report `unsupported` — ARCore's
      // install service cannot resolve it (`requestInfo returned: -100`) and
      // the query settles on `unknown`. Treating that as available put a scan
      // entry point on a device that can never scan.
      expect(
        ScanCapability.fromAvailability(ArCoreAvailability.unknown),
        ScanCapability.unavailable,
      );
      // An unsettled answer is not a positive one either; the cubit polls so
      // this is only reached once ARCore has stopped saying "checking".
      expect(
        ScanCapability.fromAvailability(ArCoreAvailability.checking),
        ScanCapability.unavailable,
      );
    });

    test('only a positive answer from ARCore opens the feature', () {
      final available = ArCoreAvailability.values
          .where((a) =>
              ScanCapability.fromAvailability(a) == ScanCapability.available)
          .toSet();

      expect(available, {
        ArCoreAvailability.supported,
        ArCoreAvailability.supportedNotInstalled,
        ArCoreAvailability.supportedApkTooOld,
      });
    });

    test('every availability value maps to a decision', () {
      // Guards the switch-free mapping against a future ARCore enum addition
      // silently defaulting to "hide".
      for (final availability in ArCoreAvailability.values) {
        expect(
          ScanCapability.fromAvailability(availability),
          isNot(ScanCapability.checking),
          reason: '$availability must resolve to available or unavailable',
        );
      }
    });
  });

  group('ScanCapabilityCubit', () {
    test('starts in checking so entry points stay hidden until resolved', () {
      // The gate renders nothing while checking — an entry point must never
      // appear and then vanish under a finger already reaching for it.
      final cubit = ScanCapabilityCubit(ArCoreDepthService());
      expect(cubit.state, ScanCapability.checking);
    });
  });
}
