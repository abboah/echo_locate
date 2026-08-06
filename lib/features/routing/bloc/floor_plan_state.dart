part of 'floor_plan_bloc.dart';

enum FloorPlanStatus { initial, loading, success, failure }

/// Why a building has no plan to show. The screen says which — "nobody has
/// mapped this yet" and "you are offline" call for different responses, and
/// collapsing them into one empty state tells the user nothing.
enum FloorPlanEmptyReason { none, noRoutes, unreachableDestination }

final class FloorPlanState extends Equatable {
  const FloorPlanState({
    this.status = FloorPlanStatus.initial,
    this.graph = const FloorGraph.empty(),
    this.landmarks = const {},
    this.floors = const [],
    this.activeFloorId,
    this.route,
    this.currentLandmarkId,
    this.emptyReason = FloorPlanEmptyReason.none,
    this.worstSpreadM = 0,
    this.error,
  });

  final FloorPlanStatus status;
  final FloorGraph graph;
  final Map<String, Landmark> landmarks;

  /// Floors that carry landmarks, in building order, for the switcher.
  final List<BuildingFloor> floors;

  final String? activeFloorId;

  /// The route being shown, recorded or planned.
  final WalkRoute? route;

  final String? currentLandmarkId;
  final FloorPlanEmptyReason emptyReason;

  /// Worst disagreement between two recordings of the same landmark, in
  /// metres. Surfaced so a contributor can see their capture is drifting
  /// rather than wondering why the plan looks bent.
  final double worstSpreadM;

  final String? error;

  /// Nodes on the floor being shown.
  List<MapNode> get visibleNodes => activeFloorId == null
      ? const []
      : graph.nodesOn(activeFloorId!).toList(growable: false);

  List<MapEdge> get visibleEdges => activeFloorId == null
      ? const []
      : graph.edgesOn(activeFloorId!).toList(growable: false);

  /// The leg the user is on, or the first, when a route is shown.
  RouteStep? get currentStep {
    final steps = route?.steps;
    if (steps == null || steps.isEmpty) return null;
    if (currentLandmarkId == null) return steps.first;

    for (final step in steps) {
      if (step.fromLandmarkId == currentLandmarkId) return step;
    }
    // Standing at a landmark no leg leaves from means it is the end of the
    // route — the leg just finished, not the first one. Announcing "leg 1 of
    // 5" to somebody who has arrived is worse than saying nothing.
    for (final step in steps.reversed) {
      if (step.toLandmarkId == currentLandmarkId) return step;
    }
    return steps.first;
  }

  /// Whether the user is standing at the route's final landmark.
  bool get hasArrived {
    final steps = route?.steps;
    if (steps == null || steps.isEmpty || currentLandmarkId == null) {
      return false;
    }
    return steps.last.toLandmarkId == currentLandmarkId;
  }

  bool get hasRoute => (route?.steps.isNotEmpty ?? false);

  FloorPlanState copyWith({
    FloorPlanStatus? status,
    FloorGraph? graph,
    Map<String, Landmark>? landmarks,
    List<BuildingFloor>? floors,
    String? activeFloorId,
    WalkRoute? route,
    bool clearRoute = false,
    String? currentLandmarkId,
    FloorPlanEmptyReason? emptyReason,
    double? worstSpreadM,
    String? error,
    bool clearError = false,
  }) {
    return FloorPlanState(
      status: status ?? this.status,
      graph: graph ?? this.graph,
      landmarks: landmarks ?? this.landmarks,
      floors: floors ?? this.floors,
      activeFloorId: activeFloorId ?? this.activeFloorId,
      route: clearRoute ? null : (route ?? this.route),
      currentLandmarkId: currentLandmarkId ?? this.currentLandmarkId,
      emptyReason: emptyReason ?? this.emptyReason,
      worstSpreadM: worstSpreadM ?? this.worstSpreadM,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        status,
        graph,
        landmarks,
        floors,
        activeFloorId,
        route,
        currentLandmarkId,
        emptyReason,
        worstSpreadM,
        error,
      ];
}
