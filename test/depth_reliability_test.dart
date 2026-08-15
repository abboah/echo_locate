import 'package:echo_locate/services/vision/depth_frame.dart';
import 'package:echo_locate/services/vision/depth_reliability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A frame with [valid] of its 12 cells carrying depth. The centre cell
  /// (row 1, column 2 of a 4x3 grid) is filled unless [centerDepth] is 0.
  DepthFrame frame({
    required int valid,
    int centerDepth = 2000,
    DepthTrackingState tracking = DepthTrackingState.tracking,
    bool hasDepth = true,
  }) {
    const columns = 4;
    const rows = 3;
    const centerIndex = (rows ~/ 2) * columns + (columns ~/ 2);
    final grid = List<int>.filled(columns * rows, 0);

    var filled = 0;
    for (var i = 0; i < grid.length && filled < valid; i++) {
      if (i == centerIndex) continue;
      grid[i] = 1500;
      filled++;
    }
    grid[centerIndex] = centerDepth;

    return DepthFrame(
      trackingState: tracking,
      hasDepth: hasDepth,
      width: 160,
      height: 120,
      gridColumns: columns,
      gridRows: rows,
      grid: grid,
      minMillimeters: 1500,
      maxMillimeters: 2000,
      meanMillimeters: 1700,
      validSamples: centerDepth == 0 ? filled : filled + 1,
      timestampNs: 1,
      translation: const [0, 0, 0],
      rotation: const [0, 0, 0, 1],
    );
  }

  const reliability = DepthReliability();

  group('depth is trusted', () {
    test('a well-covered tracking frame needs no acoustic help', () {
      final f = frame(valid: 10);

      expect(reliability.assess(f), DepthDoubt.none);
      expect(reliability.shouldFallBack(f), isFalse);
    });
  });

  group('depth is not trusted', () {
    test('no frame yet falls back rather than waiting for the camera', () {
      expect(reliability.assess(null), DepthDoubt.noDepth);
      expect(reliability.shouldFallBack(null), isTrue);
    });

    test('a lost pose is not usable however much depth arrives', () {
      // Depth values without a pose have nowhere to be placed on a plan.
      final f = frame(valid: 11, tracking: DepthTrackingState.paused);

      expect(reliability.assess(f), DepthDoubt.notTracking);
    });

    test('depth still converging falls back', () {
      expect(
        reliability.assess(frame(valid: 0, hasDepth: false)),
        DepthDoubt.noDepth,
      );
    });

    test('a bare wall or window returns too few cells to believe', () {
      // The documented low-light / featureless-surface case: the frame
      // arrives, and almost every cell comes back empty.
      expect(reliability.assess(frame(valid: 1)), DepthDoubt.sparseCoverage);
    });

    test('good coverage with an empty centre still falls back', () {
      // A doorway ahead with walls either side. Coverage looks healthy while
      // the one direction being asked about is exactly the one with no answer.
      final f = frame(valid: 11, centerDepth: 0);

      expect(reliability.assess(f), DepthDoubt.noCenterDepth);
    });
  });

  group('coverage threshold', () {
    test('is a parameter, so evaluation can re-fit it', () {
      final sparse = frame(valid: 3); // 4/12 = 0.33

      expect(
        const DepthReliability(minimumCoverage: 0.25).assess(sparse),
        DepthDoubt.none,
      );
      expect(
        const DepthReliability(minimumCoverage: 0.5).assess(sparse),
        DepthDoubt.sparseCoverage,
      );
    });
  });
}
