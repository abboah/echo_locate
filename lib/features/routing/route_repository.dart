import '../../core/models/landmark.dart';
import '../../core/models/route_draft.dart';
import '../../core/models/traced_plan.dart';
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

  /// The building's traced floor plan, or null when nobody has traced one.
  ///
  /// Preferred over [routesOf] when it exists: a plan traced off the posted
  /// floor plan carries absolute coordinates, where a recorded walk's geometry
  /// is chained from step counts and drifts.
  Future<TracedPlan?> tracedPlanOf(String buildingId);

  /// Stores a traced plan, replacing whatever the building had.
  ///
  /// Returns the plan with every node's ref rewritten to the id of the landmark
  /// it was upserted as, so the caller can build a graph whose node ids match
  /// the ones [landmarksOf] and OCR matching use. Saving and then reloading
  /// must produce the same graph.
  Future<TracedPlan> saveTracedPlan(TracedPlan plan);
}

/// Picks the best recording among several for one destination.
///
/// "Best" is the most-verified. Defined once and shared by both
/// implementations so the mock cannot drift from what the server does — the
/// point of the mock is that Stream B develops against production behaviour
/// without a network.
WalkRoute? bestRouteTo(List<WalkRoute> routes, String roomId) {
  WalkRoute? best;
  for (final route in routes) {
    if (route.destinationRoomId != roomId) continue;
    // Strictly greater, so equal counts keep the earlier route rather than
    // reshuffling between fetches — PostgREST does not guarantee row order.
    if (best == null || route.verifiedCount > best.verifiedCount) best = route;
  }
  return best;
}

