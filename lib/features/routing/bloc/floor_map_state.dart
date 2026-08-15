part of 'floor_map_bloc.dart';

/// loading → ready | empty (nobody has walked it yet) | failure.
enum FloorMapStatus { loading, ready, empty, failure }

final class FloorMapState extends Equatable {
  const FloorMapState({
    this.status = FloorMapStatus.loading,
    this.buildingId = '',
    this.buildingName,
    this.graph = FloorGraph.empty,
    this.landmarks = const [],
    this.routes = const [],
    this.floors = const [],
    this.activeFloorId,
    this.worstSpreadM = 0,
    this.fromId,
    this.toId,
    this.plan,
    this.error,
  });

  final FloorMapStatus status;
  final String buildingId;

  /// Null until looked up, and when the lookup fails.
  final String? buildingName;
  final FloorGraph graph;
  final List<Landmark> landmarks;
  final List<WalkRoute> routes;

  /// The building's floors, for naming the planes in the switcher. Best-effort
  /// like [buildingName]: without it the switcher falls back to raw floor ids,
  /// which is ugly but still navigable.
  final List<BuildingFloor> floors;

  /// Which plane is being drawn. Only one floor is shown at a time — stacking
  /// two on one canvas draws corridors crossing each other that do not.
  final String? activeFloorId;

  /// How far apart the merge found the same landmark to be before averaging,
  /// at its worst, in metres.
  ///
  /// Accumulated turn and step error, made visible. Spec §10 asks for it as a
  /// reported measure, and the screen shows it rather than hiding it: a
  /// schematic that admits its own error is a result, one that hides it is a
  /// lie. Always 0 for a traced plan, which has no drift to accumulate.
  final double worstSpreadM;

  final String? fromId;
  final String? toId;

  /// The way between [fromId] and [toId], or null when they are not connected
  /// — or when only one end has been picked.
  final PlannedRoute? plan;

  final String? error;

  Landmark? landmarkOf(String id) {
    for (final landmark in landmarks) {
      if (landmark.id == id) return landmark;
    }
    return null;
  }

  /// Landmarks that appear on the map, in a stable order for the pickers.
  ///
  /// A landmark the graph has never seen cannot be routed to, so offering it
  /// would be offering a dead end.
  List<Landmark> get mappedLandmarks => [
    for (final landmark in landmarks)
      if (graph.nodes.containsKey(landmark.id)) landmark,
  ]..sort((a, b) => a.displayName.compareTo(b.displayName));

  /// Landmark ids along the current plan, for highlighting on the map.
  List<String> get highlighted => plan?.landmarkIds ?? const [];

  /// Floors the graph actually places something on, ordered by the building's
  /// own floor list where it is known.
  ///
  /// Driven by the graph rather than the building: a floor nobody has walked
  /// has nothing to draw, and offering an empty plane reads as a bug.
  List<String> get mappedFloorIds {
    final present = graph.floorIds;
    final ordered = <String>[
      for (final floor in floors)
        if (present.contains(floor.id)) floor.id,
    ];
    // Anything the graph knows about that the building's floor list does not —
    // a stale cache, or a landmark attached to a floor since renamed.
    for (final id in present) {
      if (!ordered.contains(id)) ordered.add(id);
    }
    return ordered;
  }

  /// What to call [floorId] in the switcher.
  String labelForFloor(String floorId) {
    for (final floor in floors) {
      if (floor.id == floorId) return floor.label;
    }
    return floorId.isEmpty ? '—' : floorId;
  }

  /// Nodes on the plane being drawn.
  List<MapNode> get nodesOnActiveFloor {
    final floorId = activeFloorId;
    if (floorId == null) return graph.nodes.values.toList();
    return graph.nodesOn(floorId).toList();
  }

  /// Corridors with both ends on the plane being drawn.
  List<GraphEdge> get edgesOnActiveFloor {
    final floorId = activeFloorId;
    if (floorId == null) return graph.edges;
    return graph.edgesOn(floorId).toList();
  }

  /// Landmarks by id, the shape the painter wants.
  Map<String, Landmark> get landmarksById => {
    for (final landmark in landmarks) landmark.id: landmark,
  };

  FloorMapState copyWith({
    FloorMapStatus? status,
    String? buildingId,
    String? buildingName,
    FloorGraph? graph,
    List<Landmark>? landmarks,
    List<WalkRoute>? routes,
    List<BuildingFloor>? floors,
    String? activeFloorId,
    double? worstSpreadM,
    String? fromId,
    String? toId,
    PlannedRoute? plan,
    String? error,
    bool clearPlan = false,
    bool clearError = false,
  }) => FloorMapState(
    status: status ?? this.status,
    buildingId: buildingId ?? this.buildingId,
    buildingName: buildingName ?? this.buildingName,
    graph: graph ?? this.graph,
    landmarks: landmarks ?? this.landmarks,
    routes: routes ?? this.routes,
    floors: floors ?? this.floors,
    activeFloorId: activeFloorId ?? this.activeFloorId,
    worstSpreadM: worstSpreadM ?? this.worstSpreadM,
    fromId: fromId ?? this.fromId,
    toId: toId ?? this.toId,
    plan: clearPlan ? null : plan ?? this.plan,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [
    status,
    buildingId,
    buildingName,
    graph,
    landmarks,
    routes,
    floors,
    activeFloorId,
    worstSpreadM,
    fromId,
    toId,
    plan,
    error,
  ];
}
