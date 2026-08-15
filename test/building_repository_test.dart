import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/features/buildings/building_repository.dart';

void main() {
  late MockBuildingRepository repository;

  setUp(() => repository = MockBuildingRepository());

  test('recentlyMapped offline is the one demo building', () async {
    final recent = await repository.recentlyMapped();
    // The invented campus is gone. Returning everything there is keeps Home
    // showing something offline rather than an empty grid that reads as a bug.
    expect(recent.map((b) => b.name), ['KNUST Library']);
  });

  test('nearby filters by category and sorts by distance', () async {
    final campus = await repository.nearby(category: 'campus');
    expect(campus, isNotEmpty);
    expect(campus.every((b) => b.category == 'campus'), isTrue);
    final distances = campus.map((b) => b.distanceKm).toList();
    expect(distances, List.of(distances)..sort());
  });

  test('a category nothing has been mapped under comes back empty', () async {
    expect(await repository.nearby(category: 'mall'), isEmpty);
  });

  test('nearby filters by search query', () async {
    final results = await repository.nearby(query: 'library');
    expect(results.map((b) => b.id), ['knust-library']);
  });

  group('adding a building nobody has listed', () {
    test('it shows up in the index straight away', () async {
      final added = await repository.create(
        name: 'Great Hall Annexe',
        area: 'KNUST, Kumasi',
        floors: 2,
      );

      expect(added.id, 'great-hall-annexe');
      final all = await repository.nearby();
      expect(all.map((b) => b.name), contains('Great Hall Annexe'));
    });

    test(
      'it starts at nothing mapped, not at an invented percentage',
      () async {
        final added = await repository.create(name: 'Annexe', area: 'Kumasi');

        expect(added.mappedPercent, 0);
      },
    );

    test('its floors exist and are empty, ready to trace', () async {
      final added = await repository.create(
        name: 'Annexe',
        area: 'Kumasi',
        floors: 3,
      );

      final floors = await repository.floorsOf(added.id);
      expect(floors, hasLength(3));
      expect(floors.first.label, 'G');
      // Rooms are the contributor's to record; generating them here would
      // invent the very data they are about to map.
      expect(floors.every((f) => f.rooms.isEmpty), isTrue);
    });

    test('a name that collides is suffixed, not merged into the other '
        'building', () async {
      final first = await repository.create(name: 'KNUST Library', area: 'K');

      // Upserting would have silently handed this contributor the existing
      // library to edit.
      expect(first.id, isNot('knust-library'));
      expect(first.id, 'knust-library-2');
    });

    test('an unnamed building is refused', () async {
      expect(
        () => repository.create(name: '   ', area: 'Kumasi'),
        throwsA(isA<Exception>()),
      );
    });
  });

  test('floorsOf returns one floor per storey with rooms', () async {
    final floors = await repository.floorsOf('knust-library');
    expect(floors, hasLength(4));
    expect(floors.first.label, 'G');
    expect(floors.every((f) => f.rooms.isNotEmpty), isTrue);
    // Floor 2 mirrors the Figma building-detail mock.
    expect(floors[2].rooms.map((r) => r.name), [
      'Reading Hall',
      'Study Room 2B',
      'Help Desk',
    ]);
  });
}
