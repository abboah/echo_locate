import 'dart:math' as math;

import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/plan_editor/bloc/plan_editor_cubit.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/mapping/room_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockBuildings extends Mock implements BuildingRepository {}

Room rect({
  required String id,
  required String code,
  required RoomCategory category,
  required double left,
  required double right,
  required double bottom,
  required double top,
  String? wingId,
  String? label,
}) => Room(
  id: id,
  floorId: 'gf',
  code: code,
  category: category,
  label: label,
  wingId: wingId,
  polygon: [
    RoomCorner(x: left, y: bottom),
    RoomCorner(x: right, y: bottom),
    RoomCorner(x: right, y: top),
    RoomCorner(x: left, y: top),
  ],
);

/// Two wings. Wing 1 sits at x 0..20; wing 2 was captured in its own frame at
/// x 0..20 too and is parked 40 m east, exactly as a second AR session leaves
/// it — and rotated 3° off, which is what a hand-held capture produces.
RoomPlan twoWings({double wing2Rotation = 3 * math.pi / 180}) {
  const cos3 = 0.9986295347545738;
  const sin3 = 0.05233595624294383;
  Offset spin(double x, double y) =>
      Offset(x * cos3 - y * sin3, x * sin3 + y * cos3);

  final rotated = [spin(0, 0), spin(20, 0), spin(20, 2), spin(0, 2)];

  return RoomPlan(
    buildingId: 'knust-cs',
    floorId: 'gf',
    codePrefix: 'GF',
    metresPerUnit: 1,
    storedRooms: [
      rect(
        id: 'c1',
        code: 'GF 1',
        category: RoomCategory.corridor,
        left: 0,
        right: 20,
        bottom: 0,
        top: 2,
        wingId: 'wing-1',
      ),
      rect(
        id: 'r1',
        code: 'GF 2',
        category: RoomCategory.office,
        left: 4,
        right: 8,
        bottom: 2,
        top: 6,
        wingId: 'wing-1',
      ),
      Room(
        id: 'c2',
        floorId: 'gf',
        code: 'GF 3',
        category: RoomCategory.corridor,
        wingId: 'wing-2',
        polygon: [for (final p in rotated) RoomCorner.of(p)],
      ),
    ],
    storedOpenings: const [
      Opening(
        id: 'd1',
        roomAId: 'c1',
        roomBId: 'r1',
        at: RoomCorner(x: 6, y: 2),
      ),
    ],
    wings: const {'wing-2': WingPlacement(dx: 40)},
  );
}

