import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/route_layout.dart';

/// Builds a route from `(to, distance, turn)` triples, starting at 'A'.
/// Landmark ids are single letters so the geometry stays readable.
WalkRoute routeOf(
  List<(String, double, int)> legs, {
  String id = 'r1',
  String start = 'A',
}) {
  var from = start;
  final steps = <RouteStep>[];
  for (var i = 0; i < legs.length; i++) {
    final (to, distance, turn) = legs[i];
    steps.add(
      RouteStep(
        seq: i + 1,
        fromLandmarkId: from,
        toLandmarkId: to,
        instruction: 'leg ${i + 1}',
        distanceM: distance,
        turnDeg: turn,
      ),
    );
    from = to;
  }
  return WalkRoute(
    id: id,
    buildingId: 'b',
    startLandmarkId: start,
    destinationRoomId: 'room',
    steps: steps,
    totalDistanceM: steps.fold<double>(0, (sum, s) => sum + s.distanceM),
  );
}

Map<String, Landmark> landmarksOn(String floorId, List<String> ids) => {
      for (final id in ids)
        id: Landmark(
          id: id,
          buildingId: 'b',
          floorId: floorId,
          kind: LandmarkKind.junction,
          labelText: id,
          displayName: id,
        ),
    };

void main() {
  group('layout', () {
    test('a 10 m square turning 90° each leg closes on the origin', () {
      // The spec's own acceptance check for A2.
      final route = routeOf([
        ('B', 10, 0),
        ('C', 10, 90),
        ('D', 10, 90),
        ('A2', 10, 90),
      ]);
      final nodes = layout(
        route,
        landmarksOn('g', ['A', 'B', 'C', 'D', 'A2']),
      );

      expect(nodes, hasLength(5));
      expect(nodes.last.x, closeTo(0, 0.01));
      expect(nodes.last.y, closeTo(0, 0.01));
    });

    test('heading 0 is +y and a positive turn goes to +x', () {
      final nodes = layout(
        routeOf([('B', 5, 0), ('C', 5, 90)]),
        landmarksOn('g', ['A', 'B', 'C']),
      );

      // Straight ahead: up the map.
      expect(nodes[1].x, closeTo(0, 0.001));
      expect(nodes[1].y, closeTo(5, 0.001));
      // Then a right turn: east.
      expect(nodes[2].x, closeTo(5, 0.001));
      expect(nodes[2].y, closeTo(5, 0.001));
    });

    test('a left turn mirrors a right turn', () {
      final right = layout(
        routeOf([('B', 8, 90)]),
        landmarksOn('g', ['A', 'B']),
      );
      final left = layout(
        routeOf([('B', 8, -90)]),
        landmarksOn('g', ['A', 'B']),
      );

      expect(right.last.x, closeTo(-left.last.x, 0.001));
      expect(right.last.y, closeTo(left.last.y, 0.001));
    });

    test('sharp turns are honoured as ±135°', () {
      final nodes = layout(
        routeOf([('B', 10, 135)]),
        landmarksOn('g', ['A', 'B']),
      );
      expect(nodes.last.x, closeTo(7.071, 0.01));
      expect(nodes.last.y, closeTo(-7.071, 0.01));
    });

    test('a stairs leg changes floor without displacing the plan', () {
      // Ground: A -> B walking 12 m. Then B -> C is a floor change.
      final route = routeOf([('B', 12, 0), ('C', 8, 0)]);
      final landmarks = {
        ...landmarksOn('g', ['A', 'B']),
        ...landmarksOn('2', ['C']),
      };

      final nodes = layout(route, landmarks);

      expect(nodes[1].floorId, 'g');
      expect(nodes[2].floorId, '2');
      // The landing sits directly above the stairwell — climbing eight metres
      // must not push it eight metres down a ground-floor corridor.
      expect(nodes[2].x, closeTo(nodes[1].x, 0.001));
      expect(nodes[2].y, closeTo(nodes[1].y, 0.001));
    });

    test('heading carries through a floor change', () {
      final route = routeOf([('B', 10, 90), ('C', 4, 0), ('D', 6, 0)]);
      final landmarks = {
        ...landmarksOn('g', ['A', 'B']),
        ...landmarksOn('2', ['C', 'D']),
      };

      final nodes = layout(route, landmarks);

      // Still facing +x after the stairs, so the floor-2 leg runs east.
      expect(nodes.last.x, closeTo(16, 0.001));
      expect(nodes.last.y, closeTo(0, 0.001));
    });

    test('legs are laid out in seq order however they arrive', () {
      final ordered = routeOf([('B', 10, 0), ('C', 10, 90)]);
      final shuffled = ordered.copyWith(steps: ordered.steps.reversed.toList());
      final landmarks = landmarksOn('g', ['A', 'B', 'C']);

      expect(layout(shuffled, landmarks), layout(ordered, landmarks));
    });

    test('a route with no legs places just its start landmark', () {
      const route = WalkRoute(
        id: 'r',
        buildingId: 'b',
        startLandmarkId: 'A',
        destinationRoomId: 'room',
        steps: [],
      );
      final nodes = layout(route, landmarksOn('g', ['A']));

      expect(nodes, hasLength(1));
      expect(nodes.single.landmarkId, 'A');
      expect(nodes.single.floorId, 'g');
    });

    test('an empty route with no start landmark lays out to nothing', () {
      const route = WalkRoute(
        id: 'r',
        buildingId: 'b',
        startLandmarkId: '',
        destinationRoomId: 'room',
        steps: [],
      );
      expect(layout(route, const {}), isEmpty);
    });

    test('an unknown landmark inherits the previous floor rather than throwing',
        () {
      // A partial landmark fetch must degrade, not crash: the plan is worth
      // more slightly mislabelled than absent.
      final nodes = layout(
        routeOf([('B', 10, 0), ('unknown', 5, 0)]),
        landmarksOn('g', ['A', 'B']),
      );

      expect(nodes, hasLength(3));
      expect(nodes.last.floorId, 'g');
      expect(nodes.last.y, closeTo(15, 0.001));
    });
  });

  group('misclosureOf', () {
    test('is null when no landmark is revisited', () {
      final nodes = layout(
        routeOf([('B', 10, 0), ('C', 10, 90)]),
        landmarksOn('g', ['A', 'B', 'C']),
      );
      expect(misclosureOf(nodes), isNull);
    });

    test('is near zero for a square that closes', () {
      final nodes = layout(
        routeOf([('B', 10, 0), ('C', 10, 90), ('D', 10, 90), ('A', 10, 90)]),
        landmarksOn('g', ['A', 'B', 'C', 'D']),
      );
      expect(misclosureOf(nodes), closeTo(0, 0.01));
    });

    test('measures the gap when tapped turns do not match the building', () {
      // Four 80° corners recorded as 90° each — the real case the spec warns
      // about. The loop is left visibly open, and by how much is a result.
      final nodes = layout(
        routeOf([('B', 10, 0), ('C', 10, 90), ('D', 10, 90), ('A', 10, 90)]),
        landmarksOn('g', ['A', 'B', 'C', 'D']),
      );
      final closed = misclosureOf(nodes)!;

      final skewed = layout(
        routeOf([('B', 10, 0), ('C', 10, 80), ('D', 10, 80), ('A', 10, 80)]),
        landmarksOn('g', ['A', 'B', 'C', 'D']),
      );

      expect(misclosureOf(skewed)!, greaterThan(closed + 1));
    });
  });
}
