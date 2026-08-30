import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/services/mapping/room_directions.dart';
import 'package:echo_locate/services/mapping/room_graph.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic wing, laid out so every expected answer can be read off by eye.
///
///                north rooms (left when walking east)
///        n1 @ x4      n2 @ x8      n3 @ x12
///   ┌──────┬──────────┬────────────┬─────────────┐
///   │lobby ▓  corridor, 20 m long, 2 m wide      │   y = +1 wall
///   └──────┴────┬─────────────┬──────────────────┘   y = -1 wall
///        s1 @ x6         s2 @ x14
///                south rooms (right when walking east)
///
/// Doors sit on the corridor walls at the x marked. The lobby's door is at the
/// west end, x = 0, which is where a walker enters.
Room rectRoom({
  required String id,
  required String code,
  required RoomCategory category,
  required double left,
  required double right,
  required double bottom,
  required double top,
  String? label,
}) => Room(
  id: id,
  floorId: 'gf',
  code: code,
  category: category,
  label: label,
  polygon: [
    RoomCorner(x: left, y: bottom),
    RoomCorner(x: right, y: bottom),
    RoomCorner(x: right, y: top),
    RoomCorner(x: left, y: top),
  ],
);

Opening doorAt({
  required String id,
  required String roomA,
  String? roomB,
  required double x,
  required double y,
}) => Opening(
  id: id,
  roomAId: roomA,
  roomBId: roomB,
  at: RoomCorner(x: x, y: y),
);

/// [extraStubDoor] adds a door at x = 2 on the north wall leading to a room
/// nobody traced — the §6.3 case.
RoomPlan buildWing({bool declareDoors = true, bool extraStubDoor = false}) {
  final rooms = <Room>[
    rectRoom(
      id: 'corridor',
      code: 'GF 0',
      category: RoomCategory.corridor,
      left: 0,
      right: 20,
      bottom: -1,
      top: 1,
    ),
    rectRoom(
      id: 'lobby',
      code: 'GF 1',
      category: RoomCategory.commonRoom,
      label: 'Lobby',
      left: -6,
      right: 0,
      bottom: -1,
      top: 1,
    ),
    rectRoom(
      id: 'n1',
      code: 'GF 2',
      category: RoomCategory.office,
      left: 3,
      right: 5,
      bottom: 1,
      top: 6,
    ),
    rectRoom(
      id: 'n2',
      code: 'GF 3',
      category: RoomCategory.office,
      label: 'Digital Forensic Office',
      left: 7,
      right: 9,
      bottom: 1,
      top: 6,
    ),
    rectRoom(
      id: 'n3',
      code: 'GF 4',
      category: RoomCategory.laboratory,
      left: 11,
      right: 13,
      bottom: 1,
      top: 6,
    ),
    rectRoom(
      id: 's1',
      code: 'GF 5',
      category: RoomCategory.office,
      left: 5,
      right: 7,
      bottom: -6,
      top: -1,
    ),
    rectRoom(
      id: 's2',
      code: 'GF 6',
      category: RoomCategory.washroom,
      left: 13,
      right: 15,
      bottom: -6,
      top: -1,
    ),
    if (extraStubDoor) Room.stub(id: 'untraced', floorId: 'gf', code: 'GF 7'),
  ];

  final openings = <Opening>[
    doorAt(id: 'd-lobby', roomA: 'corridor', roomB: 'lobby', x: 0, y: 0),
    doorAt(id: 'd-n1', roomA: 'corridor', roomB: 'n1', x: 4, y: 1),
    doorAt(id: 'd-n2', roomA: 'corridor', roomB: 'n2', x: 8, y: 1),
    doorAt(id: 'd-n3', roomA: 'corridor', roomB: 'n3', x: 12, y: 1),
    doorAt(id: 'd-s1', roomA: 'corridor', roomB: 's1', x: 6, y: -1),
    doorAt(id: 'd-s2', roomA: 'corridor', roomB: 's2', x: 14, y: -1),
    if (extraStubDoor)
      doorAt(id: 'd-stub', roomA: 'corridor', roomB: 'untraced', x: 2, y: 1),
  ];

  return RoomPlan(
    buildingId: 'knust-cs',
    floorId: 'gf',
    codePrefix: 'GF',
    storedRooms: rooms,
    storedOpenings: openings,
    declaredDoorCounts: declareDoors ? {'corridor': openings.length} : const {},
  );
}

String joined(List<RoomInstruction> instructions) =>
    instructions.map((i) => i.text).join(' ');

