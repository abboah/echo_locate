import 'dart:math' as math;

import 'package:echo_locate/services/mapping/room_cleanup.dart';
import 'package:echo_locate/services/mapping/room_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Interior corner angles in degrees, in vertex order.
List<double> cornerAngles(List<Offset> polygon) => [
  for (var i = 0; i < polygon.length; i++)
    signedTurnRad(
          polygon[i] - polygon[(i - 1 + polygon.length) % polygon.length],
          polygon[(i + 1) % polygon.length] - polygon[i],
        ).abs() *
        180 /
        math.pi,
];

void main() {
  group('dropShortEdges', () {
    test('removes a finger slip', () {
      final cleaned = dropShortEdges(const [
        Offset(0, 0),
        Offset(6, 0),
        Offset(6.05, 0.05), // 7 cm away — nobody meant to tap this
        Offset(6, 4),
        Offset(0, 4),
      ], kMinEdgeMetres);

      expect(cleaned.length, 4);
      expect(cleaned, isNot(contains(const Offset(6.05, 0.05))));
    });

    test('thins a run of taps along one wall', () {
      // Taps 10 cm apart. Measuring against the last *kept* vertex rather than
      // the original neighbour is what thins the run: a pairwise pass would
      // find every gap short and keep the lot.
      //
      // (0.3, 0) survives on purpose — it is a full 30 cm from the anchor, so
      // this stage has no reason to drop it. Removing it is mergeCollinear's
      // job, because what is wrong with it is that it sits on a straight wall,
      // not that it is close to anything. cleanupPolygon runs both.
      final cleaned = dropShortEdges(const [
        Offset(0, 0),
        Offset(0.1, 0),
        Offset(0.2, 0),
        Offset(0.3, 0),
        Offset(6, 0),
        Offset(6, 4),
        Offset(0, 4),
      ], kMinEdgeMetres);

      expect(cleaned, isNot(contains(const Offset(0.1, 0))));
      expect(cleaned, isNot(contains(const Offset(0.2, 0))));
      expect(cleaned.length, 5);

      // …and the full pipeline finishes the job.
      expect(
        cleanupPolygon(const [
          Offset(0, 0),
          Offset(0.1, 0),
          Offset(0.2, 0),
          Offset(0.3, 0),
          Offset(6, 0),
          Offset(6, 4),
          Offset(0, 4),
        ]).length,
        4,
      );
    });

    test('drops a closing tap landing back on the first corner', () {
      final cleaned = dropShortEdges(const [
        Offset(0, 0),
        Offset(6, 0),
        Offset(6, 4),
        Offset(0, 4),
        Offset(0.02, 0.02), // "finish" tap, on top of the start
      ], kMinEdgeMetres);

      expect(cleaned.length, 4);
      expect(
        (cleaned.last - cleaned.first).distance,
        greaterThan(kMinEdgeMetres),
      );
    });

    test('never reduces a polygon below three corners', () {
      final cleaned = dropShortEdges(const [
        Offset(0, 0),
        Offset(0.01, 0),
        Offset(0, 0.01),
      ], kMinEdgeMetres);

      expect(cleaned.length, greaterThanOrEqualTo(3));
    });
  });

  group('mergeCollinear', () {
    test('removes a midpoint on a straight wall', () {
      final merged = mergeCollinear(const [
        Offset(0, 0),
        Offset(3, 0), // dead centre of the south wall
        Offset(6, 0),
        Offset(6, 4),
        Offset(0, 4),
      ], kCollinearToleranceDeg);

      expect(merged.length, 4);
      expect(merged, isNot(contains(const Offset(3, 0))));
    });

    test('iterates to a fixed point on a heavily tapped wall', () {
      // Removing one midpoint brings its neighbours into line; a single pass
      // would leave some of them behind.
      final merged = mergeCollinear(const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(2, 0),
        Offset(3, 0),
        Offset(4, 0),
        Offset(6, 0),
        Offset(6, 4),
        Offset(0, 4),
      ], kCollinearToleranceDeg);

      expect(merged.length, 4);
    });

    test('keeps a real corner', () {
      final merged = mergeCollinear(const [
        Offset(0, 0),
        Offset(6, 0),
        Offset(6, 4),
        Offset(0, 4),
      ], kCollinearToleranceDeg);

      expect(merged.length, 4);
    });
  });

  group('snapRightAngles', () {
    test('squares up a hand-tapped room', () {
      // Every corner a couple of degrees out — what a traced rectangle
      // actually looks like.
      final snapped = snapRightAngles(const [
        Offset(0, 0),
        Offset(6, 0.3),
        Offset(5.7, 4),
        Offset(-0.3, 3.7),
      ], kSnapToleranceDeg);

      for (final angle in cornerAngles(snapped)) {
        expect(angle, closeTo(90, 1e-6));
      }
    });

    test('snaps to the room\'s own grid, not to due north', () {
      // The same rectangle rotated 30 degrees. Its corners are already right
      // angles and must stay that way — snapping to a global axis would
      // destroy it.
      const angle = 30 * math.pi / 180;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      Offset rotate(Offset p) =>
          Offset(p.dx * cos - p.dy * sin, p.dx * sin + p.dy * cos);

      final rotated = [
        const Offset(0, 0),
        const Offset(6, 0),
        const Offset(6, 4),
        const Offset(0, 4),
      ].map(rotate).toList();

      final snapped = snapRightAngles(rotated, kSnapToleranceDeg);

      for (var i = 0; i < snapped.length; i++) {
        expect((snapped[i] - rotated[i]).distance, lessThan(0.01));
      }
    });

    test('leaves a wall splayed beyond tolerance alone', () {
      // A right trapezoid: one wall is 26 degrees off square, which is a
      // design, not a tapping error.
      final snapped = snapRightAngles(const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(8, 4),
        Offset(0, 4),
      ], kSnapToleranceDeg);

      final angles = cornerAngles(snapped);
      expect(
        angles.any((a) => (a - 90).abs() > 10),
        isTrue,
        reason: 'the splayed wall should have survived: $angles',
      );
    });

    test('does not teleport corners when walls come out near-parallel', () {
      const input = [Offset(0, 0), Offset(6, 0), Offset(6, 0.001)];
      final snapped = snapRightAngles(input, kSnapToleranceDeg);

      final diagonal = boundsOf(input).longestSide;
      for (var i = 0; i < snapped.length; i++) {
        expect((snapped[i] - input[i]).distance, lessThanOrEqualTo(diagonal));
      }
    });
  });

  group('cleanupPolygon end to end', () {
    test('turns a messy trace into a clean rectangle', () {
      final cleaned = cleanupPolygon(const [
        Offset(0, 0),
        Offset(3.1, 0.05), // midpoint tap on the south wall
        Offset(6, 0.3), // corner, a few degrees out
        Offset(6.02, 0.32), // 3 cm slip
        Offset(5.7, 4),
        Offset(-0.3, 3.7),
      ]);

      expect(cleaned.length, 4);
      for (final angle in cornerAngles(cleaned)) {
        expect(angle, closeTo(90, 1e-6));
      }
    });

    test('always returns counter-clockwise winding', () {
      const clockwise = [
        Offset(0, 0),
        Offset(0, 4),
        Offset(6, 4),
        Offset(6, 0),
      ];

      expect(signedArea(clockwise), lessThan(0));
      expect(signedArea(cleanupPolygon(clockwise)), greaterThan(0));
    });

    test('preserves area to within a few percent', () {
      // Cleanup is allowed to move corners; it is not allowed to change what
      // room this is.
      const raw = [
        Offset(0, 0),
        Offset(6, 0.3),
        Offset(5.7, 4),
        Offset(-0.3, 3.7),
      ];

      final before = areaOf(raw);
      final after = areaOf(cleanupPolygon(raw));

      expect((after - before).abs() / before, lessThan(0.05));
    });

    test('leaves a degenerate capture alone rather than inventing a room', () {
      expect(cleanupPolygon(const [Offset(0, 0), Offset(1, 1)]).length, 2);
      expect(cleanupPolygon(const []), isEmpty);
    });

    test('an L survives as an L', () {
      final cleaned = cleanupPolygon(const [
        Offset(0, 0),
        Offset(6, 0.1),
        Offset(6, 1),
        Offset(1.05, 1),
        Offset(1, 6),
        Offset(0, 6),
      ]);

      expect(cleaned.length, 6);
      expect(selfIntersects(cleaned), isFalse);
      expect(areaOf(cleaned), closeTo(11, 1));
    });
  });
}
