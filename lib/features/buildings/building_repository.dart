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

  /// Adds a building nobody has listed yet, with [floors] empty floors ready to
  /// be traced, and makes the caller its first contributor.
  ///
  /// The index is crowdsourced, so it cannot only contain what was seeded into
  /// it: a contributor standing in an unlisted building has to be able to add
  /// it and start mapping, or the whole feature only works on buildings that
  /// somebody else already thought of.
  Future<Building> create({
    required String name,
    required String area,
    String category,
    int floors,
  });
}

/// Slug for a new building's id: `'Great Hall Annexe'` → `'great-hall-annexe'`.
///
/// The `buildings` primary key is human-readable text rather than a uuid, so it
/// is generated rather than minted. Uniqueness is the caller's problem —
/// [BuildingRepository.create] suffixes a collision rather than overwriting
/// somebody else's building.
String slugify(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'building' : slug;
}

class MockBuildingRepository
    with RepositoryMixin
    implements BuildingRepository {
  static const _latency = Duration(milliseconds: 350);

  /// The one building the offline path knows about.
  ///
  /// This list used to hold eight invented buildings with invented mapper
  /// counts and completion percentages — Phase 1 scaffolding for screens built
  /// before there was a database. Kept past that point they were a claim the
  /// app could not back up: a browsable campus nobody had mapped. They are gone
  /// from `20260731090100_seed_knust.sql` too.
  ///
  /// One survives because a demonstration with no network needs somewhere to
  /// demonstrate, and because it is the building the Profile developer
  /// shortcuts open.
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
  ];

  @override
  Future<List<Building>> recentlyMapped() {
    return runEphemeralQuery('buildings:recent', () async {
      await Future<void>.delayed(_latency);
      // Everything there is, which offline is the demo building plus anything
      // added this session. This used to name two of the invented buildings;
      // with those gone it would have silently returned nothing and left Home
      // looking broken rather than empty.
      return _all;
    });
  }

  List<Building> get _all => [..._buildings, ..._created];

  @override
  Future<List<Building>> nearby({String category = 'all', String query = ''}) {
    // Cache the full list once per session; filter in memory per call.
    return runEphemeralQuery('buildings:all', () async {
      await Future<void>.delayed(_latency);
      return _all;
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
      // A building added this session has its floors already, empty and
      // waiting to be traced — generating rooms into them would invent the
      // very data the contributor is about to record.
      final created = _createdFloors[buildingId];
      if (created != null) return created;
      final building = await byId(buildingId);
      return List.generate(building.floorsCount, (i) {
        final label = i == 0 ? 'G' : '$i';
        return BuildingFloor(
          // Stands in for the uuid the `floors` table would mint, so capture
          // works against the mocks too. Deliberately the same ids the mock
          // landmarks carry (`floor-g`, `floor-2`): the floor switcher matches
          // a graph node's floor against this list to name it, so a mock world
          // that disagrees with itself would label every plane with a raw id.
          id: i == 0 ? 'floor-g' : 'floor-$i',
          label: label,
          rooms: _roomsFor(buildingId, i),
        );
      });
    });
  }

  /// Session-scoped stand-in for the `saved_maps` table.
  final Set<String> _saved = {'knust-library'};

  @override
  Future<List<Building>> savedMaps() async {
    await Future<void>.delayed(_latency);
    return _all.where((b) => _saved.contains(b.id)).toList();
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

  /// Buildings added in this session, alongside the one demo building.
  final List<Building> _created = [];

  final Map<String, List<BuildingFloor>> _createdFloors = {};

  @override
  Future<Building> create({
    required String name,
    required String area,
    String category = 'campus',
    int floors = 1,
  }) async {
    await Future<void>.delayed(_latency);

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const OperationFailure('Give the building a name');
    }

    final taken = {..._buildings, ..._created}.map((b) => b.id).toSet();
    var id = slugify(trimmed);
    for (var n = 2; taken.contains(id); n++) {
      id = '${slugify(trimmed)}-$n';
    }

    final building = Building(
      id: id,
      name: trimmed,
      area: area.trim(),
      floorsCount: floors,
      // Nothing has been traced yet, and saying otherwise is the invented
      // statistic this app just finished removing.
      mappers: 1,
      mappedPercent: 0,
      distanceKm: 0,
      category: category,
      glyph: 'building',
      updatedLabel: 'updated today',
    );

    _created.add(building);
    _createdFloors[id] = [
      for (var i = 0; i < floors; i++)
        BuildingFloor(
          id: '$id-floor-${i == 0 ? 'g' : i}',
          label: i == 0 ? 'G' : '$i',
          rooms: const [],
        ),
    ];

    // The session caches are keyed lists, so a new building would not show up
    // on Explore or Home until the app restarted without this.
    RepositoryMixin.clearEphemeralCache();
    return building;
  }

  List<Room> _roomsFor(String buildingId, int floorIndex) {
    // The library's floor 2 mirrors the Figma Building Detail screen (7:301).
    if (buildingId == 'knust-library' && floorIndex == 2) {
      return const [
        Room(
          id: 'reading-hall',
          name: 'Reading Hall',
          distanceM: 40,
          kind: 'hall',
        ),
        Room(
          id: 'study-2b',
          name: 'Study Room 2B',
          distanceM: 65,
          kind: 'room',
        ),
        Room(id: 'help-desk', name: 'Help Desk', distanceM: 20, kind: 'desk'),
      ];
    }
    final label = floorIndex == 0 ? 'G' : '$floorIndex';
    return [
      Room(
        id: '$buildingId-$floorIndex-01',
        name: 'Room ${label}01',
        distanceM: 25,
        kind: 'room',
      ),
      Room(
        id: '$buildingId-$floorIndex-02',
        name: 'Room ${label}02',
        distanceM: 45,
        kind: 'room',
      ),
      Room(
        id: '$buildingId-$floorIndex-wash',
        name: 'Washroom',
        distanceM: 30,
        kind: 'desk',
      ),
    ];
  }
}
