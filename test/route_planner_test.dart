import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';

import 'route_layout_test.dart' show landmarksOn, routeOf;

Future<RoutePlanner> libraryPlanner() async {
  final repository = MockRouteRepository();
  return RoutePlanner.from(
    await repository.routesOf('knust-library'),
    await repository.landmarksOf('knust-library'),
  );
}

void main() {
  group('findPath', () {
    test('finds the shortest way round a graph with two branches', () {
      // A -> B -> C the long way, A -> D -> C the short way.
      final long = routeOf([('B', 20, 0), ('C', 20, 90)], id: 'long');
      final short = routeOf([('D', 5, 90), ('C', 5, -90)], id: 'short');
      final planner = RoutePlanner.from(
        [long, short],
        landmarksOn('g', ['A', 'B', 'C', 'D']).values.toList(),
      );

      expect(planner.findPath('A', 'C'), ['A', 'D', 'C']);
    });

    test('returns a single node when start and destination are the same', () {
      final planner = RoutePlanner.from(
        [routeOf([('B', 10, 0)])],
        landmarksOn('g', ['A', 'B']).values.toList(),
      );
      expect(planner.findPath('A', 'A'), ['A']);
    });

    test('returns nothing for landmarks the graph does not hold', () {
      final planner = RoutePlanner.from(
        [routeOf([('B', 10, 0)])],
        landmarksOn('g', ['A', 'B']).values.toList(),
      );
      expect(planner.findPath('A', 'nowhere'), isEmpty);
      expect(planner.findPath('nowhere', 'B'), isEmpty);
    });

    test('returns nothing between disconnected wings', () {
      final west = routeOf([('B', 10, 0)], id: 'west');
      final east = routeOf([('Z', 10, 0)], id: 'east', start: 'Y');
      final planner = RoutePlanner.from(
        [west, east],
        landmarksOn('g', ['A', 'B', 'Y', 'Z']).values.toList(),
      );

      // Recorded, but no walk connects them — better than inventing a corridor.
      expect(planner.findPath('A', 'Z'), isEmpty);
    });

    test('walks a leg backwards when that is the way round', () {
      final planner = RoutePlanner.from(
        [routeOf([('B', 10, 0), ('C', 10, 0)])],
        landmarksOn('g', ['A', 'B', 'C']).values.toList(),
      );
      expect(planner.findPath('C', 'A'), ['C', 'B', 'A']);
    });
  });

  group('landmarkForRoom', () {
    test('resolves a room to the landmark at its door', () async {
      final planner = await libraryPlanner();
      expect(planner.landmarkForRoom('reading-hall'), 'lm-reading-hall');
      expect(planner.landmarkForRoom('study-2b'), 'lm-study-2b');
    });

    test('returns null for a room nobody has recorded a landmark for',
        () async {
      final planner = await libraryPlanner();
      // Rooms without a landmark cannot be navigated to. Saying so is the
      // point — silently routing to the nearest door would be worse.
      expect(planner.landmarkForRoom('help-desk'), isNull);
    });
  });

  group('planBetweenRooms — the demo moment', () {
    test('returns a path nobody ever walked', () async {
      final planner = await libraryPlanner();

      final route = planner.planBetweenRooms(
        fromRoomId: 'reading-hall',
        toRoomId: 'study-2b',
      );

      expect(route, isNotNull);
      // Both recordings run entrance -> ... -> a floor 2 door. Nobody walked
      // between the two doors; this is spliced from the tail of one and the
      // reversed tail of the other.
      expect(route!.landmarkIds, [
        'lm-reading-hall',
        'lm-corridor-2',
        'lm-study-2b',
      ]);
      expect(route.steps, hasLength(2));
      expect(route.totalDistanceM, closeTo(13, 0.01));
    });

    test('is marked planned, not recorded', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenRooms(
        fromRoomId: 'reading-hall',
        toRoomId: 'study-2b',
      )!;

      expect(route.isPlanned, isTrue);
      expect(route.verifiedCount, 0);
      // Computed distance must never masquerade as somebody's step count.
      expect(route.steps.every((s) => s.stepsRecorded == null), isTrue);
    });

    test('turns are recomputed for the approach actually taken', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenRooms(
        fromRoomId: 'reading-hall',
        toRoomId: 'study-2b',
      )!;

      // Leaving the Reading Hall there is no previous leg to turn from.
      expect(route.steps.first.turnDeg, 0);

      // At the directory board the walker is heading back down the corridor,
      // so Study Room 2B is on the LEFT — the opposite of the recorded
      // "turn right", which was written for somebody arriving from the stairs.
      expect(route.steps.last.turnDeg, -90);
    });

    test('a leg walked backwards is reworded, not replayed', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenRooms(
        fromRoomId: 'reading-hall',
        toRoomId: 'study-2b',
      )!;

      final backwards = route.steps.first;
      // The recording said "Straight on; the Reading Hall is the second door
      // on your right". Spoken to somebody walking the other way, out of the
      // Reading Hall, that is simply false.
      expect(backwards.instruction, isNot(contains('Reading Hall is')));
      expect(backwards.instruction, contains('directory board'));

      final turned = route.steps.last;
      expect(turned.instruction, contains('Turn left'));
      expect(turned.instruction, contains('Study Room 2B'));
    });

    test('distances come from what somebody measured', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenRooms(
        fromRoomId: 'reading-hall',
        toRoomId: 'study-2b',
      )!;

      // 6 m from the Reading Hall to the board, 7 m from the board to 2B —
      // both walked, neither derived from the schematic.
      expect(route.steps.first.distanceM, closeTo(6, 0.01));
      expect(route.steps.last.distanceM, closeTo(7, 0.01));
    });

    test('returns null when either room has no landmark', () async {
      final planner = await libraryPlanner();
      expect(
        planner.planBetweenRooms(
          fromRoomId: 'reading-hall',
          toRoomId: 'help-desk',
        ),
        isNull,
      );
    });
  });

  group('planBetweenLandmarks', () {
    test('replays the recorded wording when the approach matches', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-entrance',
        toLandmarkId: 'lm-reading-hall',
      )!;

      // Walked exactly as recorded, so the contributor's own sentences stand —
      // a human description of a corridor beats anything generated.
      expect(route.steps.map((s) => s.instruction), [
        'Straight ahead, past the entrance desk',
        'Turn right; the stairwell is at the end of the corridor',
        'Take the stairs up two flights to floor 2',
        'Turn left along the main corridor to the directory board',
        'Straight on; the Reading Hall is the second door on your right',
      ]);
      expect(route.steps.map((s) => s.turnDeg), [0, 90, 0, -90, 0]);
    });

    test('hands back the recording when one covers the whole path', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-entrance',
        toLandmarkId: 'lm-reading-hall',
      )!;

      // Somebody walked exactly this. Reconstructing it would throw away their
      // step counts and their verification, and the UI would then call a real
      // walk an "estimated route".
      expect(route.id, 'route-reading-hall');
      expect(route.isPlanned, isFalse);
      expect(route.steps.first.stepsRecorded, isNotNull);
    });

    test('a partial path is still synthesised', () async {
      final planner = await libraryPlanner();
      // A prefix of a recording is not itself a recording.
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-entrance',
        toLandmarkId: 'lm-stairs-g',
      )!;

      expect(route.isPlanned, isTrue);
      expect(route.steps, hasLength(2));
    });

    test('the full reverse journey is described in reverse', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-reading-hall',
        toLandmarkId: 'lm-entrance',
      )!;

      expect(route.steps, hasLength(5));
      expect(route.startLandmarkId, 'lm-reading-hall');
      // Nothing recorded survives verbatim: every leg is walked the wrong way.
      for (final step in route.steps) {
        expect(step.stepsRecorded, isNull);
      }
      // The stairs are still stairs going down.
      expect(
        route.steps.any((s) => s.instruction.contains('Take the stairs')),
        isTrue,
      );
    });

    test('a floor change is described, not turned into', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-reading-hall',
        toLandmarkId: 'lm-entrance',
      )!;

      final stairs = route.steps.firstWhere(
        (s) => s.toLandmarkId == 'lm-stairs-g',
      );
      // Two nodes at the same point give no direction to measure, so no turn
      // is invented for them.
      expect(stairs.turnDeg, 0);
      expect(stairs.instruction, contains('stairs'));
    });

    test('legs are sequenced from 1 and chain end to end', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-reading-hall',
        toLandmarkId: 'lm-entrance',
      )!;

      expect(route.steps.map((s) => s.seq), [1, 2, 3, 4, 5]);
      for (var i = 1; i < route.steps.length; i++) {
        expect(route.steps[i].fromLandmarkId, route.steps[i - 1].toLandmarkId);
      }
      expect(route.steps.first.fromLandmarkId, route.startLandmarkId);
    });

    test('total distance is the sum of its legs', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-entrance',
        toLandmarkId: 'lm-study-2b',
      )!;

      final summed = route.steps.fold<double>(0, (sum, s) => sum + s.distanceM);
      expect(route.totalDistanceM, closeTo(summed, 0.001));
      expect(route.totalDistanceM, closeTo(54, 0.01));
    });

    test('returns null when no path exists', () async {
      final planner = await libraryPlanner();
      expect(
        planner.planBetweenLandmarks(
          fromLandmarkId: 'lm-entrance',
          toLandmarkId: 'nowhere',
        ),
        isNull,
      );
    });

    test('carries the destination room id when the door has one', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-entrance',
        toLandmarkId: 'lm-study-2b',
      )!;
      expect(route.destinationRoomId, 'study-2b');

      // A junction is not a room, and claiming otherwise would break guidance.
      final toJunction = planner.planBetweenLandmarks(
        fromLandmarkId: 'lm-entrance',
        toLandmarkId: 'lm-desk',
      )!;
      expect(toJunction.destinationRoomId, isEmpty);
    });
  });

  group('synthesised wording', () {
    test('names every turn the capture UI can record', () {
      // A star of legs out of a hub, each at a different angle, so every
      // phrase the walker might hear is exercised.
      final routes = [
        routeOf([('H', 10, 0), ('N', 10, 0)], id: 'n'),
        routeOf([('H', 10, 0), ('E', 10, 90)], id: 'e'),
        routeOf([('H', 10, 0), ('W', 10, -90)], id: 'w'),
        routeOf([('H', 10, 0), ('SE', 10, 135)], id: 'se'),
        routeOf([('H', 10, 0), ('SW', 10, -135)], id: 'sw'),
      ];
      final planner = RoutePlanner.from(
        routes,
        landmarksOn('g', ['A', 'H', 'N', 'E', 'W', 'SE', 'SW']).values.toList(),
      );

      String legInto(String destination) => planner
          .planBetweenLandmarks(fromLandmarkId: 'N', toLandmarkId: destination)!
          .steps
          .last
          .instruction;

      // Arriving at the hub southbound from N, so the compass flips.
      expect(legInto('E'), contains('Turn left'));
      expect(legInto('W'), contains('Turn right'));
      expect(legInto('SE'), contains('Bear left'));
      expect(legInto('SW'), contains('Bear right'));
    });

    test('quotes distance in whole metres', () async {
      final planner = await libraryPlanner();
      final route = planner.planBetweenRooms(
        fromRoomId: 'study-2b',
        toRoomId: 'reading-hall',
      )!;

      expect(route.steps.last.instruction, contains('6 metres'));
      expect(route.steps.last.instruction, isNot(contains('.')));
    });

    test('falls back to a neutral phrase for an unnamed landmark', () {
      final planner = RoutePlanner.from(
        [routeOf([('B', 10, 0), ('C', 10, 90)])],
        // 'C' deliberately absent from the landmark set.
        landmarksOn('g', ['A', 'B']).values.toList(),
      );

      // Starting mid-route, so the recorded wording for B->C does not apply
      // and a sentence has to be built for a landmark with no name.
      final route = planner.planBetweenLandmarks(
        fromLandmarkId: 'B',
        toLandmarkId: 'C',
      )!;
      expect(route.steps.single.instruction, contains('the next landmark'));
    });
  });

  group('competing recordings', () {
    test('the most-verified wording wins', () {
      const careless = WalkRoute(
        id: 'careless',
        buildingId: 'b',
        startLandmarkId: 'A',
        destinationRoomId: 'room',
        steps: [
          RouteStep(
            seq: 1,
            fromLandmarkId: 'A',
            toLandmarkId: 'B',
            instruction: 'go that way',
            distanceM: 10,
          ),
        ],
      );
      final trusted = careless.copyWith(
        id: 'trusted',
        verifiedCount: 7,
        steps: [
          careless.steps.first.copyWith(
            instruction: 'Straight past the noticeboard to the lifts',
          ),
        ],
      );

      final planner = RoutePlanner.from(
        [careless, trusted],
        landmarksOn('g', ['A', 'B']).values.toList(),
      );

      expect(
        planner
            .planBetweenLandmarks(fromLandmarkId: 'A', toLandmarkId: 'B')!
            .steps
            .single
            .instruction,
        'Straight past the noticeboard to the lifts',
      );
    });
  });
}
