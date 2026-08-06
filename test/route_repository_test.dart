import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/route_draft.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/data/repository_mixin.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/features/routing/supabase_route_repository.dart';

/// Nothing listens on port 9 — every request fails at the socket level,
/// exactly like a phone in a corridor with no signal.
const _deadEndpoint = 'http://127.0.0.1:9';

void main() {
  group('MockRouteRepository', () {
    late MockRouteRepository repository;

    setUp(() => repository = MockRouteRepository());

    Future<WalkRoute> libraryRoute() async =>
        (await repository.routesOf('knust-library'))
            .firstWhere((r) => r.destinationRoomId == 'reading-hall');

    test('the seeded library route has five legs in seq order', () async {
      final route = await libraryRoute();
      expect(route.steps, hasLength(5));
      expect(route.steps.map((s) => s.seq), [1, 2, 3, 4, 5]);
    });

    test('two overlapping routes are seeded, so A* has something to do',
        () async {
      final routes = await repository.routesOf('knust-library');
      expect(
        routes.map((r) => r.destinationRoomId),
        containsAll(['reading-hall', 'study-2b']),
      );

      // They must share landmarks or the graph is two disconnected wings and
      // no route can be planned between them.
      final shared = routes.first.landmarkIds.toSet()
        ..retainAll(routes.last.landmarkIds.toSet());
      expect(shared, hasLength(greaterThanOrEqualTo(2)));
    });

    test('leg distances sum to the route total', () async {
      for (final route in await repository.routesOf('knust-library')) {
        final summed =
            route.steps.fold<double>(0, (sum, s) => sum + s.distanceM);
        expect(summed, closeTo(route.totalDistanceM, 0.001));
      }
    });

    test('legs form an unbroken chain from the start landmark', () async {
      for (final route in await repository.routesOf('knust-library')) {
        expect(route.steps.first.fromLandmarkId, route.startLandmarkId);
        for (var i = 1; i < route.steps.length; i++) {
          expect(
            route.steps[i].fromLandmarkId,
            route.steps[i - 1].toLandmarkId,
          );
        }
      }
    });

    test('every landmark a leg references exists', () async {
      final landmarks = await repository.landmarksOf('knust-library');
      final ids = landmarks.map((l) => l.id).toSet();

      for (final route in await repository.routesOf('knust-library')) {
        for (final step in route.steps) {
          expect(ids, contains(step.fromLandmarkId));
          expect(ids, contains(step.toLandmarkId));
        }
      }
    });

    test('the routes cross floors, so layout must handle stairs', () async {
      final landmarks = {
        for (final l in await repository.landmarksOf('knust-library')) l.id: l,
      };
      final route = await libraryRoute();

      final floors = route.landmarkIds.map((id) => landmarks[id]!.floorId);
      expect(floors.toSet(), hasLength(greaterThan(1)));
      expect(
        landmarks.values.any((l) => l.kind.breaksStepCounting),
        isTrue,
        reason: 'a stairs or lift landmark is what makes the seed useful',
      );
    });

    test('each destination landmark carries its room id', () async {
      final landmarks = await repository.landmarksOf('knust-library');

      for (final route in await repository.routesOf('knust-library')) {
        final destination = landmarks.firstWhere(
          (l) => l.id == route.steps.last.toLandmarkId,
        );
        // Phase 2 resolves a room to its landmark through exactly this link.
        expect(destination.roomId, route.destinationRoomId);
      }
    });

    test('landmarksOf filters by building', () async {
      expect(await repository.landmarksOf('does-not-exist'), isEmpty);
      expect(await repository.landmarksOf('knust-library'), isNotEmpty);
    });

    test('routeTo finds the seeded destination and nothing else', () async {
      expect(
        (await repository.routeTo('knust-library', 'reading-hall'))?.id,
        'route-reading-hall',
      );
      expect(await repository.routeTo('knust-library', 'no-such-room'), isNull);
    });

    test('saveRoute rejects a draft with no legs', () {
      const draft = RouteDraft(
        buildingId: 'knust-library',
        destinationRoomId: 'reading-hall',
        landmarks: [],
        steps: [],
      );
      expect(
        () => repository.saveRoute(draft),
        throwsA(
          isA<OperationFailure>().having(
            (f) => f.message,
            'message',
            emptyDraftMessage,
          ),
        ),
      );
    });

    test('a saved route is returned by later reads', () async {
      const draft = RouteDraft(
        buildingId: 'knust-library',
        destinationRoomId: 'study-room-2b',
        landmarks: [
          DraftLandmark(
            ref: 'L1',
            floorId: 'floor-2',
            kind: LandmarkKind.stairs,
            labelText: '2',
            displayName: 'Floor 2 landing',
          ),
          DraftLandmark(
            ref: 'L2',
            floorId: 'floor-2',
            kind: LandmarkKind.door,
            labelText: '2B',
            displayName: 'Study Room 2B door',
            roomId: 'study-room-2b',
          ),
        ],
        steps: [
          DraftStep(
            seq: 1,
            fromRef: 'L1',
            toRef: 'L2',
            instruction: 'Turn right; second door on the left',
            distanceM: 11,
            turnDeg: 90,
            stepsRecorded: 15,
          ),
        ],
      );

      final id = await repository.saveRoute(draft);
      final saved = await repository.routeTo('knust-library', 'study-room-2b');

      expect(saved, isNotNull);
      expect(saved!.id, id);
      expect(saved.totalDistanceM, 11);
      expect(saved.steps.single.turnDeg, 90);
    });
  });

  group('bestRouteTo', () {
    WalkRoute route(String id, {required int verified}) => WalkRoute(
          id: id,
          buildingId: 'knust-library',
          startLandmarkId: 'lm-entrance',
          destinationRoomId: 'reading-hall',
          verifiedCount: verified,
          steps: const [],
        );

    test('picks the most-verified recording', () {
      final best = bestRouteTo(
        [route('a', verified: 1), route('c', verified: 9), route('b', verified: 4)],
        'reading-hall',
      );
      expect(best?.id, 'c');
    });

    test('keeps the earlier route when counts tie', () {
      // Row order is not guaranteed across fetches; the answer must not
      // flip-flop between two equally-verified recordings.
      final best = bestRouteTo(
        [route('a', verified: 3), route('b', verified: 3)],
        'reading-hall',
      );
      expect(best?.id, 'a');
    });

    test('ignores other destinations and returns null when none match', () {
      expect(bestRouteTo([route('a', verified: 1)], 'other-room'), isNull);
      expect(bestRouteTo([], 'reading-hall'), isNull);
    });
  });

  group('SupabaseRouteRepository offline fallback', () {
    late Directory tempDir;
    late SupabaseClient client;
    late SupabaseRouteRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('echo_locate_routes');
      Hive.init(tempDir.path);
      await Hive.openBox(repoCacheBoxName);
      client = SupabaseClient(_deadEndpoint, 'test-key');
      repository = SupabaseRouteRepository(client);
    });

    tearDown(() async {
      await client.dispose();
      await Hive.deleteFromDisk();
      await tempDir.delete(recursive: true);
    });

    test('routesOf returns the cached copy when the network is down', () async {
      const cached = WalkRoute(
        id: 'route-reading-hall',
        buildingId: 'knust-library',
        startLandmarkId: 'lm-entrance',
        destinationRoomId: 'reading-hall',
        totalDistanceM: 53,
        steps: [
          RouteStep(
            seq: 1,
            fromLandmarkId: 'lm-entrance',
            toLandmarkId: 'lm-desk',
            instruction: 'Straight ahead, past the entrance desk',
            distanceM: 12,
          ),
        ],
      );
      await Hive.box(repoCacheBoxName)
          .put('routes:knust-library', [cached.toJson()]);

      final routes = await repository.routesOf('knust-library');

      expect(routes, hasLength(1));
      expect(routes.single.id, 'route-reading-hall');
      expect(routes.single.steps.single.distanceM, 12);
    });

    test('landmarksOf returns the cached copy when the network is down',
        () async {
      const cached = Landmark(
        id: 'lm-entrance',
        buildingId: 'knust-library',
        floorId: 'floor-g',
        kind: LandmarkKind.entrance,
        labelText: 'KNUST LIBRARY',
        displayName: 'Main entrance',
      );
      await Hive.box(repoCacheBoxName)
          .put('landmarks:knust-library', [cached.toJson()]);

      final landmarks = await repository.landmarksOf('knust-library');

      expect(landmarks.single.displayName, 'Main entrance');
      expect(landmarks.single.kind, LandmarkKind.entrance);
    });

    test('routeTo is served from the same cache as routesOf', () async {
      const cached = WalkRoute(
        id: 'route-reading-hall',
        buildingId: 'knust-library',
        startLandmarkId: 'lm-entrance',
        destinationRoomId: 'reading-hall',
        steps: [],
      );
      await Hive.box(repoCacheBoxName)
          .put('routes:knust-library', [cached.toJson()]);

      final route = await repository.routeTo('knust-library', 'reading-hall');
      expect(route?.id, 'route-reading-hall');
    });

    test('an uncached building surfaces the failure rather than empty data',
        () async {
      // Returning [] here would render as "this building has no routes",
      // which is a different and much worse claim than "you are offline".
      expect(
        () => repository.routesOf('never-opened'),
        throwsA(isNotNull),
      );
    });

    test('saveRoute rejects an empty draft before touching the network', () {
      const draft = RouteDraft(
        buildingId: 'knust-library',
        destinationRoomId: 'reading-hall',
        landmarks: [],
        steps: [],
      );
      expect(
        () => repository.saveRoute(draft),
        throwsA(
          isA<OperationFailure>().having(
            (f) => f.message,
            'message',
            emptyDraftMessage,
          ),
        ),
      );
    });
  });
}
