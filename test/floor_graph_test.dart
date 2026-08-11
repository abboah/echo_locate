import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/traced_plan.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:flutter_test/flutter_test.dart';

WalkRoute routeOf(
  String id,
  List<({String from, String to, double distanceM, int turnDeg})> legs,
) =>
    WalkRoute(
      id: id,
      buildingId: 'b1',
      startLandmarkId: legs.isEmpty ? '' : legs.first.from,
      destinationRoomId: 'room-$id',
      steps: [
        for (var i = 0; i < legs.length; i++)
          RouteStep(
            seq: i + 1,
            fromLandmarkId: legs[i].from,
            toLandmarkId: legs[i].to,
            instruction: 'walk to ${legs[i].to}',
            distanceM: legs[i].distanceM,
            turnDeg: legs[i].turnDeg,
          ),
      ],
    );

({String from, String to, double distanceM, int turnDeg}) leg(
  String from,
  String to, {
  double distanceM = 10,
  int turnDeg = 0,
}) =>
    (from: from, to: to, distanceM: distanceM, turnDeg: turnDeg);

void main() {
  test('no routes make an empty graph', () {
    final graph = FloorGraph.merge(const []);

    expect(graph.isEmpty, isTrue);
    expect(graph.nodes, isEmpty);
  });

  test('one route becomes nodes and weighted edges', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b', distanceM: 10), leg('b', 'c', distanceM: 18)]),
    ]);

    expect(graph.nodes.keys, containsAll(['a', 'b', 'c']));
    expect(graph.edges.length, 2);
    expect(
      graph.edges.firstWhere((e) => e.toId == 'c').distanceM,
      18,
    );
  });

  test('edges are walkable in both directions', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
    ]);

    expect(graph.neighboursOf('a').map((n) => n.landmarkId), ['b']);
    expect(graph.neighboursOf('b').map((n) => n.landmarkId), ['a']);
  });

  test('two routes sharing landmarks merge without duplicating nodes', () {
    // r1: entrance → desk → stairs.  r2 starts mid-way: desk → stairs → 204.
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('entrance', 'desk'), leg('desk', 'stairs')]),
      routeOf('r2', [leg('desk', 'stairs'), leg('stairs', '204')]),
    ]);

    expect(graph.nodes.keys.toSet(), {'entrance', 'desk', 'stairs', '204'});
    // Every landmark reachable from the entrance: one connected component.
    expect(graph.reachableFrom('entrance'), hasLength(4));
  });

  test('a second route is rotated into the placed frame', () {
    // r2 walks the shared pair backwards, so its local heading is 180° off.
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b'), leg('b', 'c')]),
      routeOf('r2', [leg('c', 'b'), leg('b', 'd', turnDeg: 90)]),
    ]);

    // r1 places a(0,0) b(0,10) c(0,20). Walking c→b→right→d in that frame
    // puts d ten metres west of b.
    expect(graph.nodes['d']!.x, closeTo(-10, 0.01));
    expect(graph.nodes['d']!.y, closeTo(10, 0.01));
    // The shared landmarks did not move.
    expect(graph.nodes['b']!.y, closeTo(10, 0.01));
    expect(graph.nodes['c']!.y, closeTo(20, 0.01));
  });

  test('disagreeing recordings of the same landmark are averaged', () {
    // Same walk, two contributors: one counted the last leg 10m, one 12m.
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b'), leg('b', 'c', distanceM: 10)]),
      routeOf('r2', [leg('a', 'b'), leg('b', 'c', distanceM: 12)]),
    ]);

    expect(graph.nodes['c']!.y, closeTo(21, 0.01));
  });

  test('unconnected routes are laid out clear of each other', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
      routeOf('r2', [leg('x', 'y')]),
    ]);

    expect(graph.nodes.keys.toSet(), {'a', 'b', 'x', 'y'});
    expect(graph.nodes['x'], isNot(equals(graph.nodes['a'])));
    expect(graph.reachableFrom('a'), hasLength(2));
  });

  test('the same corridor recorded twice is one edge', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b', distanceM: 10)]),
      routeOf('r2', [leg('a', 'b', distanceM: 12)]),
    ]);

    expect(graph.edges, hasLength(1));
    expect(graph.edges.single.distanceM, closeTo(11, 0.01));
    expect(graph.neighboursOf('a'), hasLength(1));
  });

  test('a corridor recorded in both directions keeps both wordings', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
      routeOf('r2', [leg('b', 'a')]),
    ]);

    expect(graph.edges, hasLength(1));
    expect(graph.edges.single.instructionFor('a'), 'walk to b');
    expect(graph.edges.single.instructionFor('b'), 'walk to a');
  });

  test('a corridor walked the way nobody recorded has no wording', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
    ]);

    expect(graph.edges.single.instructionFor('a'), 'walk to b');
    expect(graph.edges.single.instructionFor('b'), isNull);
  });

  test('a route placed before its connection still merges', () {
    // r2 shares nothing with r1 when first seen; r3 joins them. Order must not
    // decide whether the building comes out as one map or three.
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
      routeOf('r2', [leg('y', 'z')]),
      routeOf('r3', [leg('b', 'y')]),
    ]);

    expect(graph.reachableFrom('a'), hasLength(4));
  });

  group('a plan traced off a posted floor plan', () {
    TracedNode nodeOf(String ref, double x, double y, {String floor = 'f1'}) =>
        TracedNode(
          ref: ref,
          x: x,
          y: y,
          floorId: floor,
          kind: LandmarkKind.door,
          labelText: ref.toUpperCase(),
          displayName: 'Room $ref',
        );

    TracedPlan planOf(
      List<TracedNode> nodes,
      List<({String from, String to})> edges,
    ) =>
        TracedPlan(
          buildingId: 'b1',
          nodes: nodes,
          edges: [
            for (final e in edges) TracedEdge(fromRef: e.from, toRef: e.to),
          ],
        );

    test('keeps the coordinates that were tapped, without laying anything out',
        () {
      final graph = FloorGraph.fromPlan(
        planOf(
          [nodeOf('a', 0, 0), nodeOf('b', 3, 4)],
          [(from: 'a', to: 'b')],
        ),
      );

      expect(graph.nodeOf('a'), isNotNull);
      expect(graph.nodeOf('b')!.x, closeTo(3, 0.001));
      expect(graph.nodeOf('b')!.y, closeTo(4, 0.001));
    });

    test('an edge is as long as the gap between the two ends it was drawn '
        'between', () {
      final graph = FloorGraph.fromPlan(
        planOf(
          [nodeOf('a', 0, 0), nodeOf('b', 3, 4)],
          [(from: 'a', to: 'b')],
        ),
      );

      // 3-4-5: the length is geometry, never a separately stored number that
      // could disagree with where the ends sit.
      expect(graph.edges.single.distanceM, closeTo(5, 0.001));
    });

    test('a loop closes, which a chain of step counts cannot promise', () {
      final graph = FloorGraph.fromPlan(
        planOf(
          [
            nodeOf('a', 0, 0),
            nodeOf('b', 10, 0),
            nodeOf('c', 10, 10),
            nodeOf('d', 0, 10),
          ],
          [
            (from: 'a', to: 'b'),
            (from: 'b', to: 'c'),
            (from: 'c', to: 'd'),
            (from: 'd', to: 'a'),
          ],
        ),
      );

      expect(graph.nodeOf('a')!.x, closeTo(0, 0.001));
      expect(graph.nodeOf('a')!.y, closeTo(0, 0.001));
      expect(graph.edges, hasLength(4));
    });

    test('an edge naming a node the plan does not contain is dropped', () {
      final graph = FloorGraph.fromPlan(
        planOf(
          [nodeOf('a', 0, 0), nodeOf('b', 5, 0)],
          [(from: 'a', to: 'b'), (from: 'b', to: 'ghost')],
        ),
      );

      expect(graph.edges, hasLength(1));
      expect(graph.nodeOf('ghost'), isNull);
      expect(graph.neighboursOf('b'), hasLength(1));
    });

    test('a corridor drawn twice is one corridor', () {
      final graph = FloorGraph.fromPlan(
        planOf(
          [nodeOf('a', 0, 0), nodeOf('b', 5, 0)],
          [(from: 'a', to: 'b'), (from: 'b', to: 'a')],
        ),
      );

      expect(graph.edges, hasLength(1));
    });

    test('a node joined to itself makes no edge', () {
      final graph = FloorGraph.fromPlan(
        planOf([nodeOf('a', 0, 0)], [(from: 'a', to: 'a')]),
      );

      expect(graph.edges, isEmpty);
    });

    test('an untraced plan is an empty graph, not a crash', () {
      expect(FloorGraph.fromPlan(TracedPlan.empty).isEmpty, isTrue);
    });

    test('the whole traced floor is reachable from any node on it', () {
      final graph = FloorGraph.fromPlan(
        planOf(
          [
            nodeOf('entrance', 0, 0),
            nodeOf('junction', 0, 12),
            nodeOf('204', 8, 12),
            nodeOf('205', -8, 12),
          ],
          [
            (from: 'entrance', to: 'junction'),
            (from: 'junction', to: '204'),
            (from: 'junction', to: '205'),
          ],
        ),
      );

      expect(graph.reachableFrom('204'), hasLength(4));
    });

    test('a stairwell joins two traced floors into one graph', () {
      final graph = FloorGraph.fromPlan(
        planOf(
          [
            nodeOf('entrance', 0, 0),
            nodeOf('stairs-g', 0, 20),
            nodeOf('landing-2', 0, 20, floor: 'f2'),
            nodeOf('204', 12, 20, floor: 'f2'),
          ],
          [
            (from: 'entrance', to: 'stairs-g'),
            (from: 'stairs-g', to: 'landing-2'),
            (from: 'landing-2', to: '204'),
          ],
        ),
      );

      // The climb is an ordinary edge, so a route from the front door to a
      // second-floor room is one A* search, not two joined by special cases.
      expect(graph.reachableFrom('entrance'), contains('204'));
    });
  });
}
