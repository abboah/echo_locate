import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../core/models/walk_route.dart';

/// A landmark placed on the 2D schematic, in metres from the route's start.
///
/// Not screen coordinates: [FloorPlanPainter] scales these to fit. Keeping the
/// layout in metres is what lets two routes merge — a pixel position depends on
/// the widget that drew it, a metre position does not.
class MapNode extends Equatable {
  const MapNode({
    required this.landmarkId,
    required this.x,
    required this.y,
  });

  final String landmarkId;

  /// East of the start, in metres.
  final double x;

  /// North of the start, in metres.
  final double y;

  MapNode moved(double newX, double newY) =>
      MapNode(landmarkId: landmarkId, x: newX, y: newY);

  /// Straight-line metres to [other] — A*'s heuristic, and the check that a
  /// merged graph has not folded two distant landmarks onto each other.
  double distanceTo(MapNode other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  String toString() =>
      '$landmarkId(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';

  @override
  List<Object?> get props => [landmarkId, x, y];
}

/// Walks a recorded route as a turtle and returns where its landmarks lie.
///
/// Start at the origin facing 0° (north, +y). For each leg: rotate by
/// [RouteStep.turnDeg] — recorded as the turn taken *entering* the leg — then
/// advance [RouteStep.distanceM] and emit a node.
///
/// This is the whole map-generation algorithm. There is no geometry sensing
/// anywhere in it: the shape comes from what a contributor walked and the turns
/// they tapped, which is why it needs no ARCore and runs on any phone.
///
/// The result is a **schematic, not a survey**. Turns are quantised to 45°
/// multiples and distances come from step counts, so angular error accumulates
/// and a loop will not close cleanly. That is accepted rather than corrected —
/// see `floor_graph.dart` for why least-squares closure is not worth it here.
List<MapNode> layout(WalkRoute route) {
  if (route.steps.isEmpty) return const [];

  final ordered = [...route.steps]..sort((a, b) => a.seq.compareTo(b.seq));

  var heading = 0.0; // degrees clockwise from north
  var x = 0.0;
  var y = 0.0;

  final nodes = <MapNode>[
    MapNode(landmarkId: ordered.first.fromLandmarkId, x: 0, y: 0),
  ];

  for (final step in ordered) {
    heading += step.turnDeg;
    final radians = heading * math.pi / 180;
    x += step.distanceM * math.sin(radians);
    y += step.distanceM * math.cos(radians);
    nodes.add(MapNode(landmarkId: step.toLandmarkId, x: x, y: y));
  }

  return nodes;
}
