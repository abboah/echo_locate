import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';

import 'route_layout_test.dart' show landmarksOn, routeOf;

void main() {
  group('merge', () {
    test('two routes sharing landmarks become one graph with no duplicates',
        () {
      // The spec's own acceptance check for A3.
      // r1: A -> B -> C   r2: A -> B -> D
      final r1 = routeOf([('B', 10, 0), ('C', 10, 90)], id: 'r1');
      final r2 = routeOf([('B', 10, 0), ('D', 12, -90)], id: 'r2');
      final landmarks = landmarksOn('g', ['A', 'B', 'C', 'D']).values.toList();

      final graph = merge([r1, r2], landmarks);

      expect(graph.nodes.keys.toSet(), {'A', 'B', 'C', 'D'});
      expect(graph.edges, hasLength(3));
      // A shared landmark is one node, not one per route.
      expect(graph.nodes, hasLength(4));
    });

    test('a landmark walked by both routes lands in the same place once', () {
      final r1 = routeOf([('B', 10, 0), ('C', 10, 90)], id: 'r1');
      final r2 = routeOf([('B', 10, 0), ('D', 12, -90)], id: 'r2');
      final landmarks = landmarksOn('g', ['A', 'B', 'C', 'D']).values.toList();

      final result = mergeWithDiagnostics([r1, r2], landmarks);

      // Both routes agree exactly on A and B, so there is nothing to average.
      expect(result.worstSpreadM, closeTo(0, 0.01));
      expect(result.unanchoredRouteIds, isEmpty);
    });

    test('a route starting elsewhere is rotated into the shared frame', () {
      // r2 starts at C, not A. Laid out naively it would put C at the origin,
      // dragging every landmark it shares with r1 metres out of position.
      final r1 = routeOf([('B', 10, 0), ('C', 10, 90)], id: 'r1');
      final r2 = routeOf([('B', 10, 0), ('E', 7, 0)], id: 'r2', start: 'C');
      final landmarks =
          landmarksOn('g', ['A', 'B', 'C', 'E']).values.toList();

      final result = mergeWithDiagnostics([r1, r2], landmarks);
      final graph = result.graph;

      // C is where r1 put it: 10 m up, then 10 m right.
      expect(graph.nodes['C']!.x, closeTo(10, 0.01));
      expect(graph.nodes['C']!.y, closeTo(10, 0.01));
      // B keeps r1's position too, rather than being averaged with a stray
      // placement from r2's own frame.
      expect(graph.nodes['B']!.x, closeTo(0, 0.01));
      expect(graph.nodes['B']!.y, closeTo(10, 0.01));
      expect(result.unanchoredRouteIds, isEmpty);
    });

    test('a route sharing nothing is reported as unanchored', () {
      final r1 = routeOf([('B', 10, 0)], id: 'r1');
      final r2 = routeOf([('Z', 10, 0)], id: 'r2', start: 'Y');
      final landmarks = landmarksOn('g', ['A', 'B', 'Y', 'Z']).values.toList();

      final result = mergeWithDiagnostics([r1, r2], landmarks);

      expect(result.unanchoredRouteIds, ['r2']);
      // Still present — a disconnected wing of a building is real data. The
      // painter is told not to draw it as if it joins on.
      expect(result.graph.nodes.keys, containsAll(['Y', 'Z']));
    });

    test('disagreeing placements are averaged and the spread reported', () {
      // Both routes walk A -> B -> C, but r2 records the second leg 4 m longer.
      final r1 = routeOf([('B', 10, 0), ('C', 10, 0)], id: 'r1');
      final r2 = routeOf([('B', 10, 0), ('C', 14, 0)], id: 'r2');
      final landmarks = landmarksOn('g', ['A', 'B', 'C']).values.toList();

      final result = mergeWithDiagnostics([r1, r2], landmarks);

      expect(result.graph.nodes['C']!.y, closeTo(22, 0.01));
      expect(result.spreadM['C'], closeTo(4, 0.01));
      expect(result.spreadM.containsKey('A'), isFalse);
    });

    test('the same corridor walked twice is one edge with a mean distance', () {
      final r1 = routeOf([('B', 10, 0)], id: 'r1');
      // Walked the other way, and measured a little longer.
      final r2 = routeOf([('A', 12, 0)], id: 'r2', start: 'B');
      final landmarks = landmarksOn('g', ['A', 'B']).values.toList();

      final graph = merge([r1, r2], landmarks);

      expect(graph.edges, hasLength(1));
      expect(graph.edges.single.distanceM, closeTo(11, 0.001));
    });

    test('merging nothing yields an empty graph', () {
      final graph = merge([], []);
      expect(graph.isEmpty, isTrue);
      expect(graph.edges, isEmpty);
    });
  });

  group('FloorGraph floor handling', () {
    test('nodes keep the floor their landmark declares', () {
      final route = routeOf([('B', 12, 0), ('C', 8, 0), ('D', 6, -90)]);
      final landmarks = [
        ...landmarksOn('g', ['A', 'B']).values,
        ...landmarksOn('2', ['C', 'D']).values,
      ];

      final graph = merge([route], landmarks);

      expect(graph.floorIds, {'g', '2'});
      expect(graph.nodesOn('g').map((n) => n.landmarkId), ['A', 'B']);
      expect(graph.nodesOn('2').map((n) => n.landmarkId), ['C', 'D']);
    });

    test('a stairs edge is drawn on neither floor', () {
      final route = routeOf([('B', 12, 0), ('C', 8, 0), ('D', 6, -90)]);
      final landmarks = [
        ...landmarksOn('g', ['A', 'B']).values,
        ...landmarksOn('2', ['C', 'D']).values,
      ];

      final graph = merge([route], landmarks);

      // B->C crosses floors. Drawing it on either plane would imply a corridor
      // that is not there.
      expect(graph.edgesOn('g').map((e) => e.key), ['A|B']);
      expect(graph.edgesOn('2').map((e) => e.key), ['C|D']);
      expect(graph.edges, hasLength(3));
    });

    test('edgesFrom finds a landmark in either direction', () {
      final graph = merge(
        [routeOf([('B', 10, 0), ('C', 10, 90)])],
        landmarksOn('g', ['A', 'B', 'C']).values.toList(),
      );

      expect(graph.edgesFrom('B'), hasLength(2));
      expect(
        graph.edgesFrom('B').map((e) => e.otherEnd('B')).toSet(),
        {'A', 'C'},
      );
    });
  });

  group('the seeded library routes', () {
    test('merges into a two-floor schematic with the stairs stacked', () async {
      final repository = MockRouteRepository();
      final routes = await repository.routesOf('knust-library');
      final landmarks = await repository.landmarksOf('knust-library');

      final graph = merge(routes, landmarks);

      // Seven landmarks across two overlapping routes, not eleven: the four
      // legs they share collapse into the same nodes.
      expect(graph.nodes, hasLength(7));
      expect(graph.floorIds, {'floor-g', 'floor-2'});

      // The floor-2 landing sits directly above the ground-floor stairwell.
      final stairs = graph.nodes['lm-stairs-g']!;
      final landing = graph.nodes['lm-landing-2']!;
      expect(landing.x, closeTo(stairs.x, 0.01));
      expect(landing.y, closeTo(stairs.y, 0.01));

      // Ground floor is an L: 12 m up from the entrance, then 18 m right.
      expect(graph.nodes['lm-desk']!.y, closeTo(12, 0.01));
      expect(stairs.x, closeTo(18, 0.01));
    });

    test('every leg is an edge and the graph is connected', () async {
      final repository = MockRouteRepository();
      final routes = await repository.routesOf('knust-library');
      final landmarks = await repository.landmarksOf('knust-library');

      final result = mergeWithDiagnostics(routes, landmarks);

      // Six corridors: four shared, plus one to each floor-2 door.
      expect(result.graph.edges, hasLength(6));
      expect(result.unanchoredRouteIds, isEmpty);
      // The two recordings agree on every shared leg, so nothing is averaged.
      expect(result.spreadM, isEmpty);

      // Landmarks are only useful if legs reach them.
      for (final id in result.graph.nodes.keys) {
        expect(result.graph.edgesFrom(id), isNotEmpty, reason: '$id is orphaned');
      }
    });

    test('only doors carry a room id', () async {
      final repository = MockRouteRepository();
      final landmarks = await repository.landmarksOf('knust-library');
      final withRoom = landmarks.where((l) => l.roomId != null);

      // One per destination — this link is how Phase 2 resolves a room to a
      // landmark, so a junction claiming a room would misroute.
      expect(withRoom.map((l) => l.roomId), ['reading-hall', 'study-2b']);
      expect(withRoom.every((l) => l.kind == LandmarkKind.door), isTrue);
    });

    test('the two routes diverge at the directory board', () async {
      final repository = MockRouteRepository();
      final routes = await repository.routesOf('knust-library');
      final landmarks = await repository.landmarksOf('knust-library');

      final graph = merge(routes, landmarks);

      // Three ways out of the board: back to the landing, and one to each
      // door. That branch is what makes A* worth running.
      expect(graph.edgesFrom('lm-corridor-2'), hasLength(3));
    });
  });
}
