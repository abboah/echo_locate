import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/features/buildings/building_repository.dart';

void main() {
  late MockBuildingRepository repository;

  setUp(() => repository = MockBuildingRepository());

  test('recentlyMapped returns the Home screen pair', () async {
    final recent = await repository.recentlyMapped();
    expect(recent.map((b) => b.name), ['CABS Block', 'Science Block']);
  });

  test('nearby filters by category and sorts by distance', () async {
    final campus = await repository.nearby(category: 'campus');
    expect(campus, isNotEmpty);
    expect(campus.every((b) => b.category == 'campus'), isTrue);
    final distances = campus.map((b) => b.distanceKm).toList();
    expect(distances, List.of(distances)..sort());

    final malls = await repository.nearby(category: 'mall');
    expect(malls.map((b) => b.name), ['Kumasi City Mall']);
  });

  test('nearby filters by search query', () async {
    final results = await repository.nearby(query: 'library');
    expect(results.map((b) => b.id), ['knust-library']);
  });

  test('floorsOf returns one floor per storey with rooms', () async {
    final floors = await repository.floorsOf('knust-library');
    expect(floors, hasLength(4));
    expect(floors.first.label, 'G');
    expect(floors.every((f) => f.rooms.isNotEmpty), isTrue);
    // Floor 2 mirrors the Figma building-detail mock.
    expect(
      floors[2].rooms.map((r) => r.name),
      ['Reading Hall', 'Study Room 2B', 'Help Desk'],
    );
  });
}
