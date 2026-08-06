import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/services/mapping/map_node.dart';
import 'package:echo_locate/services/mapping/plan_viewport.dart';

List<MapNode> nodesAt(List<(double, double)> points) => [
      for (var i = 0; i < points.length; i++)
        MapNode(
          landmarkId: 'n$i',
          floorId: 'g',
          x: points[i].$1,
          y: points[i].$2,
        ),
    ];

void main() {
  group('PlanViewport.fit', () {
    test('centres a plan whose origin is nowhere near the middle', () {
      // Layout frames start wherever the first route started, so a plan of a
      // far corner of a building is entirely normal.
      final nodes = nodesAt([(100, 200), (140, 240)]);
      final viewport = PlanViewport.fit(nodes, width: 400, height: 400);

      expect(viewport.toCanvasX(120), closeTo(200, 0.01));
      expect(viewport.toCanvasY(220), closeTo(200, 0.01));
    });

    test('keeps every node inside the canvas', () {
      final nodes = nodesAt([(0, 0), (60, 0), (60, 45), (0, 45)]);
      const width = 320.0;
      const height = 500.0;
      final viewport = PlanViewport.fit(nodes, width: width, height: height);

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
      );

      expect(viewport.toCanvasX(0), greaterThanOrEqualTo(40 - 0.01));
      expect(viewport.toCanvasX(100), lessThanOrEqualTo(260 + 0.01));
    });

    test('flips y so north is up', () {
      final nodes = nodesAt([(0, 0), (0, 10)]);
      final viewport = PlanViewport.fit(nodes, width: 200, height: 200);

      // 10 m north must render *above* the origin, not below it. Getting this
      // backwards mirrors the plan, which is subtle enough to ship unnoticed.
      expect(viewport.toCanvasY(10), lessThan(viewport.toCanvasY(0)));
    });

    test('preserves aspect ratio — a square plan stays square', () {
      final nodes = nodesAt([(0, 0), (20, 0), (20, 20), (0, 20)]);
      final viewport = PlanViewport.fit(nodes, width: 600, height: 200);

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
      );

      expect(viewport.scale, greaterThan(0));
      expect(viewport.toCanvasX(5), closeTo(150, 0.01));
      expect(viewport.toCanvasY(5), closeTo(200, 0.01));
    });

    test('an empty plan yields a usable viewport rather than NaN', () {
      final viewport = PlanViewport.fit(const [], width: 300, height: 300);

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
      );

      expect(viewport.scale.isFinite, isTrue);
      expect(viewport.scale, greaterThan(0));
    });
  });
}
