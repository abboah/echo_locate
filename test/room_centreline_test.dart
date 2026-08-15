import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/services/mapping/room_directions.dart';
import 'package:echo_locate/services/mapping/room_geometry.dart';
import 'package:echo_locate/services/mapping/room_graph.dart';
import 'package:echo_locate/services/mapping/room_plan_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

RoomCorner c(double x, double y) => RoomCorner(x: x, y: y);

/// An L-shaped hallway: 20 m east, then 20 m north.
///
/// The shape the whole centreline idea exists for. Traced as a bare polygon it
/// has no single axis — its longest wall runs east, so everything past the bend
/// gets measured against a line at right angles to the way the walker is going.
const _lPath = [
  RoomCorner(x: 0, y: 0),
  RoomCorner(x: 20, y: 0),
  RoomCorner(x: 20, y: 20),
];

void main() {
  group('polyline primitives', () {
    test('length is the sum of the segments', () {
      expect(
        polylineLength(const [Offset(0, 0), Offset(3, 0), Offset(3, 4)]),
        closeTo(7, 1e-9),
      );
    });

    test('projection reports arc length, not distance from the start', () {
      // Round the bend of an L. Straight-line back to the origin is about
      // 20.6 m; along the corridor it is 25.
      final hit = projectOntoPolyline(const [
        Offset(0, 0),
        Offset(20, 0),
        Offset(20, 20),
      ], const Offset(20, 5));

      expect(hit.along, closeTo(25, 1e-9));
      expect(hit.distance, closeTo(0, 1e-9));
      expect(hit.at, const Offset(20, 5));
    });

    test('a point off the line measures its perpendicular offset', () {
      final hit = projectOntoPolyline(const [
        Offset(0, 0),
        Offset(20, 0),
      ], const Offset(8, 3));

      expect(hit.along, closeTo(8, 1e-9));
      expect(hit.distance, closeTo(3, 1e-9));
    });

    test('walking to a point is the inverse of projecting one', () {
      const line = [Offset(0, 0), Offset(20, 0), Offset(20, 20)];
      expect(pointAlongPolyline(line, 25), const Offset(20, 5));
      // Clamped at both ends rather than extrapolated off the corridor.
      expect(pointAlongPolyline(line, -5), const Offset(0, 0));
      expect(pointAlongPolyline(line, 500), const Offset(20, 20));
    });

    test('direction follows the corridor round its bend', () {
      const line = [Offset(0, 0), Offset(20, 0), Offset(20, 20)];
      expect(polylineDirectionAt(line, 5).dx, closeTo(1, 1e-9));
      expect(polylineDirectionAt(line, 30).dy, closeTo(1, 1e-9));
    });

    test('a slice keeps the vertices between its ends', () {
      const line = [Offset(0, 0), Offset(20, 0), Offset(20, 20)];
      final slice = polylineSlice(line, 10, 30);

      expect(slice.first, const Offset(10, 0));
      expect(slice, contains(const Offset(20, 0)));
      expect(slice.last, const Offset(20, 10));
    });

    test('a slice taken backwards comes back reversed', () {
      // A corridor is walked both ways and was drawn only one way, so the
      // route has to be able to run down it against the grain.
      const line = [Offset(0, 0), Offset(20, 0), Offset(20, 20)];
      final slice = polylineSlice(line, 30, 10);

      expect(slice.first, const Offset(20, 10));
      expect(slice.last, const Offset(10, 0));
    });
  });

  group('ribbonAround', () {
    test('a straight path becomes a rectangle of the right width', () {
      final ribbon = ribbonAround(const [Offset(0, 0), Offset(10, 0)], 1);

      expect(ribbon, hasLength(4));
      expect(boundsOf(ribbon).width, closeTo(10, 1e-6));
      expect(boundsOf(ribbon).height, closeTo(2, 1e-6));
    });

    test('the centreline stays inside the shape it generates', () {
      final ribbon = ribbonAround(const [
        Offset(0, 0),
        Offset(20, 0),
        Offset(20, 20),
      ], 1);

      for (final point in [
        const Offset(5, 0),
        const Offset(19, 0),
        const Offset(20, 15),
      ]) {
        expect(
          containsPoint(ribbon, point),
          isTrue,
          reason: '$point should be inside its own corridor',
        );
      }
    });

    test('comes out wound the way every other polygon is', () {
      // Everything downstream assumes counter-clockwise — see
      // `normaliseWinding`. A generated shape has no contributor to blame for
      // getting it backwards, so it must come out right by construction.
      final ribbon = ribbonAround(const [Offset(0, 0), Offset(10, 0)], 1);
      expect(signedArea(ribbon), greaterThan(0));
    });

    test('a hairpin is bevelled rather than spiked off the floor', () {
      // The exact mitre at a 180° turn runs to infinity. Capped, so a corridor
      // doubling back stays roughly its own size.
      final ribbon = ribbonAround(const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(0, 0.5),
      ], 1);

      expect(boundsOf(ribbon).width, lessThan(20));
      expect(boundsOf(ribbon).height, lessThan(20));
    });

    test('degenerate input yields nothing rather than a broken polygon', () {
      expect(ribbonAround(const [Offset(0, 0)], 1), isEmpty);
      expect(ribbonAround(const [Offset(0, 0), Offset(0, 0)], 1), isEmpty);
      expect(ribbonAround(const [Offset(0, 0), Offset(1, 0)], 0), isEmpty);
    });
  });

  group('a corridor drawn as a path', () {
    /// The L-shaped hallway with three rooms off it: one on the east leg, two
    /// on the north leg. Every door is on the corridor's left as walked.
    RoomPlan lPlan() {
      final hall = Room(
        id: 'hall',
        floorId: 'g',
        code: 'GF 1',
        category: RoomCategory.corridor,
        polygon: [
          for (final point in ribbonAround([
            for (final p in _lPath) p.offset,
          ], 1))
            RoomCorner.of(point),
        ],
        centreline: _lPath,
      );

      Room off(String id, String code, double x, double y) => Room(
        id: id,
        floorId: 'g',
        code: code,
        category: RoomCategory.office,
        polygon: [
          c(x - 2, y - 2),
          c(x + 2, y - 2),
          c(x + 2, y + 2),
          c(x - 2, y + 2),
        ],
      );

      return RoomPlan(
        buildingId: 'b',
        floorId: 'g',
        codePrefix: 'GF',
        metresPerUnit: 1,
        storedRooms: [
          hall,
          // North of the east leg — on the walker's left going east.
          off('a', 'GF 2', 6, 4),
          // West of the north leg — on the walker's left going north.
          off('b', 'GF 3', 16, 8),
          off('d', 'GF 4', 16, 16),
        ],
        storedOpenings: const [
          Opening(
            id: 'oa',
            roomAId: 'hall',
            roomBId: 'a',
            at: RoomCorner(x: 6, y: 1),
          ),
          Opening(
            id: 'ob',
            roomAId: 'hall',
            roomBId: 'b',
            at: RoomCorner(x: 19, y: 8),
          ),
          Opening(
            id: 'od',
            roomAId: 'hall',
            roomBId: 'd',
            at: RoomCorner(x: 19, y: 16),
          ),
        ],
        declaredDoorCounts: {'hall': 3},
      );
    }

    test('the room centre sits on the walk, not in the missing corner', () {
      final hall = lPlan().roomOf('hall')!;

      expect(hall.hasSpine, isTrue);
      // Halfway along 40 m of corridor is the bend.
      expect(hall.centre.dx, closeTo(20, 1e-6));
      expect(hall.centre.dy, closeTo(0, 1e-6));
    });

    test('doors round the bend are ordered by how far along they are', () {
      final plan = lPlan();
      final hall = plan.roomOf('hall')!;

      final passed = doorsPassedAlong(
        plan: plan,
        corridor: hall,
        from: const Offset(0, 0),
        to: const Offset(20, 20),
      );

      expect([for (final d in passed) d.openingId], ['oa', 'ob', 'od']);
      expect(passed.first.alongM, closeTo(6, 0.5));
      expect(passed.last.alongM, closeTo(36, 0.5));
    });

    test('every door reads left, on both legs of the L', () {
      // The bug the centreline removes. Measured against the corridor's longest
      // wall — which runs east — the two doors on the north leg come out on the
      // wrong side, and the sentence reads perfectly either way.
      final plan = lPlan();
      final hall = plan.roomOf('hall')!;

      final passed = doorsPassedAlong(
        plan: plan,
        corridor: hall,
        from: const Offset(0, 0),
        to: const Offset(20, 20),
      );

      expect([for (final d in passed) d.side], ['left', 'left', 'left']);
    });

    test('walking the other way puts them all on the right, in reverse', () {
      final plan = lPlan();
      final hall = plan.roomOf('hall')!;

      final passed = doorsPassedAlong(
        plan: plan,
        corridor: hall,
        from: const Offset(20, 20),
        to: const Offset(0, 0),
      );

      expect([for (final d in passed) d.openingId], ['od', 'ob', 'oa']);
      expect([for (final d in passed) d.side], ['right', 'right', 'right']);
    });

    test('the same corridor without a centreline gets the far leg wrong', () {
      // Kept as a test rather than a comment: it is the evidence that the
      // centreline is doing something, and it pins the fallback's behaviour so
      // nobody "fixes" the polygon path into silently disagreeing with it.
      final plan = lPlan();
      final flattened = plan.roomOf('hall')!.copyWith(centreline: const []);

      final passed = doorsPassedAlong(
        plan: plan,
        corridor: flattened,
        from: const Offset(0, 0),
        to: const Offset(20, 20),
      );

      expect(
        [for (final d in passed) d.side],
        isNot(['left', 'left', 'left']),
        reason: 'the polygon fallback should not manage what the spine does',
      );
    });

    test('the drawn route bends round the corridor instead of cutting it', () {
      final plan = lPlan();
      final route = RoomNavGraph.build(
        plan,
      ).route(fromRoomId: 'a', toRoomId: 'd');

      expect(route, isNotNull);
      // The bend is on the drawn line even though no waypoint sits there.
      expect(
        route!.polyline.any((p) => (p - const Offset(20, 0)).distance < 1e-6),
        isTrue,
      );
      expect(
        route.waypoints.any(
          (w) => (w.at - const Offset(20, 0)).distance < 1e-6,
        ),
        isFalse,
      );
    });

    test('the walked distance is longer than the straight line', () {
      final plan = lPlan();
      final route = RoomNavGraph.build(
        plan,
      ).route(fromRoomId: 'a', toRoomId: 'd')!;

      expect(route.walkedDistanceM, greaterThan(route.totalDistanceM));
    });

    test('routing costs the corner rather than pretending it is not there', () {
      // Door 'oa' to door 'od' is about 20 m apart in a straight line and 30 m
      // to walk. A* handed the straight line would price the corner at nothing.
      final graph = RoomNavGraph.build(lPlan());
      final route = graph.route(fromRoomId: 'a', toRoomId: 'd')!;

      expect(route.walkedDistanceM, greaterThan(28));
    });

    test('an ordinary room is still measured in a straight line', () {
      // No centreline, no change: the whole existing corpus depends on it.
      final plan = lPlan();
      expect(plan.roomOf('a')!.hasSpine, isFalse);
      expect(plan.roomOf('a')!.centre.dx, closeTo(6, 1e-6));
    });
  });

  group('spoken directions over a path corridor', () {
    test('name the door ordinal correctly past the bend', () {
      final plan = _threeDoorPlan();
      final graph = RoomNavGraph.build(plan);
      final route = graph.route(fromRoomId: 'a', toRoomId: 'd')!;

      final spoken = const RoomDirections(
        metric: true,
      ).describe(graph, route).map((i) => i.text).join(' ');

      // Second, not third: the walk starts by coming *out* of the first door,
      // and the door you leave through is not one you pass. So the walker
      // passes 'ob' and then arrives at 'od' — and it is on the left, which is
      // the part the bend would otherwise have got wrong.
      expect(spoken, contains('second door on your left'));
    });

    test('a leg round the bend is quoted at its walked length', () {
      // What this number becomes is "about forty steps" in somebody's ear. The
      // straight line across the corner is shorter than the corridor, so
      // quoting it stops a blind walker short of the bend every time.
      final plan = _threeDoorPlan();
      final planned = RoomPlanBridge.plannedRouteFrom(
        plan,
        fromRoomId: 'a',
        toRoomId: 'd',
      )!;

      final bend = planned.legs.fold<double>(
        0,
        (sum, leg) => sum + leg.distanceM,
      );
      final straight = RoomNavGraph.build(
        plan,
      ).route(fromRoomId: 'a', toRoomId: 'd')!.totalDistanceM;

      expect(bend, greaterThan(straight));
    });
  });
}