void main() {
  const east = Offset(1, 0);
  const west = Offset(-1, 0);
  const directions = RoomDirections(metresPerUnit: 1);

  group('graph structure', () {
    test('routes from the lobby to a room off the corridor', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2');

      expect(route, isNotNull);
      // The lobby is not on the list any more: the walk starts at its door, so
      // the lobby is where the walker *is*, not somewhere they cross. The
      // destination stays on the end even though it is only reached at its
      // threshold — the last leg has to have somewhere to be going.
      expect(route!.roomsPassed, ['corridor', 'n2']);

      // THE POINT: door to door. Two waypoints, both openings, and no room
      // centre at either end.
      expect(route.waypoints.length, 2);
      expect(route.waypoints.first.openingId, 'd-lobby');
      expect(route.waypoints.last.openingId, 'd-n2');
      // Their *roles* survive the move, which is what keeps the last spoken
      // sentence naming the room rather than the door in it.
      expect(route.waypoints.first.kind, WaypointKind.start);
      expect(route.waypoints.last.kind, WaypointKind.destination);
      expect(route.waypoints.first.roomId, 'lobby');
      expect(route.waypoints.last.roomId, 'n2');
    });

    test('distance is door to door, not centroid to centroid', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n3')!;

      // The corridor and nothing else: (0,0) → (12,1) is ~12.04. The 3 m from
      // the lobby's middle to its door and the 2.5 m from n3's door into n3
      // are both gone, because neither is a walk anybody needs directions for.
      expect(route.totalDistanceM, closeTo(12.04, 0.05));

      // A centroid graph would have quoted lobby→corridor→n3, which is
      // 10 + 10.6 = 20.6 — down a line nobody walks.
      expect(route.totalDistanceM, lessThan(19));
    });

    test('two rooms sharing one door keep their room nodes', () {
      // The one shape where door-to-door has nothing left to draw: trimming
      // both ends leaves a single point, which is not a line and cannot be
      // walked. The untrimmed route stands instead — see
      // RoomNavGraph._doorToDoor — because a degenerate route would read
      // downstream as "these rooms are not connected", which is a lie about a
      // pair of rooms with a door between them.
      final plan = RoomPlan(
        buildingId: 'b1',
        floorId: 'gf',
        codePrefix: 'GF',
        storedRooms: [
          rectRoom(
            id: 'a',
            code: 'GF 1',
            category: RoomCategory.office,
            label: 'Room A',
            left: 0,
            right: 4,
            bottom: 0,
            top: 4,
          ),
          rectRoom(
            id: 'b',
            code: 'GF 2',
            category: RoomCategory.office,
            label: 'Room B',
            left: 4,
            right: 8,
            bottom: 0,
            top: 4,
          ),
        ],
        storedOpenings: [
          doorAt(id: 'd-ab', roomA: 'a', roomB: 'b', x: 4, y: 2),
        ],
      );

      final route = RoomNavGraph.build(plan).route(
        fromRoomId: 'a',
        toRoomId: 'b',
      );

      expect(route, isNotNull);
      expect(route!.isEmpty, isFalse);
      // The pre-door-to-door shape, kept whole: across A, through the shared
      // door, into B.
      expect(route.roomsPassed, ['a', 'b']);
      expect(route.waypoints, hasLength(3));
      expect(route.waypoints.last.roomId, 'b');
    });

    test('a stub room has no node and never asks for its own centroid', () {
      final graph = RoomNavGraph.build(buildWing(extraStubDoor: true));

      expect(graph.positionOf(RoomNavGraph.roomNode('untraced')), isNull);
      // Its door is in the graph regardless — that is what stubs are for.
      expect(graph.positionOf(RoomNavGraph.openingNode('d-stub')), isNotNull);
      expect(graph.route(fromRoomId: 'lobby', toRoomId: 'untraced'), isNull);
    });

    test('an unconnected room is reported, not crashed on', () {
      final plan = buildWing().copyWith(
        storedRooms: [
          ...buildWing().rooms,
          rectRoom(
            id: 'orphan',
            code: 'GF 9',
            category: RoomCategory.office,
            left: 30,
            right: 34,
            bottom: 0,
            top: 4,
          ),
        ],
      );
      final graph = RoomNavGraph.build(plan);

      expect(graph.route(fromRoomId: 'lobby', toRoomId: 'orphan'), isNull);
      expect(graph.unreachableFrom('lobby'), contains('orphan'));
      expect(graph.unreachableFrom('lobby'), isNot(contains('n2')));
    });

    test('corridor shape and door count identify circulation', () {
      final plan = buildWing();

      expect(
        RoomNavGraph.looksLikeCorridor(plan.roomOf('corridor')!, plan),
        isTrue,
      );
      expect(RoomNavGraph.looksLikeCorridor(plan.roomOf('n2')!, plan), isFalse);
    });
  });

  group('door counting — the instruction that can send somebody wrong', () {
    test('names the second door on the LEFT walking east', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2')!;
      final spoken = joined(
        directions.describe(graph, route, initialHeading: east),
      );

      // Walking east, north is on the left. n1 (x=4) then n2 (x=8).
      expect(spoken, contains('second door on your left'));
      expect(spoken, contains('Digital Forensic Office'));
    });

    test('names the FIRST door on the left for the nearer room', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n1')!;

      expect(
        joined(directions.describe(graph, route, initialHeading: east)),
        contains('first door on your left'),
      );
    });

    test('south rooms are on the RIGHT walking east', () {
      final graph = RoomNavGraph.build(buildWing());

      expect(
        joined(
          directions.describe(
            graph,
            graph.route(fromRoomId: 'lobby', toRoomId: 's1')!,
            initialHeading: east,
          ),
        ),
        contains('first door on your right'),
      );
      expect(
        joined(
          directions.describe(
            graph,
            graph.route(fromRoomId: 'lobby', toRoomId: 's2')!,
            initialHeading: east,
          ),
        ),
        contains('second door on your right'),
      );
    });

    test('walking WEST swaps every side', () {
      final graph = RoomNavGraph.build(buildWing());
      // Setting off from the washroom at the east end and walking back west,
      // the north wall is now on the right — and n1 is the third door along it,
      // behind n3 and n2.
      final route = graph.route(fromRoomId: 's2', toRoomId: 'n1')!;
      final spoken = joined(
        directions.describe(graph, route, initialHeading: west),
      );

      expect(spoken, contains('third door on your right'));
      expect(spoken, isNot(contains('on your left')));
    });

    test('the same door is a different ordinal from each direction', () {
      // Nothing about the building changed; only the walker's heading did.
      // A map that answers this the same way both times is wrong one of them.
      final graph = RoomNavGraph.build(buildWing());

      expect(
        joined(
          directions.describe(
            graph,
            graph.route(fromRoomId: 'lobby', toRoomId: 'n1')!,
            initialHeading: east,
          ),
        ),
        contains('first door on your left'),
      );
      expect(
        joined(
          directions.describe(
            graph,
            graph.route(fromRoomId: 's2', toRoomId: 'n1')!,
            initialHeading: west,
          ),
        ),
        contains('third door on your right'),
      );
    });

    test('an untagged door shifts every ordinal after it — §6.3', () {
      // The same building, with one extra door on the north wall at x = 2
      // leading somewhere nobody traced. n1 is now the *second* door on the
      // left, not the first. This is the failure the spec warns about, and the
      // reason stub rooms are carried in the graph at all.
      final withStub = RoomNavGraph.build(buildWing(extraStubDoor: true));
      final route = withStub.route(fromRoomId: 'lobby', toRoomId: 'n1')!;

      expect(
        joined(directions.describe(withStub, route, initialHeading: east)),
        contains('second door on your left'),
      );
    });

    test('refuses to count when the corridor is not declared complete', () {
      final graph = RoomNavGraph.build(buildWing(declareDoors: false));
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2')!;
      final spoken = joined(
        directions.describe(graph, route, initialHeading: east),
      );

      // Silence about ordinals is the honest failure — an ordinal that might
      // be off by one is not.
      expect(spoken, isNot(contains('door on your')));
      expect(spoken, contains('Digital Forensic Office'));
    });

    test('refuses to count when a declared door is missing', () {
      final plan = buildWing().copyWith(declaredDoorCounts: {'corridor': 8});
      final graph = RoomNavGraph.build(plan);
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2')!;

      expect(plan.corridorIsComplete('corridor'), isFalse);
      expect(plan.incompleteCorridors['corridor'], 2);
      expect(
        joined(directions.describe(graph, route, initialHeading: east)),
        isNot(contains('door on your')),
      );
    });
  });

  group('doorsPassedAlong', () {
    test('orders doors along the leg and sides them off the spine', () {
      final plan = buildWing();
      final passed = doorsPassedAlong(
        plan: plan,
        corridor: plan.roomOf('corridor')!,
        from: const Offset(0, 0),
        to: const Offset(20, 0),
      );

      expect(passed.map((d) => d.openingId), [
        'd-n1',
        'd-s1',
        'd-n2',
        'd-n3',
        'd-s2',
      ]);
      expect(passed.where((d) => d.onLeft).map((d) => d.openingId), [
        'd-n1',
        'd-n2',
        'd-n3',
      ]);
      expect(passed.where((d) => !d.onLeft).map((d) => d.openingId), [
        'd-s1',
        'd-s2',
      ]);
    });

    test('a door behind the walker is not passed', () {
      final plan = buildWing();
      final passed = doorsPassedAlong(
        plan: plan,
        corridor: plan.roomOf('corridor')!,
        from: const Offset(10, 0),
        to: const Offset(20, 0),
      );

      expect(passed.map((d) => d.openingId), ['d-n3', 'd-s2']);
    });
  });

  group('egocentric turns', () {
    test('orients the walker before the first leg', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2')!;

      // Starting facing north, the first leg (east down the lobby) is a right
      // turn. The spec's version emits no turn until the second leg, leaving
      // the walker to set off whichever way they happened to be standing.
      final spoken = joined(
        directions.describe(graph, route, initialHeading: const Offset(0, 1)),
      );

      expect(spoken, startsWith('Turn right.'));
    });

    test('says nothing about turning when the heading is unknown', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2')!;
      final first = directions.describe(graph, route).first;

      expect(first.text, isNot(contains('Turn')));
    });

    test('turning into a room off the corridor is a left turn going east', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2')!;
      final steps = directions.describe(graph, route, initialHeading: east);

      final turns = steps.where((s) => s.turnDegreesRight != 0).toList();
      expect(turns, isNotEmpty);
      expect(turns.last.turnDegreesRight, lessThan(0)); // negative = left
      expect(turns.last.text, 'Turn left.');
    });

    test('a u-turn is described as turning around', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n1')!;
      final steps = directions.describe(graph, route, initialHeading: west);

      expect(steps.first.text, 'Turn around.');
    });
  });

  group('unitless plans', () {
    test('omit distances rather than speaking plan units as metres', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2')!;
      final spoken = joined(
        const RoomDirections(
          metresPerUnit: null,
        ).describe(graph, route, initialHeading: east),
      );

      expect(spoken, isNot(contains('metres')));
      // The destination is still named — it is the door count that names it
      // now that the walk ends on the threshold rather than in the middle of
      // the room, and that sentence is true at any scale.
      expect(spoken, contains('Digital Forensic Office'));
    });

    test('metric plans do speak distances', () {
      final graph = RoomNavGraph.build(buildWing());
      final route = graph.route(fromRoomId: 'lobby', toRoomId: 'n2')!;

      expect(
        joined(directions.describe(graph, route, initialHeading: east)),
        contains('metres'),
      );
    });
  });

  group('plan bookkeeping', () {
    test('allocates the next free room code', () {
      expect(buildWing().allocateCode(), 'GF 7');
    });

    test('code allocation survives a reload rather than restarting at 1', () {
      final reloaded = RoomPlan.fromJson(buildWing().toJson());

      expect(reloaded.allocateCode(), 'GF 7');
    });

    test('a plan round-trips through JSON unchanged', () {
      final plan = buildWing();

      expect(RoomPlan.fromJson(plan.toJson()), equals(plan));
    });

    test('a corridor with no declared count is not complete', () {
      expect(
        buildWing(declareDoors: false).corridorIsComplete('corridor'),
        isFalse,
      );
      expect(buildWing().corridorIsComplete('corridor'), isTrue);
      expect(buildWing().isRoutable, isTrue);
    });
  });

  group('missing connections — the editor prompt', () {
    test('flags two rooms sharing a wall with no door', () {
      // n2 (x 7..9) and a new room butted against its east wall.
      final plan = buildWing();
      final withNeighbour = plan.copyWith(
        storedRooms: [
          ...plan.rooms,
          rectRoom(
            id: 'n2b',
            code: 'GF 8',
            category: RoomCategory.office,
            left: 9,
            right: 11,
            bottom: 1,
            top: 6,
          ),
        ],
        storedOpenings: [
          ...plan.openings,
          doorAt(id: 'd-n2b', roomA: 'corridor', roomB: 'n2b', x: 10, y: 1),
        ],
        declaredDoorCounts: {'corridor': plan.openings.length + 1},
      );

      final flagged = RoomNavGraph.build(withNeighbour).missingConnections();

      expect(
        flagged.any(
          (f) =>
              (f.roomA == 'n2' && f.roomB == 'n2b') ||
              (f.roomA == 'n2b' && f.roomB == 'n2'),
        ),
        isTrue,
      );
    });

    test('does not flag rooms that already have a door between them', () {
      final flagged = RoomNavGraph.build(buildWing()).missingConnections();

      expect(
        flagged.any(
          (f) =>
              (f.roomA == 'corridor' && f.roomB == 'n2') ||
              (f.roomA == 'n2' && f.roomB == 'corridor'),
        ),
        isFalse,
      );
    });
  });
}
