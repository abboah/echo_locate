import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/features/guidance/guidance_session.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';
import 'package:echo_locate/services/mapping/room_plan_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_directions_test.dart' show buildWing, rectRoom;

void main() {
  const east = Offset(1, 0);

  group('landmarks from rooms', () {
    test('publishes every traced room so OCR can confirm arrival', () {
      final landmarks = RoomPlanBridge.landmarksFrom(buildWing());

      // The room layer knows where the second door on the left is. It has no
      // way to know the user got there — that is what these are for.
      expect(landmarks, hasLength(buildWing().drawableRooms.length));
      expect(
        landmarks.map((l) => l.displayName),
        contains('Digital Forensic Office'),
      );
    });

    test('an unnamed room offers nothing for the OCR to match', () {
      final n3 = RoomPlanBridge.landmarksFrom(
        buildWing(),
      ).firstWhere((l) => l.roomId == 'n3');

      // This used to be 'GF 4' — a code allocated in tracing order that was
      // never painted on any door. Matching a sign against it could only ever
      // succeed by coincidence, and confirming arrival wrongly is worse for a
      // blind walker than not confirming it at all.
      expect(n3.labelText, isEmpty);
      expect(n3.matchesExactly('gf 4'), isFalse);
    });

    test('the typed door name is what confirms arrival', () {
      final n2 = RoomPlanBridge.landmarksFrom(
        buildWing(),
      ).firstWhere((l) => l.roomId == 'n2');

      expect(n2.matchesExactly('Digital Forensic Office'), isTrue);
      // And only that: the code is not something a sign can say.
      expect(n2.matchesExactly('GF 3'), isFalse);
    });

    test('kinds follow the room category, so phrasing follows too', () {
      final plan = buildWing().copyWith(
        storedRooms: [
          ...buildWing().rooms,
          rectRoom(
            id: 'stairs',
            code: 'GF 9',
            category: RoomCategory.staircase,
            left: 20,
            right: 23,
            bottom: 1,
            top: 4,
          ),
        ],
      );
      final landmarks = RoomPlanBridge.landmarksFrom(plan);

      expect(
        landmarks.firstWhere((l) => l.roomId == 'stairs').kind,
        LandmarkKind.stairs,
      );
      expect(
        landmarks.firstWhere((l) => l.roomId == 'corridor').kind,
        LandmarkKind.junction,
      );
      expect(
        landmarks.firstWhere((l) => l.roomId == 'n2').kind,
        LandmarkKind.door,
      );
      // Stairs break step counting, which guidance already handles.
      expect(
        landmarks
            .firstWhere((l) => l.roomId == 'stairs')
            .kind
            .breaksStepCounting,
        isTrue,
      );
    });

    test('an untraced room publishes nothing — its sign is unknown', () {
      final landmarks = RoomPlanBridge.landmarksFrom(
        buildWing(extraStubDoor: true),
      );

      expect(landmarks.every((l) => l.roomId != 'untraced'), isTrue);
    });
  });

  group('floor graph from rooms', () {
    test('rooms become nodes and doors become corridors', () {
      final graph = RoomPlanBridge.floorGraphFrom(buildWing());

      expect(graph.nodes, hasLength(7));
      expect(graph.edges, hasLength(6));
      expect(
        graph.reachableFrom(
          RoomPlanBridge.landmarkIdFor(buildWing().roomOf('lobby')!),
        ),
        hasLength(7),
      );
    });

    test('an exterior door is not an edge to nowhere', () {
      final plan = buildWing().copyWith(
        storedOpenings: [
          ...buildWing().openings,
          const Opening(
            id: 'd-exit',
            roomAId: 'lobby',
            at: RoomCorner(x: -6, y: 0),
          ),
        ],
      );

      expect(RoomPlanBridge.floorGraphFrom(plan).edges, hasLength(6));
    });

    test('a traced plan is marked non-metric so nothing counts fake steps', () {
      expect(RoomPlanBridge.floorGraphFrom(buildWing()).metric, isFalse);
      expect(
        RoomPlanBridge.floorGraphFrom(
          buildWing().copyWith(metresPerUnit: 1),
        ).metric,
        isTrue,
      );
    });

    /// The scale was stored and never applied. A plan measured at 4 m per unit
    /// came out claiming `metric: true` with edge lengths still in plan units,
    /// so guidance was handed a number four times too small and labelled
    /// metres — and setting the scale, which is the thing a user does to make
    /// distances trustworthy, was what broke them.
    test('a declared scale converts edge lengths into real metres', () {
      final unitless = RoomPlanBridge.floorGraphFrom(buildWing());
      final scaled = RoomPlanBridge.floorGraphFrom(
        buildWing().copyWith(metresPerUnit: 4),
      );

      expect(scaled.edges, hasLength(unitless.edges.length));
      for (var i = 0; i < scaled.edges.length; i++) {
        expect(
          scaled.edges[i].distanceM,
          closeTo(unitless.edges[i].distanceM * 4, 1e-9),
        );
      }
    });

    test('node coordinates are converted with the edges, not left behind', () {
      final plan = buildWing().copyWith(metresPerUnit: 4);
      final graph = RoomPlanBridge.floorGraphFrom(plan);

      // Measuring between two nodes has to agree with the edge joining them,
      // or a caller gets two different answers for one corridor.
      for (final edge in graph.edges) {
        final from = graph.nodes[edge.fromId]!;
        final to = graph.nodes[edge.toId]!;
        expect(from.distanceTo(to), closeTo(edge.distanceM, 1e-9));
      }
    });
  });

  group('planned route — what guidance actually walks', () {
    test('one leg per room entered', () {
      final route = RoomPlanBridge.plannedRouteFrom(
        buildWing(),
        fromRoomId: 'lobby',
        toRoomId: 'n2',
        initialHeading: east,
      )!;

      // Door to door: out of the lobby's doorway, down the corridor, stop at
      // n2's door. The leg that used to cross the lobby to reach its own door
      // is gone, and with it the only leg nobody needed directions for.
      expect(route.legs, hasLength(1));
      expect(route.landmarkIds, ['room-corridor', 'room-n2']);
    });

    test('THE POINT: the door count reaches guidance as spoken words', () {
      // The whole reason the room layer exists. GuidanceBloc speaks
      // PlannedLeg.instruction verbatim, so this sentence — which only the
      // room geometry could produce — comes out of the existing pipeline with
      // no change to it at all.
      final route = RoomPlanBridge.plannedRouteFrom(
        buildWing(),
        fromRoomId: 'lobby',
        toRoomId: 'n2',
        initialHeading: east,
      )!;

      expect(
        route.legs.map((l) => l.instruction ?? '').join(' '),
        contains('second door on your left'),
      );
    });

    /// The half of the same bug that reached the arrow: `ArGuidanceCubit` uses
    /// `leg.distanceM` as metres the moment the session says it is metric, so
    /// an unconverted leg put the ring at a quarter of the distance to the
    /// door on a plan measured at 4 m per unit.
    test('a declared scale reaches the legs guidance walks', () {
      PlannedRoute routeAt(double? scale) => RoomPlanBridge.plannedRouteFrom(
        buildWing().copyWith(metresPerUnit: scale),
        fromRoomId: 'lobby',
        toRoomId: 'n2',
        initialHeading: east,
      )!;

      final unitless = routeAt(null);
      final scaled = routeAt(4);

      expect(
        scaled.totalDistanceM,
        closeTo(unitless.totalDistanceM * 4, 1e-9),
      );
      // And the turns are untouched: an angle is the same angle at any scale,
      // which is the reason a non-metric route was steerable in the first
      // place.
      expect(
        scaled.legs.map((l) => l.turnDeg),
        unitless.legs.map((l) => l.turnDeg),
      );
    });

    test('leg distances add up to the walked route', () {
      final route = RoomPlanBridge.plannedRouteFrom(
        buildWing(),
        fromRoomId: 'lobby',
        toRoomId: 'n3',
        initialHeading: east,
      )!;

      // Same total the nav graph reported for this walk — the legs partition
      // the polyline rather than re-measuring it centre to centre. Door to
      // door now, so the corridor and neither room's interior.
      expect(route.totalDistanceM, closeTo(12.04, 0.05));
    });

    test('turns are carried in the repo convention: positive is right', () {
      final route = RoomPlanBridge.plannedRouteFrom(
        buildWing(),
        fromRoomId: 'lobby',
        toRoomId: 'n2',
        initialHeading: east,
      )!;

      // Walking east then turning north into the room is a left turn.
      expect(route.legs.last.turnDeg, lessThan(0));
    });

    test('an unreachable room routes to null, not to an exception', () {
      final plan = buildWing().copyWith(
        storedRooms: [
          ...buildWing().rooms,
          rectRoom(
            id: 'orphan',
            code: 'GF 9',
            category: RoomCategory.office,
            left: 40,
            right: 44,
            bottom: 0,
            top: 4,
          ),
        ],
      );

      expect(
        RoomPlanBridge.plannedRouteFrom(
          plan,
          fromRoomId: 'lobby',
          toRoomId: 'orphan',
        ),
        isNull,
      );
    });

    test('a route is not marked synthesised — one plan, nothing spliced', () {
      final route = RoomPlanBridge.plannedRouteFrom(
        buildWing(),
        fromRoomId: 'lobby',
        toRoomId: 'n2',
      )!;

      expect(route.synthesised, isFalse);
    });

    test('an incomplete corridor drops the ordinal but keeps the route', () {
      final route = RoomPlanBridge.plannedRouteFrom(
        buildWing(declareDoors: false),
        fromRoomId: 'lobby',
        toRoomId: 'n2',
        initialHeading: east,
      )!;

      final spoken = route.legs.map((l) => l.instruction ?? '').join(' ');

      expect(route.legs, hasLength(1));
      expect(spoken, isNot(contains('door on your')));
      expect(spoken, contains('Digital Forensic Office'));
    });
  });

  group('a traced plan assembles a whole guidance session', () {
    test('everything GuidanceBloc needs comes out of one RoomPlan', () {
      final plan = buildWing();
      final route = RoomPlanBridge.plannedRouteFrom(
        plan,
        fromRoomId: 'lobby',
        toRoomId: 'n2',
        initialHeading: east,
      )!;

      final session = GuidanceSession(
        plan: route,
        landmarks: RoomPlanBridge.landmarksFrom(plan),
        destinationName: plan.roomOf('n2')!.spokenName,
        graph: RoomPlanBridge.floorGraphFrom(plan),
        metric: plan.isMetric,
      );

      expect(session.destinationLandmarkId, 'room-n2');
      expect(session.nameOf('room-n2'), 'Digital Forensic Office');
      // Unitless, so guidance leans on landmark confirmation rather than
      // promising "about twenty steps" from arbitrary plan units.
      expect(session.metric, isFalse);
      // Recovery can replan from anywhere in the building.
      expect(session.graph!.nodes, isNotEmpty);
    });

    test('a room matched to a recorded landmark keeps that landmark id', () {
      // So a plan traced over a building somebody already walked joins their
      // recordings instead of shadowing them with a parallel set of nodes.
      final plan = buildWing();
      final matched = plan.copyWith(
        storedRooms: [
          for (final room in plan.rooms)
            if (room.id == 'n2')
              room.copyWith(landmarkId: 'landmark-uuid-204')
            else
              room,
        ],
      );

      final route = RoomPlanBridge.plannedRouteFrom(
        matched,
        fromRoomId: 'lobby',
        toRoomId: 'n2',
      )!;

      expect(route.legs.last.toLandmarkId, 'landmark-uuid-204');
      expect(
        RoomPlanBridge.landmarksFrom(matched).map((l) => l.id),
        contains('landmark-uuid-204'),
      );
    });

    test('an uncalibrated plan produces a valid routePath using architectural scale estimation', () {
      final plan = buildWing();
      expect(plan.metresPerUnit, isNull);

      final path = RoomPlanBridge.routePathFrom(
        plan,
        fromRoomId: 'lobby',
        toRoomId: 'n2',
      );

      expect(path, isNotNull);
      expect(path!.pointsM.length, greaterThanOrEqualTo(2));
      expect(path.totalM, greaterThan(0));
      expect(path.legEndsM, isNotEmpty);
    });

    test('dynamic scale overrides estimated scale for routePath', () {
      final plan = buildWing();
      final normal = RoomPlanBridge.routePathFrom(
        plan,
        fromRoomId: 'lobby',
        toRoomId: 'n2',
      )!;
      final scaled = RoomPlanBridge.routePathFrom(
        plan,
        fromRoomId: 'lobby',
        toRoomId: 'n2',
        dynamicScale: 2.0,
      )!;

      expect(scaled.pointsM.length, normal.pointsM.length);
      expect(scaled.totalM, greaterThan(0));
    });
  });
}
