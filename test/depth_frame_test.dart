import 'package:echo_locate/services/vision/depth_frame.dart';
import 'package:flutter_test/flutter_test.dart';

/// A native payload shaped exactly like ArCoreDepthHandler.buildPayload emits.
Map<Object?, Object?> _payload({
  List<int>? grid,
  int columns = 4,
  int rows = 3,
  String tracking = 'TRACKING',
}) {
  final cells = grid ?? List<int>.filled(columns * rows, 1000);
  final valid = cells.where((v) => v != 0).toList();
  return {
    'hasDepth': true,
    'trackingState': tracking,
    'width': 160,
    'height': 120,
    'gridColumns': columns,
    'gridRows': rows,
    'grid': cells,
    'minMillimeters': valid.isEmpty ? 0 : valid.reduce((a, b) => a < b ? a : b),
    'maxMillimeters': valid.isEmpty ? 0 : valid.reduce((a, b) => a > b ? a : b),
    'meanMillimeters': valid.isEmpty
        ? 0
        : valid.reduce((a, b) => a + b) ~/ valid.length,
    'validSamples': valid.length,
    'timestampNs': 123456789,
    'translation': [1.0, 2.0, 3.0],
    'rotation': [0.0, 0.0, 0.0, 1.0],
  };
}

void main() {
  group('ArCoreAvailability', () {
    test('maps every native string the handler can emit', () {
      expect(
        ArCoreAvailability.fromNative('supported'),
        ArCoreAvailability.supported,
      );
      expect(
        ArCoreAvailability.fromNative('supportedNotInstalled'),
        ArCoreAvailability.supportedNotInstalled,
      );
      expect(
        ArCoreAvailability.fromNative('supportedApkTooOld'),
        ArCoreAvailability.supportedApkTooOld,
      );
      expect(
        ArCoreAvailability.fromNative('unsupported'),
        ArCoreAvailability.unsupported,
      );
      expect(
        ArCoreAvailability.fromNative('checking'),
        ArCoreAvailability.checking,
      );
    });

    test(
      'unrecognised and null values fall back to unknown, not supported',
      () {
        // Failing closed matters: treating an unparsed value as supported would
        // start a session on a device that cannot run one.
        expect(
          ArCoreAvailability.fromNative('error'),
          ArCoreAvailability.unknown,
        );
        expect(
          ArCoreAvailability.fromNative('timedOut'),
          ArCoreAvailability.unknown,
        );
        expect(ArCoreAvailability.fromNative(null), ArCoreAvailability.unknown);
        expect(
          ArCoreAvailability.fromNative('nonsense'),
          ArCoreAvailability.unknown,
        );
      },
    );

    test('only "supported" is ready; install/update states are user-fixable', () {
      expect(ArCoreAvailability.supported.isReady, isTrue);
      for (final other in ArCoreAvailability.values.where(
        (v) => v != ArCoreAvailability.supported,
      )) {
        expect(other.isReady, isFalse, reason: '$other must not be ready');
      }

      expect(ArCoreAvailability.supportedNotInstalled.isUserFixable, isTrue);
      expect(ArCoreAvailability.supportedApkTooOld.isUserFixable, isTrue);
      // An uncertified device is permanent — prompting the user would be a lie.
      expect(ArCoreAvailability.unsupported.isUserFixable, isFalse);
    });
  });

  group('DepthFrame.fromNative', () {
    test('parses a tracking frame with depth', () {
      final frame = DepthFrame.fromNative(_payload());

      expect(frame.hasDepth, isTrue);
      expect(frame.trackingState, DepthTrackingState.tracking);
      expect(frame.width, 160);
      expect(frame.grid.length, 12);
      expect(frame.meanMeters, closeTo(1.0, 1e-9));
      expect(frame.translation, [1.0, 2.0, 3.0]);
      expect(frame.rotation, [0.0, 0.0, 0.0, 1.0]);
    });

    test('a frame without depth carries no stale grid', () {
      // Depth-from-motion produces pose-only frames until the user has moved
      // enough for parallax; those must not look like a 0m reading.
      final frame = DepthFrame.fromNative({
        'hasDepth': false,
        'trackingState': 'PAUSED',
      });

      expect(frame.hasDepth, isFalse);
      expect(frame.trackingState, DepthTrackingState.paused);
      expect(frame.grid, isEmpty);
      expect(frame.centerMeters, isNull);
    });

    test('centre cell is read from the middle of the grid', () {
      final grid = List<int>.filled(12, 1000);
      // Middle of a 4x3 grid: row 1, col 2 -> index 6.
      grid[6] = 2500;
      final frame = DepthFrame.fromNative(_payload(grid: grid));

      expect(frame.centerMeters, closeTo(2.5, 1e-9));
    });

    test('a zero centre cell reads as null, not as zero distance', () {
      // 0 is ARCore's "no depth here" sentinel. Reporting it as 0.00m would
      // tell a navigating user a wall is against their face.
      final grid = List<int>.filled(12, 1000);
      grid[6] = 0;
      final frame = DepthFrame.fromNative(_payload(grid: grid));

      expect(frame.centerMeters, isNull);
    });

    test('millimetres convert to metres', () {
      final grid = [500, 1500, 3000, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      final frame = DepthFrame.fromNative(_payload(grid: grid));

      expect(frame.minMeters, closeTo(0.5, 1e-9));
      expect(frame.maxMeters, closeTo(3.0, 1e-9));
      expect(frame.validSamples, 3);
    });

    test('a malformed payload degrades instead of throwing', () {
      // The channel is a trust boundary: a shape change in native code must
      // not crash the scan screen.
      final frame = DepthFrame.fromNative({
        'hasDepth': true,
        'trackingState': 'TRACKING',
        'grid': 'not a list',
        'translation': null,
        'width': 'oops',
      });

      expect(frame.width, 0);
      expect(frame.grid, isEmpty);
      expect(frame.translation, isEmpty);
      expect(frame.centerMeters, isNull);
    });
  });
}
