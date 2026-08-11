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

  FloorMapState copyWith({
    FloorMapStatus? status,
    String? buildingId,
    String? buildingName,
    FloorGraph? graph,
    List<Landmark>? landmarks,
    List<WalkRoute>? routes,
    String? fromId,
    String? toId,
    PlannedRoute? plan,
    String? error,
    bool clearPlan = false,
    bool clearError = false,
  }) =>
      FloorMapState(
        status: status ?? this.status,
        buildingId: buildingId ?? this.buildingId,
        buildingName: buildingName ?? this.buildingName,
        graph: graph ?? this.graph,
        landmarks: landmarks ?? this.landmarks,
        routes: routes ?? this.routes,
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
        fromId,
        toId,
        plan,
        error,
      ];
}
