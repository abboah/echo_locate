import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/services/mapping/floor_mapping_status.dart';
import 'package:flutter_test/flutter_test.dart';

const ground = BuildingFloor(id: 'gf', label: 'G', rooms: []);
const first = BuildingFloor(id: 'f1', label: '1', rooms: []);

Room rect(
  String id, {
  RoomCategory category = RoomCategory.office,
  double left = 0,
  double right = 4,
  double bottom = 0,
  double top = 3,
}) => Room(
  id: id,
  floorId: 'gf',
  code: id.toUpperCase(),
  category: category,
  polygon: [
    RoomCorner(x: left, y: bottom),
    RoomCorner(x: right, y: bottom),
    RoomCorner(x: right, y: top),
    RoomCorner(x: left, y: top),
  ],
);

RoomPlan planOf({
  List<Room> rooms = const [],
  List<Opening> openings = const [],
  Map<String, int> counts = const {},
  double? metresPerUnit = 1,
}) => RoomPlan(
  buildingId: 'knust-cs',
  floorId: 'gf',
  codePrefix: 'GF',
  metresPerUnit: metresPerUnit,
  storedRooms: rooms,
  storedOpenings: openings,
  declaredDoorCounts: counts,
);

void main() {
  group('what stage a floor is at', () {
    test('nothing captured', () {
      final status = FloorMappingStatus.of(ground, null);

      expect(status.stage, FloorMappingStage.notStarted);
      expect(status.method, MappingMethod.none);
      expect(status.hasPlan, isFalse);
      expect(status.nextActionLabel, 'Start mapping');
    });

    test('an empty plan counts as nothing captured', () {
      expect(
        FloorMappingStatus.of(ground, planOf()).stage,
        FloorMappingStage.notStarted,
      );
    });

    test('rooms with no doors is the most common half-finished state', () {
      final status = FloorMappingStatus.of(
        ground,
        planOf(rooms: [rect('a'), rect('b', left: 4, right: 8)]),
      );

      // Placing doors comes after the satisfying part, so this is where a
      // floor gets abandoned.
      expect(status.stage, FloorMappingStage.needsDoors);
      expect(status.roomsWithoutDoors, 2);
      expect(status.nextActionLabel, 'Add doors');
      expect(status.summary, contains('2 with no door yet'));
    });

    test('doors placed but the floor is in two islands', () {
      final status = FloorMappingStatus.of(
        ground,
        planOf(
          rooms: [
            rect('a'),
            rect('b', left: 4, right: 8),
            rect('c', left: 40, right: 44),
            rect('d', left: 44, right: 48),
          ],
          openings: const [
            Opening(
              id: 'd1',
              roomAId: 'a',
              roomBId: 'b',
              at: RoomCorner(x: 4, y: 1),
            ),
            Opening(
              id: 'd2',
              roomAId: 'c',
              roomBId: 'd',
              at: RoomCorner(x: 44, y: 1),
            ),
          ],
        ),
      );

      // Every room has a door, so nothing looks wrong, and half the building
      // is unroutable.
      expect(status.stage, FloorMappingStage.disconnected);
      expect(status.roomsWithoutDoors, 0);
      expect(status.strandedRooms, 2);
      expect(status.nextActionLabel, 'Join it up');
    });

    test('connected but a corridor count is unmet', () {
      final status = FloorMappingStatus.of(
        ground,
        planOf(
          rooms: [
            rect('c', category: RoomCategory.corridor, right: 20),
            rect('a', bottom: 3, top: 7),
          ],
          openings: const [
            Opening(
              id: 'd1',
              roomAId: 'c',
              roomBId: 'a',
              at: RoomCorner(x: 2, y: 3),
            ),
          ],
          counts: {'c': 4},
        ),
      );

      // The floor routes; it just will not say which door.
      expect(status.stage, FloorMappingStage.countsPending);
      expect(status.undeclaredDoors, 3);
      expect(status.stage.isNavigable, isTrue);
    });

    test('finished', () {
      final status = FloorMappingStatus.of(
        ground,
        planOf(
          rooms: [rect('a'), rect('b', left: 4, right: 8)],
          openings: const [
            Opening(
              id: 'd1',
              roomAId: 'a',
              roomBId: 'b',
              at: RoomCorner(x: 4, y: 1),
            ),
          ],
        ),
      );

      expect(status.stage, FloorMappingStage.ready);
      expect(status.stage.isNavigable, isTrue);
      expect(status.summary, contains('ready to navigate'));
    });

    test('stages are ordered by what blocks navigation, not by effort', () {
      // Forty rooms and no doors routes exactly as badly as two rooms and no
      // doors, so both sit at the same stage.
      final small = FloorMappingStatus.of(ground, planOf(rooms: [rect('a')]));
      final large = FloorMappingStatus.of(
        ground,
        planOf(
          rooms: [
            for (var i = 0; i < 40; i++)
              rect('r$i', left: i * 5.0, right: i * 5.0 + 4),
          ],
        ),
      );

      expect(small.stage, large.stage);
    });
  });

  group('which method was used', () {
    test('a metric plan was scanned', () {
      expect(
        FloorMappingStatus.of(ground, planOf(rooms: [rect('a')])).method,
        MappingMethod.scanned,
      );
    });

    test('a unitless plan was traced off a photo', () {
      expect(
        FloorMappingStatus.of(
          ground,
          planOf(rooms: [rect('a')], metresPerUnit: null),
        ).method,
        MappingMethod.traced,
      );
    });
  });

  group('a building as a whole', () {
    BuildingMappingProgress progressOf(Map<BuildingFloor, RoomPlan?> plans) =>
        BuildingMappingProgress([
          for (final entry in plans.entries)
            FloorMappingStatus.of(entry.key, entry.value),
        ]);

    RoomPlan finished() => planOf(
      rooms: [rect('a'), rect('b', left: 4, right: 8)],
      openings: const [
        Opening(
          id: 'd1',
          roomAId: 'a',
          roomBId: 'b',
          at: RoomCorner(x: 4, y: 1),
        ),
      ],
    );

    test('points at a half-finished floor before an untouched one', () {
      final progress = progressOf({
        ground: planOf(rooms: [rect('a')]),
        first: null,
      });

      // Finishing something beats starting something, and a half-mapped floor
      // is the one that gets forgotten.
      expect(progress.nextFloor!.floor.id, 'gf');
      expect(progress.nextFloor!.stage, FloorMappingStage.needsDoors);
    });

    test('falls through to an untouched floor when nothing is in progress', () {
      final progress = progressOf({ground: finished(), first: null});

      expect(progress.nextFloor!.floor.id, 'f1');
    });

    test('nothing left to do when every floor is navigable', () {
      final progress = progressOf({ground: finished(), first: finished()});

      expect(progress.nextFloor, isNull);
      expect(progress.isComplete, isTrue);
      expect(progress.summary, contains('ready to navigate'));
    });

    test('counts navigable floors separately from mapped ones', () {
      final progress = progressOf({
        ground: finished(),
        first: planOf(rooms: [rect('a')]),
      });

      expect(progress.mappedFloors, 2);
      expect(progress.navigableFloors, 1);
      expect(progress.isComplete, isFalse);
      expect(progress.summary, contains('1 of 2 floors ready'));
    });

    test('a building with nothing done says how much there is', () {
      final progress = progressOf({ground: null, first: null});

      expect(progress.summary, '2 floors to map.');
      expect(progress.nextFloor!.floor.id, 'gf');
    });

    test('a building with no floors listed says so', () {
      expect(
        const BuildingMappingProgress([]).summary,
        contains('no floors listed'),
      );
    });
  });
}