void main() {
  late _MockPlans plans;
  late _MockBuildings buildings;

  setUpAll(() => registerFallbackValue(RoomPlan.empty));

  setUp(() {
    plans = _MockPlans();
    buildings = _MockBuildings();
    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'gf', label: 'G', rooms: []),
        BuildingFloor(id: 'first', label: '1', rooms: []),
      ],
    );
    when(() => plans.save(any())).thenAnswer((_) async {});
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => twoWings());
  });

  Future<PlanEditorCubit> opened() async {
    final cubit = PlanEditorCubit(plans, buildings);
    await cubit.load(buildingId: 'knust-cs', floorId: 'gf');
    return cubit;
  }

  group('opening a floor', () {
    test('loads the saved plan and selects the newest wing', () async {
      final cubit = await opened();

      expect(cubit.state.status, PlanEditorStatus.ready);
      expect(cubit.state.hasWings, isTrue);
      // The one most likely to need moving is the one captured last.
      expect(cubit.state.selectedWingId, 'wing-2');
      await cubit.close();
    });

    test('an untraced floor reports empty rather than an error', () async {
      when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);

      final cubit = await opened();

      expect(cubit.state.status, PlanEditorStatus.empty);
      expect(cubit.state.error, isNull);
      await cubit.close();
    });
  });

  group('moving a wing', () {
    test('a nudge moves only the selected wing', () async {
      final cubit = await opened();
      final wing1Before = cubit.state.plan.roomOf('c1')!.bounds;

      cubit.nudgeWing(const Offset(-15, 0));

      // Wing 2 has come west; wing 1 has not moved at all.
      expect(cubit.state.plan.wings['wing-2']!.dx, 25);
      expect(cubit.state.plan.roomOf('c1')!.bounds, wing1Before);
      await cubit.close();
    });

    test('nudges accumulate rather than replacing each other', () async {
      final cubit = await opened();

      cubit.nudgeWing(const Offset(-10, 0));
      cubit.nudgeWing(const Offset(-10, 2));

      expect(cubit.state.plan.wings['wing-2']!.dx, 20);
      expect(cubit.state.plan.wings['wing-2']!.dy, 2);
      await cubit.close();
    });

    test('rotation composes with translation predictably', () async {
      final cubit = await opened();

      cubit.rotateWing(math.pi / 2);
      cubit.nudgeWing(const Offset(0, 5));

      final placement = cubit.state.plan.wings['wing-2']!;
      expect(placement.rotation, closeTo(math.pi / 2, 1e-9));
      // Translating after rotating shifts by exactly what was asked, because
      // the rotation is about the origin rather than a moving centre.
      expect(placement.dy, 5);
      await cubit.close();
    });

    test('reset puts a wing back where it was loaded', () async {
      final cubit = await opened();

      cubit.nudgeWing(const Offset(-30, 12));
      cubit.rotateWing(0.4);
      cubit.resetWing();

      expect(cubit.state.plan.wings['wing-2'], const WingPlacement(dx: 40));
      await cubit.close();
    });

    test('nothing happens with no wing selected', () async {
      final cubit = await opened();
      cubit.selectWing(null);
      final before = cubit.state.plan;

      cubit.nudgeWing(const Offset(5, 5));

      expect(cubit.state.plan, before);
      await cubit.close();
    });

    test('putting a wing back lands its rooms where they were traced', () async {
      // For work that was parked and should never have been: the rooms are
      // stored at the coordinates they were drawn at, so clearing the placement
      // is the whole fix.
      final cubit = await opened();
      final stored = cubit.state.plan.storedRoomOf('c2')!.bounds;

      cubit.unparkWing();

      expect(cubit.state.plan.wings['wing-2'], const WingPlacement());
      expect(cubit.state.plan.roomOf('c2')!.bounds, stored);
      await cubit.close();
    });

    test('reset cannot undo a wing that arrived parked, and put-back can',
        () async {
      // The reason both exist. `reset` restores the placement the plan was
      // loaded with, which for a wing parked by the tracer *is* the parked one
      // — a no-op at the exact moment somebody needs it undone.
      final cubit = await opened();

      cubit.resetWing();
      expect(cubit.state.plan.wings['wing-2'], const WingPlacement(dx: 40));

      cubit.unparkWing();
      expect(cubit.state.plan.wings['wing-2'], const WingPlacement());
      await cubit.close();
    });

    test('putting back a wing already on the floor says so', () async {
      final cubit = await opened();
      cubit.unparkWing();
      cubit.unparkWing();

      expect(cubit.state.hint, 'That wing is already on the floor.');
      await cubit.close();
    });
  });

  group('squaring wings up', () {
    test(
      'offers the correction when the corridors are nearly parallel',
      () async {
        final cubit = await opened();

        // Wing 2's corridor was captured 3 degrees off wing 1's.
        final correction = cubit.state.snapCorrectionFor('wing-2');

        expect(correction, isNotNull);
        expect(correction! * 180 / math.pi, closeTo(-3, 0.01));
        await cubit.close();
      },
    );

    test('snapping applies it, leaving the corridors parallel', () async {
      final cubit = await opened();

      cubit.snapWing();

      expect(
        cubit.state.plan.wings['wing-2']!.rotation * 180 / math.pi,
        closeTo(-3, 0.01),
      );
      expect(cubit.state.snapCorrectionFor('wing-2')!.abs(), lessThan(1e-6));
      await cubit.close();
    });

    test('declines when the wing is nowhere near square', () async {
      final cubit = await opened();
      // Thirty degrees out is a decision, not a slip.
      cubit.rotateWing(30 * math.pi / 180);

      expect(cubit.state.snapCorrectionFor('wing-2'), isNull);

      cubit.snapWing();
      expect(cubit.state.hint, contains('No nearby corridor'));
      await cubit.close();
    });

    test('a quarter turn out still counts as aligned', () async {
      final cubit = await opened();
      // Two corridors meeting at right angles are as aligned as two parallel
      // ones — the building's grid is what matters, not the heading.
      cubit.rotateWing(math.pi / 2);

      expect(cubit.state.snapCorrectionFor('wing-2'), isNotNull);
      await cubit.close();
    });
  });

  group('aligning is not connecting', () {
    test(
      'two wings side by side are still unroutable without a door',
      () async {
        final cubit = await opened();
        cubit.nudgeWing(const Offset(-40, 0));

        // Perfectly placed on screen, and routing does not care.
        expect(cubit.state.strandedRooms, isNotEmpty);
        await cubit.close();
      },
    );

    test('joining them makes the floor one map', () async {
      final cubit = await opened();
      cubit.nudgeWing(const Offset(-40, 0));

      cubit.addDoorBetween('c1', 'c2', const Offset(20, 1));

      expect(cubit.state.strandedRooms, isEmpty);
      expect(
        RoomNavGraph.build(
          cubit.state.plan,
        ).route(fromRoomId: 'r1', toRoomId: 'c2'),
        isNotNull,
      );
      await cubit.close();
    });

    test('refuses to add a second door between the same pair', () async {
      final cubit = await opened();
      cubit.addDoorBetween('c1', 'c2', const Offset(20, 1));
      cubit.addDoorBetween('c1', 'c2', const Offset(20, 1.5));

      expect(
        cubit.state.plan.storedOpenings.where(
          (o) => o.touches('c1') && o.touches('c2'),
        ),
        hasLength(1),
      );
      await cubit.close();
    });
  });

  group('fixing what was captured', () {
    test('deleting a room takes its doors with it', () async {
      final cubit = await opened();

      cubit.deleteRoom('r1');

      expect(
        cubit.state.plan.storedRooms.map((r) => r.id),
        isNot(contains('r1')),
      );
      // An opening naming a room that no longer exists keeps counting towards
      // a corridor's declared total and skews every ordinal after it.
      expect(cubit.state.plan.storedOpenings, isEmpty);
      await cubit.close();
    });

    test('a category picked wrongly can be changed', () async {
      final cubit = await opened();

      cubit.editRoom('r1', category: RoomCategory.laboratory);

      expect(cubit.state.plan.roomOf('r1')!.category, RoomCategory.laboratory);
      await cubit.close();
    });

    test('a label can be set and cleared', () async {
      final cubit = await opened();

      cubit.editRoom('r1', label: 'Networks Lab');
      expect(cubit.state.plan.roomOf('r1')!.label, 'Networks Lab');

      cubit.editRoom('r1', label: '   ');
      expect(cubit.state.plan.roomOf('r1')!.label, isNull);
      await cubit.close();
    });
  });

  group('saving', () {
    test('writes the edited plan and clears the dirty flag', () async {
      final cubit = await opened();
      cubit.nudgeWing(const Offset(-40, 0));
      expect(cubit.state.isDirty, isTrue);

      await cubit.save();

      final saved =
          verify(() => plans.save(captureAny())).captured.single as RoomPlan;
      expect(saved.wings['wing-2']!.dx, 0);
      expect(cubit.state.status, PlanEditorStatus.saved);
      expect(cubit.state.isDirty, isFalse);
      await cubit.close();
    });

    test('a failed save keeps the edits', () async {
      when(() => plans.save(any())).thenThrow(Exception('offline'));
      final cubit = await opened();
      cubit.nudgeWing(const Offset(-40, 0));

      await cubit.save();

      expect(cubit.state.status, PlanEditorStatus.ready);
      expect(cubit.state.error, contains('still here'));
      expect(cubit.state.plan.wings['wing-2']!.dx, 0);
      await cubit.close();
    });

    test('an alignment survives a round trip through JSON', () async {
      final cubit = await opened();
      cubit.nudgeWing(const Offset(-40, 3));
      cubit.rotateWing(-0.05);

      final reloaded = RoomPlan.fromJson(cubit.state.plan.toJson());

      expect(reloaded, equals(cubit.state.plan));
      expect(reloaded.wings['wing-2']!.rotation, closeTo(-0.05, 1e-9));
      await cubit.close();
    });
  });

  group('missing connections', () {
    /// Two offices side by side sharing a wall, with a corridor along the top
    /// that neither has a door onto. The shape of every teaching building.
    PlanEditorState stateFor(List<Room> rooms) =>
        PlanEditorState(plan: RoomPlan(
          buildingId: 'b',
          floorId: 'gf',
          codePrefix: 'G',
          storedRooms: rooms,
        ));

    final officeA = rect(
      id: 'a', code: 'a', category: RoomCategory.office,
      left: 0, right: 10, bottom: 0, top: 10,
    );
    final officeB = rect(
      id: 'b', code: 'b', category: RoomCategory.office,
      left: 10, right: 20, bottom: 0, top: 10,
    );
    final corridor = rect(
      id: 'c', code: 'c', category: RoomCategory.corridor,
      left: 0, right: 20, bottom: 10, top: 13,
    );

    test('two rooms sharing a wall are not a missing door', () {
      // The suggestion this used to make. A row of offices shares a wall at
      // every boundary and has a door onto the corridor and nowhere else;
      // taking the suggestion routes somebody through a wall.
      final pairs = stateFor([officeA, officeB]).missingConnections;
      expect(pairs, isEmpty);
    });

    test('a room with no door onto the corridor beside it still is', () {
      final pairs = stateFor([officeA, officeB, corridor]).missingConnections;
      expect(pairs, isNotEmpty);
      for (final pair in pairs) {
        expect([pair.roomA, pair.roomB], contains('c'));
      }
    });
  });
}
