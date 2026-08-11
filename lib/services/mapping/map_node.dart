import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// A landmark placed on a floor plane, in metres.
///
/// These are **derived geometry, not data**: recomputed from routes on every
/// load, never persisted and never sent anywhere. That is why they are plain
/// `Equatable` classes rather than freezed models — `CLAUDE.md`'s freezed rule
/// covers what repositories return, and nothing here is ever serialised.
///
/// Not screen coordinates either: `FloorPlanView` scales these to fit. Keeping
/// the layout in metres is what lets two routes merge — a pixel position
/// depends on the widget that drew it, a metre position does not.
///
/// The coordinate frame is arbitrary. Layout starts the first route at the
/// origin facing 0°, so absolute positions mean nothing; only the relative
/// geometry does.
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

  /// The same landmark on the same floor, relocated. Used by the merge to
  /// rotate and translate a route's own frame onto the shared one.
  MapNode moved(double newX, double newY) =>
      MapNode(landmarkId: landmarkId, floorId: floorId, x: newX, y: newY);

  /// Straight-line metres to [other] — A*'s heuristic, and the check that a
  /// merged graph has not folded two distant landmarks onto each other.
  double distanceTo(MapNode other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  List<Object?> get props => [landmarkId, floorId, x, y];

  @override
  String toString() =>
      'MapNode($landmarkId, $floorId, ${x.toStringAsFixed(2)}, '
      '${y.toStringAsFixed(2)})';
}
