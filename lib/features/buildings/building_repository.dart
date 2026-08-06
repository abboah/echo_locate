import '../../core/models/building.dart';
import '../../data/repository_mixin.dart';

/// Crowdsourced building index. Mock implementation for Phase 1 — the
/// Supabase-backed implementation replaces [MockBuildingRepository] behind
/// this interface in Phase 2 (screens don't change).
abstract class BuildingRepository {
  /// Buildings the current user recently mapped (Home "Recently mapped").
  Future<List<Building>> recentlyMapped();

  /// Nearby buildings for Explore, filterable by category chip and search.
  Future<List<Building>> nearby({String category = 'all', String query = ''});

  Future<Building> byId(String id);

  /// Floors + rooms for the Building Detail screen.
  Future<List<BuildingFloor>> floorsOf(String buildingId);

  /// Buildings saved for offline use (Maps tab).
  Future<List<Building>> savedMaps();

  /// Whether the signed-in user has saved this building for offline use.
  Future<bool> isSaved(String buildingId);

  /// Save/unsave a building for offline use; returns the new saved state.
  Future<bool> setSaved(String buildingId, bool saved);
}

class MockBuildingRepository with RepositoryMixin implements BuildingRepository {
  static const _latency = Duration(milliseconds: 350);

  // KNUST-flavoured seed data matching the Figma screens.
  static const _buildings = [
    Building(
      id: 'knust-library',
      name: 'KNUST Library',
      area: 'KNUST, Kumasi',
      floorsCount: 4,
      mappers: 12,
      mappedPercent: 94,
      distanceKm: 0.2,
      category: 'campus',
      glyph: 'building',
      updatedLabel: 'updated today',
    ),
    Building(
      id: 'engineering-block',
      name: 'Engineering Block',
      area: 'KNUST, Kumasi',
      floorsCount: 5,
      mappers: 8,
      mappedPercent: 71,
      distanceKm: 0.4,
      category: 'campus',
      glyph: 'door',
      updatedLabel: 'updated yesterday',
    ),
    Building(
      id: 'src-building',
      name: 'SRC Building',
      area: 'KNUST, Kumasi',
      floorsCount: 2,
      mappers: 3,
      mappedPercent: 42,
      distanceKm: 0.6,
      category: 'campus',
      glyph: 'home',
      updatedLabel: 'updated 3 days ago',
    ),
    Building(
      id: 'great-hall',
      name: 'Great Hall',
      area: 'KNUST, Kumasi',
      floorsCount: 1,
      mappers: 6,
      mappedPercent: 88,
      distanceKm: 0.5,
      category: 'campus',
      glyph: 'hall',
      updatedLabel: 'updated this week',
    ),
    Building(
      id: 'cabs-block',
      name: 'CABS Block',
      area: 'KNUST, Kumasi',
      floorsCount: 3,
      mappers: 4,
      mappedPercent: 87,
      distanceKm: 0.3,
      category: 'campus',
      glyph: 'building',
      updatedLabel: 'updated today',
    ),
    Building(
      id: 'science-block',
      name: 'Science Block',
      area: 'KNUST, Kumasi',
      floorsCount: 2,
      mappers: 2,
      mappedPercent: 62,
      distanceKm: 0.4,
      category: 'campus',
      glyph: 'door',
      updatedLabel: 'updated yesterday',
    ),
    Building(
      id: 'kath-wing-a',
      name: 'KATH — Wing A',
      area: 'Bantama, Kumasi',
      floorsCount: 3,
      mappers: 5,
      mappedPercent: 55,
      distanceKm: 2.1,
      category: 'hospital',
      glyph: 'building',
      updatedLabel: 'updated this week',
    ),
    Building(
      id: 'kumasi-city-mall',
      name: 'Kumasi City Mall',
      area: 'Asokwa, Kumasi',
      floorsCount: 2,
      mappers: 9,
      mappedPercent: 77,
      distanceKm: 3.4,
      category: 'mall',
      glyph: 'hall',
      updatedLabel: 'updated today',
    ),
  ];

  @override
  Future<List<Building>> recentlyMapped() {
    return runEphemeralQuery('buildings:recent', () async {
      await Future<void>.delayed(_latency);
      return _buildings
          .where((b) => b.id == 'cabs-block' || b.id == 'science-block')
          .toList();
    });
  }

  @override
  Future<List<Building>> nearby({String category = 'all', String query = ''}) {
    // Cache the full list once per session; filter in memory per call.
    return runEphemeralQuery('buildings:all', () async {
      await Future<void>.delayed(_latency);
      return _buildings;
    }).then((all) {
      final q = query.trim().toLowerCase();
      return all
          .where((b) => category == 'all' || b.category == category)
          .where((b) => q.isEmpty || b.name.toLowerCase().contains(q))
          .toList()
        ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    });
  }

  @override
  Future<Building> byId(String id) async {
    final all = await nearby();
    return all.firstWhere(
      (b) => b.id == id,
      orElse: () => throw const OperationFailure('Building not found'),
    );
  }

  @override
  Future<List<BuildingFloor>> floorsOf(String buildingId) {
    return runEphemeralQuery('floors:$buildingId', () async {
      await Future<void>.delayed(_latency);
      final building = await byId(buildingId);
      return List.generate(building.floorsCount, (i) {
        final label = i == 0 ? 'G' : '$i';
        // Mirrors the ids the seeded landmarks reference, so the floor plan's
        // switcher can name its planes offline exactly as it does online.
        return BuildingFloor(
          id: i == 0 ? 'floor-g' : 'floor-$i',
          label: label,
          rooms: _roomsFor(buildingId, i),
        );
      });
    });
  }

  /// Session-scoped stand-in for the `saved_maps` table.
  final Set<String> _saved = {'knust-library', 'great-hall'};

  @override
  Future<List<Building>> savedMaps() async {
    await Future<void>.delayed(_latency);
    return _buildings.where((b) => _saved.contains(b.id)).toList();
  }

  @override
  Future<bool> isSaved(String buildingId) async => _saved.contains(buildingId);

  @override
  Future<bool> setSaved(String buildingId, bool saved) async {
    if (saved) {
      _saved.add(buildingId);
    } else {
      _saved.remove(buildingId);
    }
    return saved;
  }

  List<Room> _roomsFor(String buildingId, int floorIndex) {
    // The library's floor 2 mirrors the Figma Building Detail screen (7:301).
    if (buildingId == 'knust-library' && floorIndex == 2) {
      return const [
        Room(id: 'reading-hall', name: 'Reading Hall', distanceM: 40, kind: 'hall'),
        Room(id: 'study-2b', name: 'Study Room 2B', distanceM: 65, kind: 'room'),
        Room(id: 'help-desk', name: 'Help Desk', distanceM: 20, kind: 'desk'),
      ];
    }
    final label = floorIndex == 0 ? 'G' : '$floorIndex';
    return [
      Room(id: '$buildingId-$floorIndex-01', name: 'Room ${label}01', distanceM: 25, kind: 'room'),
      Room(id: '$buildingId-$floorIndex-02', name: 'Room ${label}02', distanceM: 45, kind: 'room'),
      Room(id: '$buildingId-$floorIndex-wash', name: 'Washroom', distanceM: 30, kind: 'desk'),
    ];
  }
}
