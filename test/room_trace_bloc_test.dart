// `show BuildingFloor`: building.dart also exports a `Room`, which is a
// directory listing rather than a shape. See room_trace_bloc.dart.
import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/room_trace/bloc/room_trace_bloc.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/mapping/plan_photo_service.dart';
import 'package:echo_locate/services/mapping/room_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockPhotos extends Mock implements PlanPhotoService {}

class _MockBuildings extends Mock implements BuildingRepository {}

void main() {
  late _MockPlans plans;
  late _MockPhotos photos;
  late _MockBuildings buildings;

  setUpAll(() => registerFallbackValue(RoomPlan.empty));

  setUp(() {
    plans = _MockPlans();
    photos = _MockPhotos();
    buildings = _MockBuildings();

    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'floor-uuid-g', label: 'G', rooms: []),
        BuildingFloor(id: 'floor-uuid-2', label: '2', rooms: []),
      ],
    );
    when(() => photos.start()).thenAnswer((_) async => true);
    when(() => photos.stop()).thenAnswer((_) async {});
    when(
      () => photos.capture(any(), any()),
    ).thenAnswer((_) async => '/tmp/board.jpg');
    when(
      () => photos.storedPhotos(any()),
    ).thenAnswer((_) async => const <String, String>{});
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);
    when(() => plans.save(any())).thenAnswer((_) async {});
    // Autosave runs on every plan change, so every test exercises it.
    when(() => plans.saveDraft(any())).thenAnswer((_) async {});
    when(() => plans.draftFor(any(), any())).thenAnswer((_) async => null);
    when(() => plans.clearDraft(any(), any())).thenAnswer((_) async {});
  });

  RoomTraceBloc build() => RoomTraceBloc(plans, photos, buildings);

  /// Starts a trace and gets past the photo step.
  Future<RoomTraceBloc> traced() async {
    final bloc = build();
    bloc.add(const RoomTraceStarted(buildingId: 'knust-cs'));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const RoomPhotoSkipped());
    await Future<void>.delayed(Duration.zero);
    return bloc;
  }

  /// Traces one axis-aligned rectangle in image coordinates and closes it.
  Future<void> traceRect(
    RoomTraceBloc bloc, {
    required double left,
    required double right,
    required double top,
    required double bottom,
    required RoomCategory category,
    String? label,
  }) async {
    for (final corner in [
      (left, top),
      (right, top),
      (right, bottom),
      (left, bottom),
    ]) {
      bloc.add(RoomCornerTapped(corner.$1, corner.$2));
    }
    await Future<void>.delayed(Duration.zero);
    bloc.add(RoomClosed(category: category, label: label));
    await Future<void>.delayed(Duration.zero);
  }

  group('starting up', () {
    test(
      'loads the building floors and files rooms under a real floor id',
      () async {
        final bloc = await traced();

        expect(bloc.state.floorId, 'floor-uuid-g');
        expect(bloc.state.floors, hasLength(2));

        await traceRect(
          bloc,
          left: 0.1,
          right: 0.4,
          top: 0.1,
          bottom: 0.3,
          category: RoomCategory.office,
        );

        expect(bloc.state.plan.rooms.single.floorId, 'floor-uuid-g');
        await bloc.close();
      },
    );

    test('reopens a part-traced floor instead of starting blank', () async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => const RoomPlan(
          buildingId: 'knust-cs',
          floorId: 'floor-uuid-g',
          codePrefix: 'GF',
          storedRooms: [
            Room(
              id: 'room-1',
              floorId: 'floor-uuid-g',
              code: 'GF 1',
              category: RoomCategory.office,
              polygon: [
                RoomCorner(x: 0, y: 0),
                RoomCorner(x: 1, y: 0),
                RoomCorner(x: 1, y: 1),
              ],
            ),
          ],
        ),
      );

      final bloc = build();
      bloc.add(const RoomTraceStarted(buildingId: 'knust-cs'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.rooms, hasLength(1));
      await bloc.close();
    });

    RoomPlan planWith(int rooms) => RoomPlan(
      buildingId: 'knust-cs',
      floorId: 'floor-uuid-g',
      codePrefix: 'GF',
      storedRooms: [
        for (var i = 0; i < rooms; i++)
          Room(
            id: 'room-$i',
            floorId: 'floor-uuid-g',
            code: 'room-$i',
            category: RoomCategory.office,
            polygon: const [
              RoomCorner(x: 0, y: 0),
              RoomCorner(x: 1, y: 0),
              RoomCorner(x: 1, y: 1),
            ],
          ),
      ],
    );

    test('a richer draft is picked up after a session that never saved',
        () async {
      // The crash case: three rooms traced, the app died before Save.
      when(() => plans.planFor(any(), any()))
          .thenAnswer((_) async => planWith(1));
      when(() => plans.draftFor(any(), any()))
          .thenAnswer((_) async => planWith(3));

      final bloc = build();
      bloc.add(const RoomTraceStarted(buildingId: 'knust-cs'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.rooms, hasLength(3));
      expect(bloc.state.warning, contains('left off'));
      await bloc.close();
    });

    test('a stale draft never eats a floor published since', () async {
      // Same floor, saved from another device with more in it. The draft is
      // older work and must not win, or syncing costs somebody their floor.
      when(() => plans.planFor(any(), any()))
          .thenAnswer((_) async => planWith(5));
      when(() => plans.draftFor(any(), any()))
          .thenAnswer((_) async => planWith(2));

      final bloc = build();
      bloc.add(const RoomTraceStarted(buildingId: 'knust-cs'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.rooms, hasLength(5));
      await bloc.close();
    });

    test('a draft that cannot be read leaves tracing working', () async {
      when(() => plans.planFor(any(), any()))
          .thenAnswer((_) async => planWith(1));
      when(() => plans.draftFor(any(), any())).thenThrow(Exception('hive'));

      final bloc = build();
      bloc.add(const RoomTraceStarted(buildingId: 'knust-cs'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.rooms, hasLength(1));
      await bloc.close();
    });

    test('a new room after a reload does not reuse an existing id', () async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => const RoomPlan(
          buildingId: 'knust-cs',
          floorId: 'floor-uuid-g',
          codePrefix: 'GF',
          storedRooms: [
            Room(
              id: 'room-7',
              floorId: 'floor-uuid-g',
              code: 'GF 7',
              category: RoomCategory.office,
              polygon: [
                RoomCorner(x: 0, y: 0),
                RoomCorner(x: 1, y: 0),
                RoomCorner(x: 1, y: 1),
              ],
            ),
          ],
        ),
      );

      final bloc = build();
      bloc.add(const RoomTraceStarted(buildingId: 'knust-cs'));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const RoomPhotoSkipped());
      await Future<void>.delayed(Duration.zero);

      await traceRect(
        bloc,
        left: 0.5,
        right: 0.8,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
      );

      final ids = bloc.state.plan.rooms.map((r) => r.id).toSet();
      expect(ids, hasLength(2));
      // The point of the test: the reloaded room's id is not handed out
      // again. Rooms are no longer numbered, so the code is the id and
      // uniqueness is the only thing left to check.
      final added = bloc.state.plan.rooms.last;
      expect(added.id, isNot('room-7'));
      expect(added.code, added.id);
      await bloc.close();
    });
  });

  group('tracing a room', () {
    test('corners accumulate and undo removes the last', () async {
      final bloc = await traced();

      bloc.add(const RoomCornerTapped(0.1, 0.1));
      bloc.add(const RoomCornerTapped(0.4, 0.1));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.draft, hasLength(2));
      expect(bloc.state.canCloseRoom, isFalse);

      bloc.add(const RoomCornerTapped(0.4, 0.3));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.canCloseRoom, isTrue);

      bloc.add(const RoomCornerUndone());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.draft, hasLength(2));

      await bloc.close();
    });

    test(
      'IMAGE v is flipped to plan y — otherwise every room is mirrored',
      () async {
        // The trap this whole layer is built around. Image v grows *downward*;
        // the plan frame is y-north. Store v unflipped and the plan is mirrored
        // about the horizontal, which looks entirely plausible on screen and
        // inverts every left and right the directions layer generates.
        final bloc = await traced();

        bloc.add(const RoomCornerTapped(0.5, 0.1)); // near the TOP of the image
        bloc.add(const RoomCornerTapped(0.5, 0.9)); // near the BOTTOM
        await Future<void>.delayed(Duration.zero);

        final top = bloc.state.draft.first;
        final bottom = bloc.state.draft.last;

        // The absolute values do not matter — the plan frame's origin is
        // arbitrary, exactly as MapNode's is. What must hold is the *ordering*:
        // higher on the image is further north, so it has the greater plan y.
        // Unflipped, this comparison reverses and the whole floor is mirrored.
        expect(top.dy, greaterThan(bottom.dy));
        // x passes straight through — only one axis is flipped.
        expect(top.dx, 0.5);

        await bloc.close();
      },
    );

    test('closing runs cleanup and normalises winding', () async {
      final bloc = await traced();

      // Traced clockwise in image terms, with a corner a few degrees out and a
      // finger slip on one wall.
      for (final corner in [
        (0.10, 0.10),
        (0.40, 0.105),
        (0.402, 0.107),
        (0.40, 0.30),
        (0.10, 0.30),
      ]) {
        bloc.add(RoomCornerTapped(corner.$1, corner.$2));
      }
      await Future<void>.delayed(Duration.zero);
      bloc.add(const RoomClosed(category: RoomCategory.office));
      await Future<void>.delayed(Duration.zero);

      final room = bloc.state.plan.rooms.single;

      expect(room.polygon, hasLength(4), reason: 'the slip should be gone');
      expect(
        signedArea(room.corners),
        greaterThan(0),
        reason: 'winding must be normalised counter-clockwise',
      );
      expect(bloc.state.draft, isEmpty);
      await bloc.close();
    });

    test('refuses a self-intersecting trace and keeps the corners', () async {
      final bloc = await traced();

      // A bowtie: opposite corners swapped.
      for (final corner in [(0.1, 0.1), (0.4, 0.3), (0.4, 0.1), (0.1, 0.3)]) {
        bloc.add(RoomCornerTapped(corner.$1, corner.$2));
      }
      await Future<void>.delayed(Duration.zero);
      bloc.add(const RoomClosed(category: RoomCategory.office));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.rooms, isEmpty);
      expect(bloc.state.warning, contains('cross'));
      // Kept, so the contributor undoes one corner rather than retracing.
      expect(bloc.state.draft, hasLength(4));
      await bloc.close();
    });

    test('refuses fewer than three corners', () async {
      final bloc = await traced();

      bloc.add(const RoomCornerTapped(0.1, 0.1));
      bloc.add(const RoomCornerTapped(0.4, 0.1));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const RoomClosed(category: RoomCategory.office));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.rooms, isEmpty);
      expect(bloc.state.warning, contains('three corners'));
      await bloc.close();
    });

    test('does not number rooms — an unnamed room is its category', () async {
      final bloc = await traced();

      await traceRect(
        bloc,
        left: 0.1,
        right: 0.3,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
      );
      await traceRect(
        bloc,
        left: 0.4,
        right: 0.6,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.laboratory,
      );

      final rooms = bloc.state.plan.rooms;
      // No allocated `GF 1` / `GF 2`: a number handed out in tracing order
      // looks like the number on the door and is nothing of the kind.
      expect(rooms.map((r) => r.code), rooms.map((r) => r.id));
      // What a person sees and hears instead, neither of them a number.
      expect(rooms.map((r) => r.displayName), ['Office', 'Laboratory']);
      expect(rooms.every((r) => r.isNamed), isFalse);
      await bloc.close();
    });

    test(
      'an empty label is stored as no label, not as an empty string',
      () async {
        final bloc = await traced();

        await traceRect(
          bloc,
          left: 0.1,
          right: 0.3,
          top: 0.1,
          bottom: 0.3,
          category: RoomCategory.office,
          label: '   ',
        );

        expect(bloc.state.plan.rooms.single.label, isNull);
        await bloc.close();
      },
    );

    test('switching mode abandons a half-traced room', () async {
      final bloc = await traced();

      bloc.add(const RoomCornerTapped(0.1, 0.1));
      bloc.add(const RoomCornerTapped(0.4, 0.1));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const RoomTraceModeChanged(RoomTraceMode.doors));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.draft, isEmpty);
      expect(bloc.state.mode, RoomTraceMode.doors);
      await bloc.close();
    });
  });

  group('placing doors', () {
    /// A corridor with two rooms above it, sharing walls.
    Future<RoomTraceBloc> wing() async {
      final bloc = await traced();
      // Corridor across the middle of the image.
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.9,
        top: 0.50,
        bottom: 0.56,
        category: RoomCategory.corridor,
      );
      // Two rooms sitting directly on top of it.
      await traceRect(
        bloc,
        left: 0.15,
        right: 0.35,
        top: 0.20,
        bottom: 0.50,
        category: RoomCategory.office,
        label: 'Room A',
      );
      await traceRect(
        bloc,
        left: 0.45,
        right: 0.65,
        top: 0.20,
        bottom: 0.50,
        category: RoomCategory.office,
        label: 'Room B',
      );
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.doors));
      await Future<void>.delayed(Duration.zero);
      return bloc;
    }

    test('joins the two rooms whose walls the tap fell between', () async {
      final bloc = await wing();

      // On the shared wall between the corridor and Room A.
      bloc.add(const RoomDoorTapped(0.25, 0.50));
      await Future<void>.delayed(Duration.zero);

      final opening = bloc.state.plan.openings.single;
      final joined = {opening.roomAId, opening.roomBId};
      final corridor = bloc.state.plan.rooms.firstWhere(
        (r) => r.category == RoomCategory.corridor,
      );
      final roomA = bloc.state.plan.rooms.firstWhere(
        (r) => r.label == 'Room A',
      );

      expect(joined, {corridor.id, roomA.id});
      expect(bloc.state.warning, isNull);
      await bloc.close();
    });

    test('a tap on an outside wall makes an exterior door', () async {
      final bloc = await wing();

      // The corridor's far left end — only the corridor borders it.
      bloc.add(const RoomDoorTapped(0.10, 0.53));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.openings.single.isExterior, isTrue);
      expect(bloc.state.warning, contains('exterior'));
      await bloc.close();
    });

    test('a tap in open space places nothing and says so', () async {
      final bloc = await wing();

      bloc.add(const RoomDoorTapped(0.05, 0.05));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.openings, isEmpty);
      expect(bloc.state.warning, contains('No wall'));
      await bloc.close();
    });

    test('refuses a second door between the same two rooms', () async {
      final bloc = await wing();

      bloc.add(const RoomDoorTapped(0.25, 0.50));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const RoomDoorTapped(0.30, 0.50));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.openings, hasLength(1));
      expect(bloc.state.warning, contains('already have a door'));
      await bloc.close();
    });

    test('deleting a room takes its doors with it', () async {
      final bloc = await wing();

      bloc.add(const RoomDoorTapped(0.25, 0.50));
      bloc.add(const RoomDoorTapped(0.55, 0.50));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.plan.openings, hasLength(2));

      final roomA = bloc.state.plan.rooms.firstWhere(
        (r) => r.label == 'Room A',
      );
      bloc.add(RoomDeleted(roomA.id));
      await Future<void>.delayed(Duration.zero);

      // An opening naming a room that no longer exists would keep counting
      // towards the corridor's declared total and quietly skew every ordinal.
      expect(bloc.state.plan.openings, hasLength(1));
      expect(
        bloc.state.plan.openings.every((o) => !o.touches(roomA.id)),
        isTrue,
      );
      await bloc.close();
    });
  });

  group('the door-count guard', () {
    test('ordinals stay unsafe until the declared count is met', () async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.9,
        top: 0.50,
        bottom: 0.56,
        category: RoomCategory.corridor,
      );
      await traceRect(
        bloc,
        left: 0.15,
        right: 0.35,
        top: 0.20,
        bottom: 0.50,
        category: RoomCategory.office,
      );
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.doors));
      await Future<void>.delayed(Duration.zero);

      final corridor = bloc.state.plan.rooms.firstWhere(
        (r) => r.category == RoomCategory.corridor,
      );

      // The contributor counts four doors by eye.
      bloc.add(CorridorDoorCountDeclared(corridorId: corridor.id, count: 4));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.ordinalsAreSafe, isFalse);
      expect(bloc.state.incompleteCorridors[corridor.id], 4);

      bloc.add(const RoomDoorTapped(0.25, 0.50));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.incompleteCorridors[corridor.id], 3);
      expect(bloc.state.ordinalsAreSafe, isFalse);

      await bloc.close();
    });

    test('a stub room stands in for a door nobody opened', () async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.9,
        top: 0.50,
        bottom: 0.56,
        category: RoomCategory.corridor,
      );

      bloc.add(const StubRoomAdded());
      await Future<void>.delayed(Duration.zero);

      final stub = bloc.state.plan.rooms.last;
      expect(stub.isStub, isTrue);
      // In the plan for counting, absent from the drawing.
      expect(
        bloc.state.plan.drawableRooms.map((r) => r.id),
        isNot(contains(stub.id)),
      );
      await bloc.close();
    });
  });

  group('reporting problems worth fixing before saving', () {
    test('names rooms with no door at all', () async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.3,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
        label: 'Sealed',
      );

      expect(bloc.state.roomsWithoutDoors.single.label, 'Sealed');
      await bloc.close();
    });
  });

  group('two wall boards, two wings', () {
    test('a second tracing session opens its own wing', () async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => const RoomPlan(
          buildingId: 'knust-cs',
          floorId: 'floor-uuid-g',
          codePrefix: 'GF',
          storedRooms: [
            Room(
              id: 'room-1',
              floorId: 'floor-uuid-g',
              code: 'GF 1',
              category: RoomCategory.office,
              wingId: 'wing-1',
              polygon: [
                RoomCorner(x: 0, y: 0),
                RoomCorner(x: 0.3, y: 0),
                RoomCorner(x: 0.3, y: 0.2),
              ],
            ),
          ],
        ),
      );

      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.4,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
      );

      // A floor with two wall boards is two photographs and two coordinate
      // frames — the same problem a second AR session has, and until now the
      // only way to reach the alignment editor was hardware nobody had.
      expect(bloc.state.plan.storedRooms.last.wingId, 'wing-2');
      expect(bloc.state.plan.wingIds, ['wing-1', 'wing-2']);
      await bloc.close();
    });

    test('the new wing is parked clear of the first', () async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => const RoomPlan(
          buildingId: 'knust-cs',
          floorId: 'floor-uuid-g',
          codePrefix: 'GF',
          storedRooms: [
            Room(
              id: 'room-1',
              floorId: 'floor-uuid-g',
              code: 'GF 1',
              category: RoomCategory.office,
              wingId: 'wing-1',
              polygon: [
                RoomCorner(x: 0, y: 0),
                RoomCorner(x: 0.3, y: 0),
                RoomCorner(x: 0.3, y: 0.2),
              ],
            ),
          ],
        ),
      );

      final bloc = await traced();

      expect(
        bloc.state.plan.wings['wing-2']!.dx,
        closeTo(0.3 + RoomTraceBloc.parkingGapUnits, 0.001),
      );
      await bloc.close();
    });

    test('the first wing on an empty floor is not parked', () async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.4,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
      );

      expect(bloc.state.plan.hasWingPlacements, isFalse);
      expect(bloc.state.plan.storedRooms.single.wingId, 'wing-1');
      await bloc.close();
    });

    test('refuses to trace onto a floor scanned in AR', () async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => const RoomPlan(
          buildingId: 'knust-cs',
          floorId: 'floor-uuid-g',
          codePrefix: 'GF',
          metresPerUnit: 1,
          storedRooms: [
            Room(
              id: 'room-1',
              floorId: 'floor-uuid-g',
              code: 'GF 1',
              category: RoomCategory.office,
              polygon: [
                RoomCorner(x: 0, y: 0),
                RoomCorner(x: 4, y: 0),
                RoomCorner(x: 4, y: 3),
              ],
            ),
          ],
        ),
      );

      final bloc = build();
      bloc.add(const RoomTraceStarted(buildingId: 'knust-cs'));
      await Future<void>.delayed(Duration.zero);

      // Metres and image fractions are about fifty times apart; the mirror of
      // the guard AR capture applies to traced floors.
      expect(bloc.state.error, contains('scanned in AR'));
      await bloc.close();
    });
  });

  group('squaring the board up', () {
    /// The board as photographed from below: its far edge shorter than its
    /// near one, which is what every hand-held shot of a wall looks like.
    const keystoned = [(0.25, 0.10), (0.75, 0.10), (0.90, 0.70), (0.10, 0.70)];

    Future<RoomTraceBloc> squared() async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.board));
      for (final corner in keystoned) {
        bloc.add(BoardCornerTapped(corner.$1, corner.$2));
      }
      await Future<void>.delayed(Duration.zero);
      return bloc;
    }

    test(
      'four corners produce a correction and switch back to rooms',
      () async {
        final bloc = await squared();

        expect(bloc.state.isRectified, isTrue);
        expect(bloc.state.mode, RoomTraceMode.rooms);
        await bloc.close();
      },
    );

    test('a room traced after squaring up is not skewed', () async {
      final bloc = await squared();

      // Where a rectangle on the board actually appears in the photograph.
      final onPhoto = [
        for (final corner in const [
          Offset(0.2, 0.15),
          Offset(0.6, 0.15),
          Offset(0.6, 0.45),
          Offset(0.2, 0.45),
        ])
          bloc.state.rectification.invert(corner),
      ];

      for (final point in onPhoto) {
        bloc.add(RoomCornerTapped(point.dx, point.dy));
      }
      await Future<void>.delayed(Duration.zero);
      bloc.add(const RoomClosed(category: RoomCategory.office));
      await Future<void>.delayed(Duration.zero);

      final room = bloc.state.plan.rooms.single;
      final box = room.bounds;
      // 0.4 wide by 0.3 tall on the board. Traced without the correction the
      // room would come out a trapezium and the bounds would be wrong.
      expect(box.width, closeTo(0.4, 0.01));
      expect(box.height, closeTo(0.3, 0.01));
      await bloc.close();
    });

    test('corners tapped in the wrong order are refused', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.board));
      for (final corner in const [
        (0.1, 0.1),
        (0.9, 0.7),
        (0.9, 0.1),
        (0.1, 0.7),
      ]) {
        bloc.add(BoardCornerTapped(corner.$1, corner.$2));
      }
      await Future<void>.delayed(Duration.zero);

      // A bowtie folds the plan over rather than merely distorting it.
      expect(bloc.state.isRectified, isFalse);
      expect(bloc.state.boardCorners, isEmpty);
      expect(bloc.state.warning, contains('cross over'));
      await bloc.close();
    });

    test('warns when the photo is too oblique to trust', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.board));
      // Far edge a third of the near one.
      for (final corner in const [
        (0.40, 0.1),
        (0.60, 0.1),
        (0.95, 0.7),
        (0.05, 0.7),
      ]) {
        bloc.add(BoardCornerTapped(corner.$1, corner.$2));
      }
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.isRectified, isTrue);
      expect(bloc.state.warning, contains('oblique'));
      await bloc.close();
    });

    test('undo removes the last corner', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.board));
      bloc.add(const BoardCornerTapped(0.1, 0.1));
      bloc.add(const BoardCornerTapped(0.9, 0.1));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const BoardCornerUndone());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.boardCorners, hasLength(1));
      await bloc.close();
    });

    test('clearing says rooms already traced keep their shape', () async {
      final bloc = await squared();
      await traceRect(
        bloc,
        left: 0.2,
        right: 0.4,
        top: 0.2,
        bottom: 0.4,
        category: RoomCategory.office,
      );

      bloc.add(const BoardRectificationCleared());
      await Future<void>.delayed(Duration.zero);

      // Not an undo — silently re-projecting placed rooms would move ones the
      // contributor was happy with.
      expect(bloc.state.isRectified, isFalse);
      expect(bloc.state.plan.rooms, hasLength(1));
      expect(bloc.state.warning, contains('keep their shape'));
      await bloc.close();
    });
  });

  group('setting the scale', () {
    test('two points and a distance make the plan metric', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.scale));
      // Half the plan's width apart.
      bloc.add(const ScalePointTapped(0.2, 0.5));
      bloc.add(const ScalePointTapped(0.7, 0.5));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const ScaleDeclared(10));
      await Future<void>.delayed(Duration.zero);

      // Until this a traced plan is unitless and guidance withholds every
      // distance, because a number invented from fractions of a photograph is
      // a confidently wrong number in a blind user's ear.
      expect(bloc.state.hasScale, isTrue);
      expect(bloc.state.plan.metresPerUnit, closeTo(20, 0.01));
      expect(bloc.state.mode, RoomTraceMode.rooms);
      await bloc.close();
    });

    test('a traced room then has a real area', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.scale));
      bloc.add(const ScalePointTapped(0.0, 0.5));
      bloc.add(const ScalePointTapped(1.0, 0.5));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const ScaleDeclared(20));
      await Future<void>.delayed(Duration.zero);

      await traceRect(
        bloc,
        left: 0.1,
        right: 0.3,
        top: 0.1,
        bottom: 0.25,
        category: RoomCategory.office,
      );

      // 0.2 x 0.15 plan units at 20 m per unit is 4 m by 3 m.
      final room = bloc.state.plan.rooms.single;
      expect(
        room.bounds.width * bloc.state.plan.metresPerUnit!,
        closeTo(4, 0.05),
      );
      await bloc.close();
    });

    test('needs both ends before a distance means anything', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.scale));
      bloc.add(const ScalePointTapped(0.2, 0.5));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const ScaleDeclared(10));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.hasScale, isFalse);
      expect(bloc.state.warning, contains('both ends'));
      await bloc.close();
    });

    test('refuses two points in the same place', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.scale));
      bloc.add(const ScalePointTapped(0.5, 0.5));
      bloc.add(const ScalePointTapped(0.5, 0.5));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const ScaleDeclared(10));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.hasScale, isFalse);
      expect(bloc.state.warning, contains('same place'));
      await bloc.close();
    });

    test('refuses a distance of zero', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.scale));
      bloc.add(const ScalePointTapped(0.2, 0.5));
      bloc.add(const ScalePointTapped(0.7, 0.5));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const ScaleDeclared(0));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.hasScale, isFalse);
      await bloc.close();
    });

    test('a third tap starts a fresh span', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.scale));
      bloc.add(const ScalePointTapped(0.2, 0.5));
      bloc.add(const ScalePointTapped(0.7, 0.5));
      bloc.add(const ScalePointTapped(0.3, 0.3));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.scalePoints, hasLength(1));
      await bloc.close();
    });

    test('clearing puts the plan back to unitless', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.scale));
      bloc.add(const ScalePointTapped(0.2, 0.5));
      bloc.add(const ScalePointTapped(0.7, 0.5));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const ScaleDeclared(10));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const ScaleCleared());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.hasScale, isFalse);
      await bloc.close();
    });
  });

  group('snapping to existing corners', () {
    test('a tap near a placed corner lands exactly on it', () async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.4,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
      );

      final placed = bloc.state.plan.rooms.single.corners;
      // The room next door, starting a hair off the shared corner.
      bloc.add(const RoomCornerTapped(0.4 + 0.003, 0.3 - 0.003));
      await Future<void>.delayed(Duration.zero);

      // Adjacent rooms otherwise end up with walls that *nearly* coincide,
      // which is worse than either alternative — door inference has to guess
      // and the missing-connection check sees a gap where there is a wall.
      expect(
        placed.any(
          (corner) => (corner - bloc.state.draft.single).distance < 1e-9,
        ),
        isTrue,
      );
      await bloc.close();
    });

    test('a tap well clear of everything is left alone', () async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.4,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
      );

      bloc.add(const RoomCornerTapped(0.8, 0.8));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.draft.single, const Offset(0.8, -0.8));
      await bloc.close();
    });

    test('closing back onto the first corner is exact', () async {
      final bloc = await traced();
      bloc.add(const RoomCornerTapped(0.1, 0.1));
      bloc.add(const RoomCornerTapped(0.4, 0.1));
      bloc.add(const RoomCornerTapped(0.4, 0.3));
      await Future<void>.delayed(Duration.zero);
      // A hair off where the trace began.
      bloc.add(const RoomCornerTapped(0.1 + 0.002, 0.1 + 0.002));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.draft.last, bloc.state.draft.first);
      await bloc.close();
    });
  });

  group('saving', () {
    test('sends the plan and reports saved', () async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.3,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
      );

      bloc.add(const RoomTraceSaved());
      await Future<void>.delayed(Duration.zero);

      final captured =
          verify(() => plans.save(captureAny())).captured.single as RoomPlan;
      expect(captured.rooms, hasLength(1));
      expect(captured.buildingId, 'knust-cs');
      expect(bloc.state.stage, RoomTraceStage.saved);
      await bloc.close();
    });

    test(
      'a traced plan is saved unitless, so nothing speaks fake metres',
      () async {
        final bloc = await traced();
        await traceRect(
          bloc,
          left: 0.1,
          right: 0.3,
          top: 0.1,
          bottom: 0.3,
          category: RoomCategory.office,
        );

        bloc.add(const RoomTraceSaved());
        await Future<void>.delayed(Duration.zero);

        final captured =
            verify(() => plans.save(captureAny())).captured.single as RoomPlan;
        expect(captured.metresPerUnit, isNull);
        expect(captured.isMetric, isFalse);
        await bloc.close();
      },
    );

    test('refuses to save nothing', () async {
      final bloc = await traced();

      bloc.add(const RoomTraceSaved());
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => plans.save(any()));
      expect(bloc.state.error, contains('at least one room'));
      await bloc.close();
    });

    test('a failed save keeps the work and says so', () async {
      when(() => plans.save(any())).thenThrow(Exception('offline'));

      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.3,
        top: 0.1,
        bottom: 0.3,
        category: RoomCategory.office,
      );

      bloc.add(const RoomTraceSaved());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.stage, RoomTraceStage.trace);
      expect(bloc.state.error, contains('still here'));
      expect(bloc.state.plan.rooms, hasLength(1));
      await bloc.close();
    });
  });

  group('the traced plan feeds the layers already built', () {
    test('routes between two rooms off a traced corridor', () async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.9,
        top: 0.50,
        bottom: 0.56,
        category: RoomCategory.corridor,
      );
      await traceRect(
        bloc,
        left: 0.15,
        right: 0.35,
        top: 0.20,
        bottom: 0.50,
        category: RoomCategory.office,
        label: 'Room A',
      );
      await traceRect(
        bloc,
        left: 0.45,
        right: 0.65,
        top: 0.20,
        bottom: 0.50,
        category: RoomCategory.office,
        label: 'Room B',
      );

      bloc.add(const RoomTraceModeChanged(RoomTraceMode.doors));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const RoomDoorTapped(0.25, 0.50));
      bloc.add(const RoomDoorTapped(0.55, 0.50));
      await Future<void>.delayed(Duration.zero);

      final rooms = bloc.state.plan.rooms;
      final a = rooms.firstWhere((r) => r.label == 'Room A');
      final b = rooms.firstWhere((r) => r.label == 'Room B');

      final route = bloc.graph.route(fromRoomId: a.id, toRoomId: b.id);

      expect(route, isNotNull);
      expect(route!.roomsPassed.length, 3);
      await bloc.close();
    });
  });

  group('drawing a hallway as a path', () {
    /// Taps along the middle of a hallway and finishes it.
    Future<void> drawHall(
      RoomTraceBloc bloc,
      List<(double, double)> points, {
      String? label,
    }) async {
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.corridor));
      await Future<void>.delayed(Duration.zero);
      for (final point in points) {
        bloc.add(HallPointTapped(point.$1, point.$2));
      }
      await Future<void>.delayed(Duration.zero);
      bloc.add(CorridorPathClosed(label: label));
      await Future<void>.delayed(Duration.zero);
    }

    test('stores the tapped line and generates an outline around it', () async {
      final bloc = await traced();
      await drawHall(bloc, [(0.1, 0.5), (0.9, 0.5)], label: 'Main');

      final hall = bloc.state.plan.rooms.single;
      expect(hall.category, RoomCategory.corridor);
      expect(hall.label, 'Main');
      expect(hall.hasSpine, isTrue);
      expect(hall.centreline, hasLength(2));
      // Generated, not tapped: two taps could never enclose anything.
      expect(hall.polygon.length, greaterThanOrEqualTo(4));
      expect(hall.isStub, isFalse);
      await bloc.close();
    });

    test('the centreline lies inside the corridor it generated', () async {
      final bloc = await traced();
      await drawHall(bloc, [(0.1, 0.5), (0.9, 0.5)]);

      final hall = bloc.state.plan.rooms.single;
      final spine = hall.spine;

      // Midpoints, not the vertices: the two ends of the centreline sit exactly
      // on the ribbon's end caps by construction, and whether a strict ray-cast
      // calls a point on the boundary "inside" is a coin toss. What has to hold
      // is that the line between them runs down the corridor.
      for (var i = 0; i + 1 < spine.length; i++) {
        expect(
          containsPoint(hall.corners, (spine[i] + spine[i + 1]) / 2),
          isTrue,
        );
      }
      await bloc.close();
    });

    test('an L-shaped hall keeps its bend', () async {
      final bloc = await traced();
      await drawHall(bloc, [(0.1, 0.5), (0.8, 0.5), (0.8, 0.1)]);

      expect(bloc.state.plan.rooms.single.centreline, hasLength(3));
      await bloc.close();
    });

    test('refuses a single tap — a line needs two ends', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.corridor));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const HallPointTapped(0.5, 0.5));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CorridorPathClosed());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.rooms, isEmpty);
      expect(bloc.state.warning, contains('at least two points'));
      await bloc.close();
    });

    test('taps in the same place do not become a corridor', () async {
      final bloc = await traced();
      await drawHall(bloc, [(0.5, 0.5), (0.5001, 0.5), (0.5002, 0.5)]);

      expect(bloc.state.plan.rooms, isEmpty);
      expect(bloc.state.warning, contains('same place'));
      await bloc.close();
    });

    test(
      'routing between rooms off it follows the line, not the walls',
      () async {
        final bloc = await traced();
        // A hall along the middle, with a room either side of it.
        await drawHall(bloc, [(0.1, 0.5), (0.9, 0.5)]);
        await traceRect(
          bloc,
          left: 0.15,
          right: 0.35,
          top: 0.20,
          bottom: 0.49,
          category: RoomCategory.office,
          label: 'Room A',
        );
        await traceRect(
          bloc,
          left: 0.60,
          right: 0.80,
          top: 0.20,
          bottom: 0.49,
          category: RoomCategory.office,
          label: 'Room B',
        );

        bloc.add(const RoomTraceModeChanged(RoomTraceMode.doors));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const RoomDoorTapped(0.25, 0.495));
        bloc.add(const RoomDoorTapped(0.70, 0.495));
        await Future<void>.delayed(Duration.zero);

        final rooms = bloc.state.plan.rooms;
        final a = rooms.firstWhere((r) => r.label == 'Room A');
        final b = rooms.firstWhere((r) => r.label == 'Room B');
        final route = bloc.graph.route(fromRoomId: a.id, toRoomId: b.id);

        expect(route, isNotNull);
        expect(route!.roomsPassed.length, 3);
        // The drawn line has more points than the decision points, because it
        // was expanded along the hall's centreline.
        expect(
          route.polyline.length,
          greaterThanOrEqualTo(route.waypoints.length),
        );
        await bloc.close();
      },
    );
  });

  group('hallways run between rooms, not through them', () {
    /// Two rooms with a 0.02-wide gap between them at y = 0.5 — a corridor,
    /// drawn the way a wall board draws one.
    Future<RoomTraceBloc> withTwoRooms() async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.9,
        top: 0.20,
        bottom: 0.49,
        category: RoomCategory.office,
        label: 'North',
      );
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.9,
        top: 0.51,
        bottom: 0.80,
        category: RoomCategory.office,
        label: 'South',
      );
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.corridor));
      await Future<void>.delayed(Duration.zero);
      return bloc;
    }

    test('a hall tap does not snap onto the room corners either side', () async {
      // The bug: hall points used the room-corner rule, which exists so two
      // rooms end up sharing a wall. A corridor has room corners within
      // snapping distance on *both* sides for its whole length, so every tap
      // was dragged into whichever room it was passing and the hall came out
      // threaded through the offices.
      final bloc = await withTwoRooms();

      // Just inside the gap, and well within cornerSnapRadius of the corner at
      // (0.1, 0.49).
      bloc.add(const HallPointTapped(0.105, 0.5));
      await Future<void>.delayed(Duration.zero);

      final placed = bloc.state.draft.single;
      expect(placed.dx, closeTo(0.105, 1e-9));
      expect(placed.dy, closeTo(-0.5, 1e-9));
      await bloc.close();
    });

    test('says so when a leg cuts straight through a room', () async {
      final bloc = await withTwoRooms();

      bloc.add(const HallPointTapped(0.2, 0.5));
      await Future<void>.delayed(Duration.zero);
      // Diagonally across the north room rather than along the gap.
      bloc.add(const HallPointTapped(0.8, 0.25));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.warning, contains('runs through'));
      expect(bloc.state.warning, contains('North'));
      // Warned, not refused: the point is still placed so Undo is the fix.
      expect(bloc.state.draft, hasLength(2));
      await bloc.close();
    });

    test('a leg down the gap between them is not complained about', () async {
      final bloc = await withTwoRooms();

      bloc.add(const HallPointTapped(0.2, 0.5));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const HallPointTapped(0.8, 0.5));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.warning, isNull);
      await bloc.close();
    });
  });

  group('hallways join each other', () {
    test('a tap on an existing hall snaps onto its centreline', () async {
      final bloc = await traced();
      // A hall east–west across the middle.
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.corridor));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const HallPointTapped(0.1, 0.5));
      bloc.add(const HallPointTapped(0.9, 0.5));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CorridorPathClosed(label: 'Main'));
      await Future<void>.delayed(Duration.zero);

      // A second hall starting a whisker off the first.
      bloc.add(const HallPointTapped(0.5, 0.505));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.draft.single.dy, closeTo(-0.5, 1e-6));
      expect(bloc.state.warning, contains('Joined to'));
      await bloc.close();
    });

    test('a T-junction becomes a real connection in the graph', () async {
      // Without this a floor's halls are separate lines whose polygons happen
      // to overlap: routing from one to the other returns null and the floor
      // reads "not joined up" with nothing on screen to explain it.
      final bloc = await traced();

      bloc.add(const RoomTraceModeChanged(RoomTraceMode.corridor));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const HallPointTapped(0.1, 0.5));
      bloc.add(const HallPointTapped(0.9, 0.5));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CorridorPathClosed(label: 'Main'));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const HallPointTapped(0.5, 0.5));
      bloc.add(const HallPointTapped(0.5, 0.9));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CorridorPathClosed(label: 'Spur'));
      await Future<void>.delayed(Duration.zero);

      final main = bloc.state.plan.rooms.firstWhere((r) => r.label == 'Main');
      final spur = bloc.state.plan.rooms.firstWhere((r) => r.label == 'Spur');

      expect(bloc.state.warning, contains('joined to 1'));
      expect(
        bloc.state.plan.openings.any(
          (o) => o.touches(main.id) && o.touches(spur.id),
        ),
        isTrue,
      );
      expect(
        bloc.graph.route(fromRoomId: spur.id, toRoomId: main.id),
        isNotNull,
      );
      await bloc.close();
    });

    test('two halls that never meet are left unjoined', () async {
      final bloc = await traced();

      bloc.add(const RoomTraceModeChanged(RoomTraceMode.corridor));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const HallPointTapped(0.1, 0.2));
      bloc.add(const HallPointTapped(0.9, 0.2));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CorridorPathClosed(label: 'North'));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const HallPointTapped(0.1, 0.8));
      bloc.add(const HallPointTapped(0.9, 0.8));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CorridorPathClosed(label: 'South'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.plan.openings, isEmpty);
      await bloc.close();
    });
  });

  group('marking stairs', () {
    Future<RoomTraceBloc> withCorridor() async {
      final bloc = await traced();
      await traceRect(
        bloc,
        left: 0.1,
        right: 0.9,
        top: 0.50,
        bottom: 0.60,
        category: RoomCategory.corridor,
        label: 'Main',
      );
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.stairs));
      await Future<void>.delayed(Duration.zero);
      return bloc;
    }

    test('one tap leaves a staircase on the plan', () async {
      final bloc = await withCorridor();
      bloc.add(const StairsTapped(0.5, 0.55));
      await Future<void>.delayed(Duration.zero);

      final stairs = bloc.state.verticalLinks.single;
      expect(stairs.category, RoomCategory.staircase);
      // A marker with a real square, so it draws and can hold a door.
      expect(stairs.polygon, hasLength(4));
      expect(stairs.isStub, isFalse);
      await bloc.close();
    });

    test('joins itself to whatever it landed in', () async {
      // The point of the mode. A staircase nobody connected is drawn on the
      // plan and unreachable in the graph.
      final bloc = await withCorridor();
      bloc.add(const StairsTapped(0.5, 0.55));
      await Future<void>.delayed(Duration.zero);

      final stairs = bloc.state.verticalLinks.single;
      final corridor = bloc.state.plan.rooms.firstWhere(
        (r) => r.label == 'Main',
      );

      expect(bloc.state.plan.openingsOn(stairs.id), hasLength(1));
      expect(bloc.graph.reachableRooms(corridor.id), contains(stairs.id));
      await bloc.close();
    });

    test('says so when there is nothing to join it to', () async {
      final bloc = await traced();
      bloc.add(const RoomTraceModeChanged(RoomTraceMode.stairs));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const StairsTapped(0.5, 0.55));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.verticalLinks, hasLength(1));
      expect(bloc.state.plan.openings, isEmpty);
      expect(bloc.state.warning, contains('nothing is next to them'));
      await bloc.close();
    });

    test('a lift is marked the same way and listed alongside', () async {
      final bloc = await withCorridor();
      bloc.add(const StairsTapped(0.3, 0.55));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const StairsTapped(0.7, 0.55, category: RoomCategory.elevator));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.verticalLinks, hasLength(2));
      expect(
        bloc.state.verticalLinks.map((r) => r.category),
        containsAll([RoomCategory.staircase, RoomCategory.elevator]),
      );
      await bloc.close();
    });

    test('deleting a mis-tapped marker takes its door with it', () async {
      final bloc = await withCorridor();
      bloc.add(const StairsTapped(0.5, 0.55));
      await Future<void>.delayed(Duration.zero);

      bloc.add(RoomDeleted(bloc.state.verticalLinks.single.id));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.verticalLinks, isEmpty);
      // An opening naming a room that no longer exists is the orphan that
      // keeps counting towards a corridor's declared door total.
      expect(bloc.state.plan.openings, isEmpty);
      await bloc.close();
    });
  });
}
