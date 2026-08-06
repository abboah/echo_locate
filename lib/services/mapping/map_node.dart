import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// A landmark placed on a floor plane, in metres.
///
/// These are **derived geometry, not data**: recomputed from routes on every
/// load, never persisted and never sent anywhere. That is why they are plain
/// `Equatable` classes rather than freezed models — `CLAUDE.md`'s freezed rule
/// covers what repositories return, and nothing here is ever serialised.
///
/// The coordinate frame is arbitrary. Layout starts the first route at the
/// origin facing 0°, so absolute positions mean nothing; only the relative
/// geometry does. Rendering fits whatever bounding box comes out (see
/// `floor_plan_painter.dart`).
class MapNode extends Equatable {
  const MapNode({
    required this.landmarkId,
    required this.floorId,
    required this.x,
    required this.y,
  });

  final String landmarkId;

  /// Which floor plane this node lies on. Nodes on different floors share an
  /// (x, y) frame but are never drawn or connected as if adjacent.
  final String floorId;

  /// Metres east of the frame origin.
  final double x;

  /// Metres north of the frame origin.
  final double y;

  MapNode copyWith({double? x, double? y}) => MapNode(
        landmarkId: landmarkId,
        floorId: floorId,
        x: x ?? this.x,
        y: y ?? this.y,
      );

  double distanceTo(MapNode other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));

  @override
  List<Object?> get props => [landmarkId, floorId, x, y];

  @override
  String toString() =>
      'MapNode($landmarkId, $floorId, ${x.toStringAsFixed(2)}, '
      '${y.toStringAsFixed(2)})';
}

/// A walkable connection between two landmarks, weighted by the distance a
/// contributor actually walked.
///
/// Undirected: guidance can traverse a leg in either direction, though doing so
/// backwards means the recorded instruction no longer applies (see
/// `route_planner.dart`).
class MapEdge extends Equatable {
  const MapEdge({
    required this.fromId,
    required this.toId,
    required this.distanceM,
  });

  final String fromId;
  final String toId;
  final double distanceM;

  /// Direction-independent identity, so the same corridor recorded by two
  /// contributors walking opposite ways is one edge, not two.
  String get key {
    final ends = [fromId, toId]..sort();
    return '${ends[0]}|${ends[1]}';
  }

  bool touches(String landmarkId) => fromId == landmarkId || toId == landmarkId;

  /// The landmark at the other end, or null if [landmarkId] is not an endpoint.
  String? otherEnd(String landmarkId) {
    if (fromId == landmarkId) return toId;
    if (toId == landmarkId) return fromId;
    return null;
  }

  @override
  List<Object?> get props => [key, distanceM];

  @override
  String toString() => 'MapEdge($fromId <-> $toId, ${distanceM}m)';
}

/// Every landmark and connection in one building, merged from all its recorded
/// routes.
///
/// Spans floors: `nodes` carry their own `floorId` and edges may cross between
/// them (a stairs leg does exactly that). The painter filters to one floor;
/// A* does not, because a route between floors is a normal thing to want.
class FloorGraph extends Equatable {
  const FloorGraph({required this.nodes, required this.edges});

  const FloorGraph.empty() : nodes = const {}, edges = const [];

  /// Landmark id → placed position.
  final Map<String, MapNode> nodes;

  final List<MapEdge> edges;

  bool get isEmpty => nodes.isEmpty;

  /// Distinct floors this graph covers, in no particular order — the caller
  /// orders them by the building's floor ordinals, which the graph does not
  /// know about.
  Set<String> get floorIds => nodes.values.map((n) => n.floorId).toSet();

  Iterable<MapNode> nodesOn(String floorId) =>
      nodes.values.where((n) => n.floorId == floorId);

  /// Edges with both ends on [floorId]. A stairs leg is deliberately excluded:
  /// drawing it on either floor would imply a corridor that is not there.
  Iterable<MapEdge> edgesOn(String floorId) => edges.where((e) {
        final from = nodes[e.fromId];
        final to = nodes[e.toId];
        return from?.floorId == floorId && to?.floorId == floorId;
      });

  Iterable<MapEdge> edgesFrom(String landmarkId) =>
      edges.where((e) => e.touches(landmarkId));

  @override
  List<Object?> get props => [nodes, edges];
}
