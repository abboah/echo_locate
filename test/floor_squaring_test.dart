import 'dart:math' as math;

import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/services/mapping/floor_squaring.dart';
import 'package:flutter_test/flutter_test.dart';

Room rect(
  String id, {
  required double left,
  required double right,
  required double bottom,
  required double top,
  RoomCategory category = RoomCategory.office,
}) => Room(
  id: id,
  floorId: 'f',
  code: id,
  category: category,
  polygon: [
    RoomCorner(x: left, y: bottom),
    RoomCorner(x: right, y: bottom),
    RoomCorner(x: right, y: top),
    RoomCorner(x: left, y: top),
  ],
);

RoomPlan planOf(List<Room> rooms, {List<Opening> openings = const []}) =>
    RoomPlan(
      buildingId: 'b',
      floorId: 'f',
      codePrefix: 'G',
      storedRooms: rooms,
      storedOpenings: openings,
    );

/// Rotates a plan's geometry, standing in for a photograph taken off-square.
RoomPlan tilt(RoomPlan plan, double degrees) {
  final r = degrees * math.pi / 180;
  final cos = math.cos(r), sin = math.sin(r);
  Offset spin(Offset p) => Offset(p.dx * cos - p.dy * sin, p.dx * sin + p.dy * cos);
  return plan.copyWith(
    storedRooms: [
      for (final room in plan.rooms)
        room.copyWith(
          polygon: [for (final c in room.corners) RoomCorner.of(spin(c))],
        ),
    ],
    storedOpenings: [
      for (final o in plan.openings)
        o.copyWith(at: RoomCorner.of(spin(o.at.offset))),
    ],
  );
}

double worstAngleOffAxis(RoomPlan plan) {
  var worst = 0.0;
  for (final room in plan.rooms) {
    final c = room.corners;
    for (var i = 0; i < c.length; i++) {
      final e = c[(i + 1) % c.length] - c[i];
      if (e.distance < 1e-9) continue;
      var deg = math.atan2(e.dy, e.dx) * 180 / math.pi;
      deg = deg % 90;
      if (deg < 0) deg += 90;
      final off = math.min(deg, 90 - deg);
      if (off > worst) worst = off;
    }
  }
  return worst;
}

void main() {
  group('dominantSkew', () {
    test('an already-square floor has no skew', () {
      final plan = planOf([rect('a', left: 0, right: 4, bottom: 0, top: 3)]);
      expect(dominantSkew(plan) * 180 / math.pi, closeTo(0, 1e-6));
    });

    test('it finds the angle a tilted floor was traced at', () {
      final plan = tilt(
        planOf([rect('a', left: 0, right: 40, bottom: 0, top: 30)]),
        6,
      );
      expect(dominantSkew(plan) * 180 / math.pi, closeTo(6, 0.01));
    });

    test('long walls outvote short ones', () {
      // One long true wall, several short splayed ones. Unweighted, the crowd
      // of small edges would carry the vote and rotate the floor to nonsense.
      final plan = planOf([
        rect('long', left: 0, right: 100, bottom: 0, top: 1),
        tilt(planOf([rect('a', left: 0, right: 2, bottom: 5, top: 6)]), 20).rooms.first,
        tilt(planOf([rect('b', left: 0, right: 2, bottom: 8, top: 9)]), 20).rooms.first,
      ]);
      expect(dominantSkew(plan).abs() * 180 / math.pi, lessThan(3));
    });
  });

  group('squareFloor', () {
    test('it straightens a floor traced off-square', () {
      final plan = tilt(
        planOf([
          rect('a', left: 0, right: 40, bottom: 0, top: 30),
          rect('b', left: 40, right: 70, bottom: 0, top: 30),
        ]),
        5,
      );
      expect(worstAngleOffAxis(plan), greaterThan(4));
      expect(worstAngleOffAxis(squareFloor(plan)), lessThan(0.5));
    });

    test('walls that were meant to be one wall become one wall', () {
      // The defect this exists for: neighbours cleaned independently disagree
      // by a hair, so the shared wall is two lines and the rooms do not touch.
      final plan = planOf([
        rect('a', left: 0, right: 10.00, bottom: 0, top: 10),
        rect('b', left: 10.04, right: 20, bottom: 0, top: 10),
      ]);
      final squared = squareFloor(plan);
      final a = squared.rooms.firstWhere((r) => r.id == 'a');
      final b = squared.rooms.firstWhere((r) => r.id == 'b');
      final aRight = a.corners.map((c) => c.dx).reduce(math.max);
      final bLeft = b.corners.map((c) => c.dx).reduce(math.min);
      expect(aRight, closeTo(bLeft, 1e-9));
    });

    test('walls genuinely far apart are left apart', () {
      final plan = planOf([
        rect('a', left: 0, right: 10, bottom: 0, top: 10),
        rect('b', left: 14, right: 24, bottom: 0, top: 10),
      ]);
      final squared = squareFloor(plan);
      final a = squared.rooms.firstWhere((r) => r.id == 'a');
      final b = squared.rooms.firstWhere((r) => r.id == 'b');
      expect(a.corners.map((c) => c.dx).reduce(math.max), closeTo(10, 1e-6));
      expect(b.corners.map((c) => c.dx).reduce(math.min), closeTo(14, 1e-6));
    });

    test('doors move with the walls they sit in', () {
      final plan = planOf(
        [rect('a', left: 0, right: 10, bottom: 0, top: 10)],
        openings: [
          const Opening(
            id: 'd1',
            roomAId: 'a',
            at: RoomCorner(x: 5, y: 0),
          ),
        ],
      );
      final tilted = tilt(plan, 7);
      final squared = squareFloor(tilted);
      final room = squared.rooms.first;
      final door = squared.openings.first.at.offset;
      // Still on the room's bottom wall, not floating off it.
      final bottom = room.corners.map((c) => c.dy).reduce(math.min);
      expect(door.dy, closeTo(bottom, 0.2));
    });

    test('no room is lost, whatever the tolerance does', () {
      final plan = planOf([
        rect('a', left: 0, right: 100, bottom: 0, top: 100),
        // Far smaller than the weld window for this floor: it would collapse
        // if the pass were willing to destroy a room to tidy one.
        rect('tiny', left: 10, right: 10.2, bottom: 10, top: 10.2),
      ]);
      final squared = squareFloor(plan);
      expect(squared.rooms, hasLength(2));
      final tiny = squared.rooms.firstWhere((r) => r.id == 'tiny');
      expect(tiny.corners.length, greaterThanOrEqualTo(3));
    });

    test('an empty plan comes back untouched', () {
      final plan = planOf(const []);
      expect(squareFloor(plan), plan);
    });

    test('a corridor keeps its centreline', () {
      final plan = planOf([
        rect('c', left: 0, right: 40, bottom: 0, top: 4,
            category: RoomCategory.corridor)
            .copyWith(centreline: const [
          RoomCorner(x: 0, y: 2),
          RoomCorner(x: 40, y: 2),
        ]),
      ]);
      final squared = squareFloor(tilt(plan, 4));
      expect(squared.rooms.first.centreline, hasLength(2));
    });
  });
}
