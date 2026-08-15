import 'dart:math' as math;

import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/services/mapping/plan_editing.dart';
import 'package:echo_locate/services/mapping/room_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

Room square(String id, {double left = 0, double size = 10}) => Room(
  id: id,
  floorId: 'f',
  code: id,
  category: RoomCategory.office,
  polygon: [
    RoomCorner(x: left, y: 0),
    RoomCorner(x: left + size, y: 0),
    RoomCorner(x: left + size, y: size),
    RoomCorner(x: left, y: size),
  ],
);

/// A corridor running east along y = 12, 40 long, with a band around it.
Room corridor(String id, {int points = 5, double step = 10}) {
  final spine = [
    for (var i = 0; i < points; i++) Offset(i * step, 12),
  ];
  return Room(
    id: id,
    floorId: 'f',
    code: id,
    category: RoomCategory.corridor,
    centreline: [for (final p in spine) RoomCorner.of(p)],
    polygon: [for (final p in ribbonAround(spine, 1)) RoomCorner.of(p)],
  );
}

RoomPlan planOf(List<Room> rooms, [List<Opening> openings = const []]) =>
    RoomPlan(
      buildingId: 'b',
      floorId: 'f',
      codePrefix: 'G',
      storedRooms: rooms,
      storedOpenings: openings,
    );

Opening doorAt(String id, String roomA, double x, double y) =>
    Opening(id: id, roomAId: roomA, at: RoomCorner(x: x, y: y));

/// The same square, filed under a wing that has been dragged somewhere else.
///
/// The state a floor is in the moment a second board or a second AR session is
/// traced: the geometry is stored where it was captured, and the plan carries
/// the placement that says where it really goes.
RoomPlan wingedPlan(
  WingPlacement placement, {
  List<Opening> openings = const [],
}) => RoomPlan(
  buildingId: 'b',
  floorId: 'f',
  codePrefix: 'G',
  storedRooms: [square('a').copyWith(wingId: 'wing-2')],
  storedOpenings: openings,
  wings: {'wing-2': placement},
);

/// Where a room is *drawn* — placement applied, which is what a finger points
/// at and what these tests measure.
Offset placedCorner(RoomPlan plan, String roomId, int index) =>
    plan.roomOf(roomId)!.corners[index];

