import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/services/mapping/map_node.dart';
import 'package:echo_locate/services/mapping/plan_viewport.dart';

/// The metric zoom cap, which is what every test below is working in.
const metric = PlanViewport.maxPixelsPerMetre;

List<MapNode> nodesAt(List<(double, double)> points) => [
  for (var i = 0; i < points.length; i++)
    MapNode(landmarkId: 'n$i', floorId: 'g', x: points[i].$1, y: points[i].$2),
];

void main() {
  group('PlanViewport.fit', () {
    test('centres a plan whose origin is nowhere near the middle', () {
      // Layout frames start wherever the first route started, so a plan of a
      // far corner of a building is entirely normal.
      final nodes = nodesAt([(100, 200), (140, 240)]);
      final viewport = PlanViewport.fit(
        nodes,
        width: 400,
        height: 400,
        maxScale: metric,
      );

      expect(viewport.toCanvasX(120), closeTo(200, 0.01));
      expect(viewport.toCanvasY(220), closeTo(200, 0.01));
    });

    test('keeps every node inside the canvas', () {
      final nodes = nodesAt([(0, 0), (60, 0), (60, 45), (0, 45)]);
      const width = 320.0;
      const height = 500.0;
      final viewport = PlanViewport.fit(
        nodes,
        width: width,
        height: height,
        maxScale: metric,
      );

      for (final node in nodes) {
        expect(viewport.toCanvasX(node.x), inInclusiveRange(0, width));
        expect(viewport.toCanvasY(node.y), inInclusiveRange(0, height));
      }
    });

    test('respects the padding it was given', () {
      final nodes = nodesAt([(0, 0), (100, 100)]);
      final viewport = PlanViewport.fit(
        nodes,
        width: 300,
        height: 300,
        padding: 40,
        maxScale: metric,
      );

      expect(viewport.toCanvasX(0), greaterThanOrEqualTo(40 - 0.01));
      expect(viewport.toCanvasX(100), lessThanOrEqualTo(260 + 0.01));
    });

    test('flips y so north is up', () {
      final nodes = nodesAt([(0, 0), (0, 10)]);
      final viewport = PlanViewport.fit(
        nodes,
        width: 200,
        height: 200,
        maxScale: metric,
      );

      // 10 m north must render *above* the origin, not below it. Getting this
      // backwards mirrors the plan, which is subtle enough to ship unnoticed.
      expect(viewport.toCanvasY(10), lessThan(viewport.toCanvasY(0)));
    });

    test('preserves aspect ratio — a square plan stays square', () {
      final nodes = nodesAt([(0, 0), (20, 0), (20, 20), (0, 20)]);
      final viewport = PlanViewport.fit(
        nodes,
        width: 600,
        height: 200,
        maxScale: metric,
      );

      final drawnWidth = viewport.toCanvasX(20) - viewport.toCanvasX(0);
      final drawnHeight = viewport.toCanvasY(0) - viewport.toCanvasY(20);
      expect(drawnWidth, closeTo(drawnHeight, 0.01));
    });

    test('a straight corridor still fits across its one axis', () {
      // Extent in x, none in y — the most common real shape, and the case a
      // naive min() over both spans divides by zero on.
      final nodes = nodesAt([(0, 0), (40, 0)]);
      final viewport = PlanViewport.fit(
        nodes,
        width: 400,
        height: 400,
        padding: 20,
        maxScale: 1000,
      );

      expect(viewport.toCanvasX(0), closeTo(20, 0.01));
      expect(viewport.toCanvasX(40), closeTo(380, 0.01));
      expect(viewport.toCanvasY(0), closeTo(200, 0.01));
    });

    test('a vertical corridor fits the other way round', () {
      final nodes = nodesAt([(0, 0), (0, 40)]);
      final viewport = PlanViewport.fit(
        nodes,
        width: 400,
        height: 400,
        padding: 20,
        maxScale: 1000,
      );

      expect(viewport.toCanvasY(40), closeTo(20, 0.01));
      expect(viewport.toCanvasY(0), closeTo(380, 0.01));
    });

    test('a unitless traced floor fills the canvas rather than a corner', () {
      // The bug this pins, found by tracing a real wall board on a phone: the
      // cap was a bare `maxScale = 22` default, meaning pixels per *metre*.
      // A traced plan is in image fractions — a whole floor is about one unit
      // across — so three rooms rendered as a nine-pixel smudge in the middle
      // of an empty sheet, with no error and nothing to point at the scale.
      final rooms = nodesAt([(0.10, -0.32), (0.54, -0.32), (0.54, -0.10)]);
      final viewport = PlanViewport.fit(
        rooms,
        width: 400,
        height: 700,
        maxScale: PlanViewport.maxScaleFor(null),
      );

      // The 0.44-unit span should cross most of the 400 px canvas.
      final drawnWidth = viewport.toCanvasX(0.54) - viewport.toCanvasX(0.10);
      expect(drawnWidth, greaterThan(300));

      // And a scale set on the plan is still honoured as metres.
      final metricViewport = PlanViewport.fit(
        rooms,
        width: 400,
        height: 700,
        maxScale: PlanViewport.maxScaleFor(50),
      );
      expect(metricViewport.scale, viewport.scale);
    });

    test('a two-node plan is not blown up to fill the screen', () {
      // Without a cap, a 7 m corridor renders at 50 px per metre and looks
      // broken rather than zoomed.
      final nodes = nodesAt([(0, 0), (7, 0)]);
      final viewport = PlanViewport.fit(
        nodes,
        width: 800,
        height: 800,
        maxScale: 22,
      );

      expect(viewport.scale, 22);
    });

    test('a single node is centred rather than dividing by zero', () {
      final viewport = PlanViewport.fit(
        nodesAt([(5, 5)]),
        width: 300,
        height: 400,
        maxScale: metric,
      );

      expect(viewport.scale, greaterThan(0));
      expect(viewport.toCanvasX(5), closeTo(150, 0.01));
      expect(viewport.toCanvasY(5), closeTo(200, 0.01));
    });

    test('an empty plan yields a usable viewport rather than NaN', () {
      final viewport = PlanViewport.fit(
        const [],
        width: 300,
        height: 300,
        maxScale: metric,
      );

      expect(viewport.scale.isFinite, isTrue);
      expect(viewport.toCanvasX(0).isFinite, isTrue);
      expect(viewport.toCanvasY(0).isFinite, isTrue);
    });

    test('survives a canvas smaller than its own padding', () {
      // First layout pass can hand a painter a near-zero size.
      final viewport = PlanViewport.fit(
        nodesAt([(0, 0), (10, 10)]),
        width: 10,
        height: 10,
        padding: 32,
        maxScale: metric,
      );

      expect(viewport.scale.isFinite, isTrue);
      expect(viewport.scale, greaterThan(0));
    });
  });
}
