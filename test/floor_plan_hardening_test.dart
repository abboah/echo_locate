import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:echo_locate/services/mapping/plan_viewport.dart';
import 'package:echo_locate/services/mapping/route_layout.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';

import 'route_layout_test.dart' show landmarksOn, routeOf;

/// Phase 4 — what real captures do that the seed does not.
///
/// A contributor walking a building with one hand on a phone produces data the
/// hand-authored seed never will: legs of two metres and forty, a sign read
/// twice, a route abandoned halfway, a wing nothing connects to. None of it
/// should throw, and none of it should silently render as an empty screen.
void main() {
  group('degenerate routes', () {
    test('a single-leg route lays out and plans', () {
      final route = routeOf([('B', 12, 0)]);
      final planner = RoutePlanner.from(
        [route],
        landmarksOn('g', ['A', 'B']).values.toList(),
      );

      expect(planner.graph.nodes, hasLength(2));
      expect(
        planner
            .planBetweenLandmarks(fromLandmarkId: 'A', toLandmarkId: 'B')!
            .steps,
        hasLength(1),
      );
    });

    test('a leg that goes nowhere does not become an edge', () {
      // Tapping "confirm" twice on the same sign.
      const route = WalkRoute(
        id: 'r',
        buildingId: 'b',
        startLandmarkId: 'A',
        destinationRoomId: 'room',
        steps: [
          RouteStep(
            seq: 1,
            fromLandmarkId: 'A',
            toLandmarkId: 'A',
            instruction: 'confirmed twice',
            distanceM: 0,
          ),
        ],
      );

      final graph = merge([route], landmarksOn('g', ['A']).values.toList());
      expect(graph.edges, isEmpty);
      expect(graph.nodes, hasLength(1));
    });

    test('zero-distance legs do not collapse the plan', () {
      final route = routeOf([('B', 0, 0), ('C', 10, 90)]);
      final planner = RoutePlanner.from(
        [route],
        landmarksOn('g', ['A', 'B', 'C']).values.toList(),
      );

      expect(planner.graph.nodes, hasLength(3));
      final planned =
          planner.planBetweenLandmarks(fromLandmarkId: 'A', toLandmarkId: 'C')!;
      expect(planned.totalDistanceM, closeTo(10, 0.01));
      expect(planned.steps.every((s) => s.distanceM.isFinite), isTrue);
    });

    test('a route revisiting a landmark reports its misclosure', () {
      // A loop round a floor, walked with slightly wrong corners.
      final nodes = layout(
        routeOf([('B', 12, 0), ('C', 12, 80), ('D', 12, 80), ('A', 12, 80)]),
        landmarksOn('g', ['A', 'B', 'C', 'D']),
      );

      final gap = misclosureOf(nodes);
      expect(gap, isNotNull);
      // Reported, not hidden: this number belongs in the evaluation chapter.
      expect(gap!, greaterThan(0));
      expect(gap.isFinite, isTrue);
    });

    test('a route whose legs arrive with duplicate seq still lays out', () {
      const route = WalkRoute(
        id: 'r',
        buildingId: 'b',
        startLandmarkId: 'A',
        destinationRoomId: 'room',
        steps: [
          RouteStep(
            seq: 1,
            fromLandmarkId: 'A',
            toLandmarkId: 'B',
            instruction: 'one',
            distanceM: 10,
          ),
          RouteStep(
            seq: 1,
            fromLandmarkId: 'B',
            toLandmarkId: 'C',
            instruction: 'also one',
            distanceM: 10,
          ),
        ],
      );

      final nodes = layout(route, landmarksOn('g', ['A', 'B', 'C']));
      expect(nodes, hasLength(3));
      expect(nodes.every((n) => n.x.isFinite && n.y.isFinite), isTrue);
    });
  });

  group('scale extremes', () {
    test('a two-metre leg and a forty-metre leg share one plan', () {
      final route = routeOf([('B', 2, 0), ('C', 40, 90), ('D', 2, 90)]);
      final nodes = layout(route, landmarksOn('g', ['A', 'B', 'C', 'D']));

      final viewport = PlanViewport.fit(nodes, width: 360, height: 640);

      for (final node in nodes) {
        expect(viewport.toCanvasX(node.x), inInclusiveRange(0, 360));
        expect(viewport.toCanvasY(node.y), inInclusiveRange(0, 640));
      }
      // The short legs must not be squashed to nothing by the long one.
      final a = viewport.toCanvasY(nodes[0].y);
      final b = viewport.toCanvasY(nodes[1].y);
      expect((a - b).abs(), greaterThan(1));
    });

    test('a building-sized plan still fits', () {
      final route = routeOf([('B', 200, 0), ('C', 150, 90)]);
      final nodes = layout(route, landmarksOn('g', ['A', 'B', 'C']));
      final viewport = PlanViewport.fit(nodes, width: 360, height: 640);

      for (final node in nodes) {
        expect(viewport.toCanvasX(node.x), inInclusiveRange(0, 360));
        expect(viewport.toCanvasY(node.y), inInclusiveRange(0, 640));
      }
    });
  });

  group('incomplete data', () {
    test('a destination landmark with no room id cannot be routed to', () {
      final planner = RoutePlanner.from(
        [routeOf([('B', 10, 0)])],
        landmarksOn('g', ['A', 'B']).values.toList(),
      );

      // Says so rather than routing to the nearest door and hoping.
      expect(planner.landmarkForRoom('some-room'), isNull);
      expect(
        planner.planToRoom(fromLandmarkId: 'A', roomId: 'some-room'),
        isNull,
      );
    });

    test('a landmark recorded but never walked to is unreachable, not fatal',
        () {
      final landmarks = [
        ...landmarksOn('g', ['A', 'B']).values,
        // Captured, then the contributor gave up before recording a leg to it.
        const Landmark(
          id: 'orphan',
          buildingId: 'b',
          floorId: 'g',
          kind: LandmarkKind.door,
          labelText: '204',
          displayName: 'Room 204 door',
          roomId: 'room-204',
        ),
      ];
      final planner = RoutePlanner.from([routeOf([('B', 10, 0)])], landmarks);

      expect(planner.landmarkForRoom('room-204'), 'orphan');
      // Resolvable but not connected — the screen says "no recorded walk
      // reaches that room yet", which is true and actionable.
      expect(planner.planToRoom(fromLandmarkId: 'A', roomId: 'room-204'),
          isNull);
    });

    test('two disconnected wings each keep their own geometry', () {
      final west = routeOf([('B', 10, 0), ('C', 10, 90)], id: 'west');
      final east = routeOf([('Z', 15, 0)], id: 'east', start: 'Y');
      final landmarks =
          landmarksOn('g', ['A', 'B', 'C', 'Y', 'Z']).values.toList();

      final result = mergeWithDiagnostics([west, east], landmarks);

      expect(result.unanchoredRouteIds, ['east']);
      expect(result.graph.nodes, hasLength(5));
      // Internally consistent even though it floats: 15 m apart is still 15 m.
      final y = result.graph.nodes['Y']!;
      final z = result.graph.nodes['Z']!;
      expect(y.distanceTo(z), closeTo(15, 0.01));
    });

    test('a landmark set missing entries does not stop the plan', () {
      // A partial fetch: legs reference landmarks the client does not hold.
      final graph = merge(
        [routeOf([('B', 10, 0), ('C', 10, 90)])],
        landmarksOn('g', ['A']).values.toList(),
      );

      expect(graph.nodes, hasLength(3));
      expect(graph.nodes.values.every((n) => n.x.isFinite), isTrue);
    });
  });

  group('contradictory recordings', () {
    test('a badly disagreeing landmark is averaged and the gap reported', () {
      // Two contributors, one counting steps far longer than the other.
      final careful = routeOf([('B', 10, 0), ('C', 10, 0)], id: 'careful');
      final hurried = routeOf([('B', 10, 0), ('C', 25, 0)], id: 'hurried');

      final result = mergeWithDiagnostics(
        [careful, hurried],
        landmarksOn('g', ['A', 'B', 'C']).values.toList(),
      );

      expect(result.spreadM['C'], closeTo(15, 0.01));
      expect(result.worstSpreadM, closeTo(15, 0.01));
      // Averaged, not resolved. Nothing here can say who walked more carefully.
      expect(result.graph.nodes['C']!.y, closeTo(27.5, 0.01));
    });

    test('the same leg recorded in both directions is one corridor', () {
      final there = routeOf([('B', 10, 0)], id: 'there');
      final back = routeOf([('A', 11, 0)], id: 'back', start: 'B');

      final graph =
          merge([there, back], landmarksOn('g', ['A', 'B']).values.toList());

      expect(graph.edges, hasLength(1));
      expect(graph.edges.single.distanceM, closeTo(10.5, 0.01));
    });

    test('planning is deterministic across equally good recordings', () {
      final first = routeOf([('B', 10, 0), ('C', 10, 0)], id: 'first');
      final second = routeOf([('B', 10, 0), ('C', 10, 0)], id: 'second');
      final landmarks = landmarksOn('g', ['A', 'B', 'C']).values.toList();

      final a = RoutePlanner.from([first, second], landmarks)
          .planBetweenLandmarks(fromLandmarkId: 'A', toLandmarkId: 'C');
      final b = RoutePlanner.from([second, first], landmarks)
          .planBetweenLandmarks(fromLandmarkId: 'A', toLandmarkId: 'C');

      // Row order from PostgREST is arbitrary; the route the user hears must
      // not be.
      expect(a!.steps.map((s) => s.instruction),
          b!.steps.map((s) => s.instruction));
    });
  });
}