/// The L-plan again, built where the directions group can reach it.
RoomPlan _threeDoorPlan() {
  final ribbon = ribbonAround([for (final p in _lPath) p.offset], 1);

  Room off(String id, String code, double x, double y) => Room(
    id: id,
    floorId: 'g',
    code: code,
    category: RoomCategory.office,
    polygon: [
      c(x - 2, y - 2),
      c(x + 2, y - 2),
      c(x + 2, y + 2),
      c(x - 2, y + 2),
    ],
  );

  return RoomPlan(
    buildingId: 'b',
    floorId: 'g',
    codePrefix: 'GF',
    metresPerUnit: 1,
    storedRooms: [
      Room(
        id: 'hall',
        floorId: 'g',
        code: 'GF 1',
        category: RoomCategory.corridor,
        polygon: [for (final point in ribbon) RoomCorner.of(point)],
        centreline: _lPath,
      ),
      off('a', 'GF 2', 6, 4),
      off('b', 'GF 3', 16, 8),
      off('d', 'GF 4', 16, 16),
    ],
    storedOpenings: const [
      Opening(
        id: 'oa',
        roomAId: 'hall',
        roomBId: 'a',
        at: RoomCorner(x: 6, y: 1),
      ),
      Opening(
        id: 'ob',
        roomAId: 'hall',
        roomBId: 'b',
        at: RoomCorner(x: 19, y: 8),
      ),
      Opening(
        id: 'od',
        roomAId: 'hall',
        roomBId: 'd',
        at: RoomCorner(x: 19, y: 16),
      ),
    ],
    declaredDoorCounts: {'hall': 3},
  );
}