void main() {
  group('corridor points', () {
    test('trimming drops the tail and keeps the run before it', () {
      final plan = planOf([corridor('c')]);
      final out = trimCorridorAfter(plan, 'c', 2);

      expect(out.plan.rooms.first.spine, hasLength(3));
      expect(out.plan.rooms.first.spine.last.dx, 20);
      // The band is rebuilt, not left describing the old length.
      expect(out.plan.rooms.first.corners.map((c) => c.dx).reduce(
            (a, b) => a > b ? a : b,
          ), lessThan(40));
    });

    test('a door on the trimmed-away tail is dropped and counted', () {
      final plan = planOf(
        [corridor('c')],
        [doorAt('near', 'c', 5, 12), doorAt('far', 'c', 40, 12)],
      );
      final out = trimCorridorAfter(plan, 'c', 1);

      expect(out.doorsDropped, 1);
      expect(out.plan.openings.map((o) => o.id), ['near']);
    });

    test('doors on the part that survives are untouched', () {
      final plan = planOf(
        [corridor('c')],
        [doorAt('a', 'c', 5, 12), doorAt('b', 'c', 15, 12)],
      );
      final out = trimCorridorAfter(plan, 'c', 3);

      expect(out.doorsDropped, 0);
      expect(out.plan.openings, hasLength(2));
    });

    test('moving a point moves the band with it', () {
      final plan = planOf([corridor('c')]);
      final out = moveCorridorPoint(plan, 'c', 2, const Offset(20, 30));

      expect(out.plan.rooms.first.spine[2].dy, 30);
      expect(
        out.plan.rooms.first.corners.map((c) => c.dy).reduce(
              (a, b) => a > b ? a : b,
            ),
        greaterThan(25),
      );
    });

    test('a corridor is never trimmed below two points', () {
      final plan = planOf([corridor('c', points: 2)]);
      expect(deleteCorridorPoint(plan, 'c', 0).plan, plan);
      expect(trimCorridorAfter(plan, 'c', 0).plan, plan);
    });

    test('an unknown room changes nothing', () {
      final plan = planOf([corridor('c')]);
      expect(trimCorridorAfter(plan, 'nope', 1).plan, plan);
    });
  });

  group('room corners', () {
    test('a corner can be moved', () {
      final plan = planOf([square('a')]);
      final out = moveRoomCorner(plan, 'a', 2, const Offset(14, 14));

      expect(out.plan.rooms.first.corners[2], const Offset(14, 14));
      expect(out.doorsDropped, 0);
    });

    test('a move that crosses the walls is refused', () {
      // Dragging a corner through the opposite wall makes a bowtie, which has
      // no meaningful centroid and would put a room's name outside itself.
      final plan = planOf([square('a')]);
      final out = moveRoomCorner(plan, 'a', 3, const Offset(5, -5));
      expect(out.plan, plan);
    });

    test('a move that folds the room flat is refused', () {
      // Corner onto corner: the walls never cross, they collapse, so
      // `selfIntersects` says nothing and the room would draw as a line.
      final plan = planOf([square('a')]);
      final out = moveRoomCorner(plan, 'a', 0, const Offset(10, 10));
      expect(out.plan, plan);
    });

    test('a corner can be inserted and lands on the wall', () {
      final plan = planOf([square('a')]);
      final out = insertRoomCorner(plan, 'a', 0);

      expect(out.plan.rooms.first.corners, hasLength(5));
      expect(out.plan.rooms.first.corners[1], const Offset(5, 0));
    });

    test('a room is never left with fewer than three corners', () {
      final plan = planOf([square('a')]);
      var out = deleteRoomCorner(plan, 'a', 0);
      expect(out.plan.rooms.first.corners, hasLength(3));

      out = deleteRoomCorner(out.plan, 'a', 0);
      expect(out.plan.rooms.first.corners, hasLength(3));
    });

    test('dragging never drops a door, however far it is dragged', () {
      // A drag emits a plan per frame. Dropping orphans there would delete a
      // door as the finger swept past somewhere far and never restore it when
      // the finger came back — the shape recovers, the door does not.
      final plan = planOf(
        [square('a', size: 10)],
        [doorAt('d', 'a', 5, 0)],
      );
      var out = moveRoomCorner(plan, 'a', 0, const Offset(-400, -400));
      out = moveRoomCorner(out.plan, 'a', 0, const Offset(0, 0));

      expect(out.doorsDropped, 0);
      expect(out.plan.openings.map((o) => o.id), ['d']);
      // And the shape is back where it started.
      expect(out.plan.rooms.first.corners.first, const Offset(0, 0));
    });

    test('doors on other rooms are never touched', () {
      final plan = planOf(
        [square('a'), square('b', left: 20)],
        [doorAt('other', 'b', 25, 0)],
      );
      final out = moveRoomCorner(plan, 'a', 2, const Offset(12, 12));

      expect(out.plan.openings.map((o) => o.id), contains('other'));
      expect(out.doorsDropped, 0);
    });
  });

  // The frame edits are read in is not the frame they are written to. Every
  // test here fails by a wing jumping its own offset — a fault that is
  // completely invisible until somebody captures a second wing.
  group('editing a wing that has been placed', () {
    test('a dragged corner lands where it was dropped, not twice as far', () {
      final plan = wingedPlan(const WingPlacement(dx: 100));
      // Corner 2 is drawn at (110, 10) — the stored (10, 10) shifted by the
      // wing. Dropping it at (114, 14) must leave it drawn at (114, 14).
      final out = moveRoomCorner(plan, 'a', 2, const Offset(114, 14));

      expect(placedCorner(out.plan, 'a', 2), const Offset(114, 14));
      // And stored in the wing's own coordinates, with the offset taken back
      // off. Storing (114, 14) here is what makes it read as (214, 14).
      expect(out.plan.storedRoomOf('a')!.corners[2], const Offset(14, 14));
    });

    test('the placement survives the edit', () {
      final plan = wingedPlan(const WingPlacement(dx: 100));
      final out = moveRoomCorner(plan, 'a', 2, const Offset(114, 14));

      expect(out.plan.wings['wing-2'], const WingPlacement(dx: 100));
      // Nothing else in the wing moved with it.
      expect(placedCorner(out.plan, 'a', 0), const Offset(100, 0));
    });

    test('a rotated wing takes the drag back through its own rotation', () {
      final plan = wingedPlan(const WingPlacement(rotation: math.pi / 2));
      // A quarter turn puts stored (10, 10) at drawn (-10, 10).
      final drawn = placedCorner(plan, 'a', 2);
      expect(drawn.dx, closeTo(-10, 1e-9));
      expect(drawn.dy, closeTo(10, 1e-9));

      final out = moveRoomCorner(plan, 'a', 2, const Offset(-14, 14));
      final after = placedCorner(out.plan, 'a', 2);
      expect(after.dx, closeTo(-14, 1e-9));
      expect(after.dy, closeTo(14, 1e-9));
    });

    test('a door in the wing is measured against the wing, not the floor', () {
      // The door is stored at the wing's own (5, 0) — drawn at (105, 0), right
      // on the room's wall. Measured raw against a room stored at 0..10 it is a
      // hundred units away and would be dropped by the first discrete edit.
      final plan = wingedPlan(
        const WingPlacement(dx: 100),
        openings: [doorAt('d', 'a', 5, 0)],
      );
      final out = deleteRoomCorner(plan, 'a', 2);

      expect(out.doorsDropped, 0);
      expect(out.plan.openings.map((o) => o.id), ['d']);
    });
  });

  group('moving a whole room', () {
    test('the room and its doors move together', () {
      final plan = planOf([square('a')], [doorAt('d', 'a', 5, 0)]);
      final out = moveRoom(plan, 'a', const Offset(3, 4));

      expect(out.plan.rooms.first.corners.first, const Offset(3, 4));
      expect(out.plan.openings.first.position, const Offset(8, 4));
      expect(out.doorsDropped, 0);
    });

    test('a corridor keeps its centreline under its band', () {
      final plan = planOf([corridor('c')]);
      final out = moveRoom(plan, 'c', const Offset(0, 5));

      expect(out.plan.rooms.first.spine.first, const Offset(0, 17));
      // The band came along, so the corridor is not drawn where it no longer
      // routes.
      final ys = out.plan.rooms.first.corners.map((c) => c.dy);
      expect(ys.reduce(math.min), greaterThan(15));
    });

    test('a room in another wing is left alone', () {
      final plan = planOf([square('a'), square('b', left: 20)]);
      final out = moveRoom(plan, 'a', const Offset(3, 0));

      expect(out.plan.rooms[1].corners.first, const Offset(20, 0));
    });

    test('a move on a placed wing is stored in the wing frame', () {
      final plan = wingedPlan(const WingPlacement(dx: 100));
      final out = moveRoom(plan, 'a', const Offset(5, 0));

      expect(placedCorner(out.plan, 'a', 0), const Offset(105, 0));
      expect(out.plan.storedRoomOf('a')!.corners.first, const Offset(5, 0));
    });

    test('a rotated wing turns the drag into its own frame', () {
      final plan = wingedPlan(const WingPlacement(rotation: math.pi / 2));
      // Dragging a quarter-turned wing north on screen must move it north on
      // screen — not east, which is what an unrotated delta does.
      final out = moveRoom(plan, 'a', const Offset(0, 1));
      final before = placedCorner(plan, 'a', 0);
      final after = placedCorner(out.plan, 'a', 0);

      expect(after.dx - before.dx, closeTo(0, 1e-9));
      expect(after.dy - before.dy, closeTo(1, 1e-9));
    });

    test('an unknown room changes nothing', () {
      final plan = planOf([square('a')]);
      expect(moveRoom(plan, 'nope', const Offset(1, 1)).plan, plan);
    });
  });
}
