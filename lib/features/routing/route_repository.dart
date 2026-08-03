import '../../core/models/landmark.dart';
import '../../core/models/route_draft.dart';
import '../../core/models/walk_route.dart';
import '../../data/repository_mixin.dart';

/// Landmarks and recorded routes for a building.
///
/// The contract both work streams build against (see
/// `docs/landmark-navigation-spec.md` §5). Stream A consumes it to lay out the
/// 2D schematic and build the A* graph; Stream B consumes it to guide a user
/// along a route and to upload newly captured ones.
abstract class RouteRepository {
  /// Every landmark in the building, across all floors.
  ///
  /// Guidance needs the full set, not just the current route's: the recovery
  /// sweep matches an OCR read against *any* landmark in the building to work
  /// out where a lost user actually is.
  Future<List<Landmark>> landmarksOf(String buildingId);

  /// Every recorded route. Stream A merges these into one floor graph, so
  /// routes sharing a landmark stitch together.
  Future<List<WalkRoute>> routesOf(String buildingId);

  /// The best recorded route to a room, or null when nobody has walked it yet.
  /// "Best" is currently the most-verified recording.
  Future<WalkRoute?> routeTo(String buildingId, String roomId);

  /// Uploads a captured route atomically. Returns the new route's id.
  Future<String> saveRoute(RouteDraft draft);
}

/// In-memory stand-in used when `AppConfig.hasSupabase` is false, mirroring
/// the seed in `supabase/migrations/20260803090100_seed_library_route.sql` so
/// both streams can work offline and unit-test without a network.
class MockRouteRepository with RepositoryMixin implements RouteRepository {
  static const _latency = Duration(milliseconds: 250);

  static const _landmarks = [
    Landmark(
      id: 'lm-entrance',
      buildingId: 'knust-library',
      floorId: 'floor-g',
      kind: LandmarkKind.entrance,
      labelText: 'KNUST LIBRARY',
      displayName: 'Main entrance',
    ),
    Landmark(
      id: 'lm-desk',
      buildingId: 'knust-library',
      floorId: 'floor-g',
      kind: LandmarkKind.junction,
      labelText: 'HELP DESK',
      displayName: 'Help desk',
      aliases: ['HELPDESK'],
    ),
    Landmark(
      id: 'lm-stairs-g',
      buildingId: 'knust-library',
      floorId: 'floor-g',
      kind: LandmarkKind.stairs,
      labelText: 'STAIRS',
      displayName: 'Ground floor stairwell',
      aliases: ['STAIRWAY'],
    ),
    Landmark(
      id: 'lm-landing-2',
      buildingId: 'knust-library',
      floorId: 'floor-2',
      kind: LandmarkKind.stairs,
      labelText: '2',
      displayName: 'Floor 2 landing',
      aliases: ['FLOOR 2', '2ND'],
    ),
    Landmark(
      id: 'lm-reading-hall',
      buildingId: 'knust-library',
      floorId: 'floor-2',
      kind: LandmarkKind.door,
      labelText: 'READING HALL',
      displayName: 'Reading Hall door',
      aliases: ['READINGHALL'],
      roomId: 'reading-hall',
    ),
  ];

  static const _libraryRoute = WalkRoute(
    id: 'route-reading-hall',
    buildingId: 'knust-library',
    startLandmarkId: 'lm-entrance',
    destinationRoomId: 'reading-hall',
    totalDistanceM: 53,
    steps: [
      RouteStep(
        seq: 1,
        fromLandmarkId: 'lm-entrance',
        toLandmarkId: 'lm-desk',
        instruction: 'Straight ahead, past the entrance desk',
        distanceM: 12,
        stepsRecorded: 16,
      ),
      RouteStep(
        seq: 2,
        fromLandmarkId: 'lm-desk',
        toLandmarkId: 'lm-stairs-g',
        instruction: 'Turn right; the stairwell is at the end of the corridor',
        distanceM: 18,
        stepsRecorded: 24,
        turnDeg: 90,
      ),
      RouteStep(
        seq: 3,
        fromLandmarkId: 'lm-stairs-g',
        toLandmarkId: 'lm-landing-2',
        instruction: 'Take the stairs up two flights to floor 2',
        distanceM: 8,
        stepsRecorded: 11,
      ),
      RouteStep(
        seq: 4,
        fromLandmarkId: 'lm-landing-2',
        toLandmarkId: 'lm-reading-hall',
        instruction:
            'Turn left; the Reading Hall is the third door on your right',
        distanceM: 15,
        stepsRecorded: 20,
        turnDeg: -90,
      ),
    ],
  );

  final List<WalkRoute> _saved = [];

  @override
  Future<List<Landmark>> landmarksOf(String buildingId) async {
    await Future<void>.delayed(_latency);
    return _landmarks.where((l) => l.buildingId == buildingId).toList();
  }

  @override
  Future<List<WalkRoute>> routesOf(String buildingId) async {
    await Future<void>.delayed(_latency);
    return [
      if (buildingId == 'knust-library') _libraryRoute,
      ..._saved.where((r) => r.buildingId == buildingId),
    ];
  }

  @override
  Future<WalkRoute?> routeTo(String buildingId, String roomId) async {
    final routes = await routesOf(buildingId);
    for (final route in routes) {
      if (route.destinationRoomId == roomId) return route;
    }
    return null;
  }

  @override
  Future<String> saveRoute(RouteDraft draft) async {
    await Future<void>.delayed(_latency);
    // Refs stand in for the uuids the server would mint.
    final id = 'route-${_saved.length + 1}';
    _saved.add(
      WalkRoute(
        id: id,
        buildingId: draft.buildingId,
        startLandmarkId: draft.steps.isEmpty ? '' : draft.steps.first.fromRef,
        destinationRoomId: draft.destinationRoomId,
        totalDistanceM:
            draft.steps.fold(0, (sum, s) => sum + s.distanceM),
        steps: [
          for (final s in draft.steps)
            RouteStep(
              seq: s.seq,
              fromLandmarkId: s.fromRef,
              toLandmarkId: s.toRef,
              instruction: s.instruction,
              distanceM: s.distanceM,
              turnDeg: s.turnDeg,
              stepsRecorded: s.stepsRecorded,
            ),
        ],
      ),
    );
    return id;
  }
}
