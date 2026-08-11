import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/route_draft.dart';
import 'package:echo_locate/core/models/traced_plan.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RouteDraft draft() => const RouteDraft(
        buildingId: 'cabs-block',
        destinationRoomId: 'room-1',
        landmarks: [
          DraftLandmark(
            ref: 'L1',
            floorId: 'floor-g',
            kind: LandmarkKind.entrance,
            labelText: 'CABS BLOCK',
            displayName: 'Main entrance',
          ),
          DraftLandmark(
            ref: 'L2',
            floorId: 'floor-g',
            kind: LandmarkKind.door,
            labelText: 'ROOM 101',
            displayName: 'Room 101 door',
            roomId: 'room-1',
          ),
        ],
        steps: [
          DraftStep(
            seq: 1,
            fromRef: 'L1',
            toRef: 'L2',
            instruction: 'Turn right and follow the corridor',
            distanceM: 14,
            stepsRecorded: 20,
          ),
        ],
      );

  test('a saved capture puts its landmarks on the building map', () async {
    // The server's save_route upserts landmarks and hands back real ids; the
    // mock has to do the same or the offline demo draws a map of nameless
    // nodes that no route can be planned over.
    final repository = MockRouteRepository();

    await repository.saveRoute(draft());
    final landmarks = await repository.landmarksOf('cabs-block');

    expect(
      landmarks.map((l) => l.displayName),
      containsAll(['Main entrance', 'Room 101 door']),
    );
    expect(landmarks.firstWhere((l) => l.roomId == 'room-1').displayName,
        'Room 101 door');
  });

  test('saved legs reference landmark ids, not client-side refs', () async {
    final repository = MockRouteRepository();

    await repository.saveRoute(draft());
    final routes = await repository.routesOf('cabs-block');
    final landmarks = await repository.landmarksOf('cabs-block');

    final step = routes.single.steps.single;
    final ids = landmarks.map((l) => l.id).toSet();
    expect(ids, contains(step.fromLandmarkId));
    expect(ids, contains(step.toLandmarkId));
    expect(step.fromLandmarkId, isNot('L1'));
  });

  test('re-walking a route reuses the landmarks already recorded', () async {
    final repository = MockRouteRepository();

    await repository.saveRoute(draft());
    await repository.saveRoute(draft());
    final landmarks = await repository.landmarksOf('cabs-block');

    // Keyed on display name, exactly as the SQL upsert is.
    expect(landmarks, hasLength(2));
  });

  test('the seeded library routes still read back whole', () async {
    final repository = MockRouteRepository();

    final routes = await repository.routesOf('knust-library');

    // Two walks, sharing their first legs and diverging on floor 2. That
    // overlap is the point: it is what gives A* somewhere to leave one
    // contributor's route and join another's.
    expect(routes, hasLength(2));

    final readingHall = routes.firstWhere((r) => r.id == 'route-reading-hall');
    expect(readingHall.steps, hasLength(5));
    expect(readingHall.totalDistanceM, 53);
  });

  group('traced plans', () {
    TracedPlan plan({String building = 'cabs-block'}) => TracedPlan(
          buildingId: building,
          nodes: const [
            TracedNode(
              ref: 'n1',
              x: 0,
              y: 0,
              floorId: 'floor-g',
              kind: LandmarkKind.entrance,
              labelText: 'CABS BLOCK',
              displayName: 'Front door',
            ),
            TracedNode(
              ref: 'n2',
              x: 0,
              y: 24,
              floorId: 'floor-g',
              kind: LandmarkKind.door,
              labelText: '101',
              displayName: 'Room 101',
              roomId: 'room-1',
            ),
          ],
          edges: const [TracedEdge(fromRef: 'n1', toRef: 'n2')],
        );

    test('a building nobody has traced has no plan', () async {
      final repository = MockRouteRepository();

      expect(await repository.tracedPlanOf('cabs-block'), isNull);
    });

    test('saving swaps client-side refs for landmark ids', () async {
      final repository = MockRouteRepository();

      final saved = await repository.saveTracedPlan(plan());

      // The refs the tracing screen invented must not survive the save: the
      // graph's node ids have to be the ids OCR matching and landmarksOf use.
      expect(saved.nodes.map((n) => n.ref), isNot(contains('n1')));
      expect(saved.edges.single.fromRef, saved.nodes.first.ref);
      expect(saved.edges.single.toRef, saved.nodes.last.ref);
    });

    test('a traced node becomes a landmark the camera can match', () async {
      final repository = MockRouteRepository();

      await repository.saveTracedPlan(plan());
      final landmarks = await repository.landmarksOf('cabs-block');

      final room = landmarks.firstWhere((l) => l.displayName == 'Room 101');
      expect(room.labelText, '101');
      expect(room.roomId, 'room-1');
      expect(room.kind, LandmarkKind.door);
    });

    test('a saved plan reads back as the same graph', () async {
      final repository = MockRouteRepository();

      final saved = await repository.saveTracedPlan(plan());
      final reloaded = await repository.tracedPlanOf('cabs-block');

      expect(reloaded, isNotNull);
      expect(FloorGraph.fromPlan(reloaded!).nodes.keys,
          FloorGraph.fromPlan(saved).nodes.keys);
      expect(FloorGraph.fromPlan(reloaded).edges.single.distanceM,
          closeTo(24, 0.001));
    });

    test('re-tracing a floor reuses the landmarks already there', () async {
      final repository = MockRouteRepository();

      final first = await repository.saveTracedPlan(plan());
      final second = await repository.saveTracedPlan(plan());

      // Same building, same floor, same display names: one door, not two, or
      // A* gets a choice that does not exist and OCR two things to match.
      expect(second.nodes.map((n) => n.ref), first.nodes.map((n) => n.ref));
      final landmarks = await repository.landmarksOf('cabs-block');
      expect(
        landmarks.where((l) => l.displayName == 'Room 101'),
        hasLength(1),
      );
    });

    test('saving replaces the building\'s plan rather than appending to it',
        () async {
      final repository = MockRouteRepository();

      await repository.saveTracedPlan(plan());
      await repository.saveTracedPlan(
        TracedPlan(
          buildingId: 'cabs-block',
          nodes: plan().nodes.take(1).toList(),
          edges: const [],
        ),
      );

      final reloaded = await repository.tracedPlanOf('cabs-block');
      expect(reloaded!.nodes, hasLength(1));
      expect(reloaded.edges, isEmpty);
    });

    test('one building\'s plan is not another\'s', () async {
      final repository = MockRouteRepository();

      await repository.saveTracedPlan(plan());

      expect(await repository.tracedPlanOf('knust-library'), isNull);
    });
  });
}