/// Rejected before any network call: a route with no legs has nothing to
/// navigate and would draw an empty map.
const emptyDraftMessage = 'Record at least one leg before saving';

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
      id: 'lm-corridor-2',
      buildingId: 'knust-library',
      floorId: 'floor-2',
      kind: LandmarkKind.sign,
      labelText: 'ROOMS 201-210',
      displayName: 'Floor 2 directory board',
      aliases: ['ROOMS 201 - 210', '201-210'],
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
    Landmark(
      id: 'lm-study-2b',
      buildingId: 'knust-library',
      floorId: 'floor-2',
      kind: LandmarkKind.door,
      labelText: '2B',
      displayName: 'Study Room 2B door',
      aliases: ['28', '2 B'],
      roomId: 'study-2b',
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
        toLandmarkId: 'lm-corridor-2',
        instruction: 'Turn left along the main corridor to the directory board',
        distanceM: 9,
        stepsRecorded: 12,
        turnDeg: -90,
      ),
      RouteStep(
        seq: 5,
        fromLandmarkId: 'lm-corridor-2',
        toLandmarkId: 'lm-reading-hall',
        instruction:
            'Straight on; the Reading Hall is the second door on your right',
        distanceM: 6,
        stepsRecorded: 8,
      ),
    ],
  );

  /// Shares its first four legs with [_libraryRoute], diverging at the floor 2
  /// directory board. Two overlapping routes are what make A* meaningful: with
  /// only one, every answer is a replayed recording.
  static const _studyRoomRoute = WalkRoute(
    id: 'route-study-2b',
    buildingId: 'knust-library',
    startLandmarkId: 'lm-entrance',
    destinationRoomId: 'study-2b',
    totalDistanceM: 54,
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
        stepsRecorded: 25,
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
        toLandmarkId: 'lm-corridor-2',
        instruction: 'Turn left along the main corridor to the directory board',
        distanceM: 9,
        stepsRecorded: 12,
        turnDeg: -90,
      ),
      RouteStep(
        seq: 5,
        fromLandmarkId: 'lm-corridor-2',
        toLandmarkId: 'lm-study-2b',
        instruction: 'Turn right; Study Room 2B is the first door on your left',
        distanceM: 7,
        stepsRecorded: 9,
        turnDeg: 90,
      ),
    ],
  );

  final List<WalkRoute> _saved = [];

  /// Landmarks captured this session, alongside the seeded ones.
  final List<Landmark> _captured = [];

  /// One traced plan per building, replaced wholesale on save.
  final Map<String, TracedPlan> _plans = {};

  /// Upserts a landmark on the natural key and returns its id.
  ///
  /// Mirrors `save_route`'s `on conflict (building_id, floor_id, display_name)`
  /// so tracing a plan over a building somebody already walked reuses the
  /// landmarks rather than duplicating them — two nodes for one door would give
  /// A* a choice that does not exist and OCR two things to match.
  String _upsertLandmark({
    required String buildingId,
    required String floorId,
    required LandmarkKind kind,
    required String labelText,
    required String displayName,
    required List<String> aliases,
    String? roomId,
  }) {
    final existing = [..._landmarks, ..._captured].where(
      (l) =>
          l.buildingId == buildingId &&
          l.floorId == floorId &&
          l.displayName == displayName,
    );
    if (existing.isNotEmpty) return existing.first.id;

    final landmark = Landmark(
      id:
          'lm-${_captured.length + 1}-'
          '${displayName.toLowerCase().replaceAll(RegExp(r'\s+'), '-')}',
      buildingId: buildingId,
      floorId: floorId,
      kind: kind,
      labelText: labelText,
      displayName: displayName,
      aliases: aliases,
      roomId: roomId,
    );
    _captured.add(landmark);
    return landmark.id;
  }

  @override
  Future<TracedPlan?> tracedPlanOf(String buildingId) async {
    await Future<void>.delayed(_latency);
    return _plans[buildingId];
  }

  @override
  Future<TracedPlan> saveTracedPlan(TracedPlan plan) async {
    await Future<void>.delayed(_latency);

    final idOfRef = <String, String>{
      for (final node in plan.nodes)
        node.ref: _upsertLandmark(
          buildingId: plan.buildingId,
          floorId: node.floorId,
          kind: node.kind,
          labelText: node.labelText,
          displayName: node.displayName,
          aliases: node.aliases,
          roomId: node.roomId,
        ),
    };

    final resolved = TracedPlan(
      buildingId: plan.buildingId,
      nodes: [
        for (final node in plan.nodes) node.copyWith(ref: idOfRef[node.ref]!),
      ],
      edges: [
        for (final edge in plan.edges)
          // An edge whose ends did not resolve is dropped rather than stored
          // pointing at a ref no landmark answers to.
          if (idOfRef[edge.fromRef] != null && idOfRef[edge.toRef] != null)
            TracedEdge(
              fromRef: idOfRef[edge.fromRef]!,
              toRef: idOfRef[edge.toRef]!,
            ),
      ],
    );

    _plans[plan.buildingId] = resolved;
    return resolved;
  }

  @override
  Future<List<Landmark>> landmarksOf(String buildingId) async {
    await Future<void>.delayed(_latency);
    return [
      for (final landmark in [..._landmarks, ..._captured])
        if (landmark.buildingId == buildingId) landmark,
    ];
  }

  @override
  Future<List<WalkRoute>> routesOf(String buildingId) async {
    await Future<void>.delayed(_latency);
    return [
      if (buildingId == 'knust-library') ...[_libraryRoute, _studyRoomRoute],
      ..._saved.where((r) => r.buildingId == buildingId),
    ];
  }

  @override
  Future<WalkRoute?> routeTo(String buildingId, String roomId) async {
    return bestRouteTo(await routesOf(buildingId), roomId);
  }

  @override
  Future<String> saveRoute(RouteDraft draft) async {
    if (draft.steps.isEmpty) throw const OperationFailure(emptyDraftMessage);
    await Future<void>.delayed(_latency);

    // Mirrors `save_route`: landmarks are upserted on their display name
    // within the building, and the client-side refs ('L1') are swapped for the
    // ids the steps then point at. Doing less here would leave the mock map
    // with nodes no landmark matches, which is what the real server avoids.
    final idOfRef = <String, String>{
      for (final drafted in draft.landmarks)
        drafted.ref: _upsertLandmark(
          buildingId: draft.buildingId,
          floorId: drafted.floorId,
          kind: drafted.kind,
          labelText: drafted.labelText,
          displayName: drafted.displayName,
          aliases: drafted.aliases,
          roomId: drafted.roomId,
        ),
    };

    final id = 'route-${_saved.length + 1}';
    _saved.add(
      WalkRoute(
        id: id,
        buildingId: draft.buildingId,
        startLandmarkId: draft.steps.isEmpty
            ? ''
            : idOfRef[draft.steps.first.fromRef] ?? '',
        destinationRoomId: draft.destinationRoomId,
        totalDistanceM: draft.steps.fold(0, (sum, s) => sum + s.distanceM),
        steps: [
          for (final s in draft.steps)
            RouteStep(
              seq: s.seq,
              fromLandmarkId: idOfRef[s.fromRef] ?? s.fromRef,
              toLandmarkId: idOfRef[s.toRef] ?? s.toRef,
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
