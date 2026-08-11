// Turtle layout — spec §6 A2.
//
// A contributor records only what they can honestly observe: how far they
// walked and which way they turned. That is a turtle program, and running it
// produces a floor plan. This is the whole map-generation algorithm — there is
// no geometry sensing anywhere in it, which is why it needs no ARCore and runs
// on any phone.
//
// Heading convention: 0° is +y ("up" on the map, the direction the contributor
// faced at the start). A positive turnDeg is a right turn towards +x, matching
// how the capture UI labels the buttons.
//
// The result is a *schematic*, not a survey. Angles come from six tapped
// buttons, not a compass, so a corridor that bends 80° is recorded as 90° and
// the geometry drifts. Spec §6 A3 is explicit that this is not to be fought
// with least-squares fitting; the drift is measured and reported instead — see
// [misclosureOf] and `FloorGraph.mergeWithDiagnostics`.

import 'dart:math' as math;

import '../../core/models/landmark.dart';
import '../../core/models/walk_route.dart';
import 'map_node.dart';

/// Lays [route] out in its own frame, starting at the origin facing 0°.
///
/// [landmarks] supplies each node's floor. A route referencing a landmark that
/// is not in the map still lays out — geometry does not need it — and inherits
/// the previous node's floor, so a partial landmark fetch degrades to a
/// slightly mislabelled plan rather than an exception.
List<MapNode> layout(
  WalkRoute route, [
  Map<String, Landmark> landmarks = const {},
]) {
  // Sorted before anything reads it: PostgREST does not guarantee embedded row
  // order, and the start landmark is taken from the first leg.
  final legs = [...route.steps]..sort((a, b) => a.seq.compareTo(b.seq));

  final startId =
      legs.isEmpty ? route.startLandmarkId : legs.first.fromLandmarkId;
  if (startId.isEmpty) return const [];

  var floorId = landmarks[startId]?.floorId ?? '';
  var x = 0.0;
  var y = 0.0;
  var headingDeg = 0.0;

  final nodes = <MapNode>[
    MapNode(landmarkId: startId, floorId: floorId, x: x, y: y),
  ];

  for (final leg in legs) {
    headingDeg += leg.turnDeg;

    final toFloor = landmarks[leg.toLandmarkId]?.floorId ?? floorId;

    if (toFloor == floorId) {
      final headingRad = headingDeg * math.pi / 180;
      x += leg.distanceM * math.sin(headingRad);
      y += leg.distanceM * math.cos(headingRad);
    } else {
      // A floor change — stairs or a lift. The distance is real (the
      // contributor climbed it, and guidance quotes it) but it is vertical,
      // so it must not displace the plan: consuming it horizontally would
      // push every floor-2 landmark eight metres down a ground-floor
      // corridor. The landing is placed directly above the stairwell, which
      // is where it physically is. Heading carries through, because the next
      // leg's turn was tapped relative to how the contributor emerged.
      floorId = toFloor;
    }

    nodes.add(
      MapNode(landmarkId: leg.toLandmarkId, floorId: floorId, x: x, y: y),
    );
  }

  return nodes;
}

/// How far a route's laid-out geometry fails to close, in metres, or null when
/// the route never revisits a landmark.
///
/// A corridor loop that returns to its start should land back on it. The gap is
/// accumulated turn and distance error, and spec §10 asks for it as a measured
/// result rather than a hidden flaw.
double? misclosureOf(List<MapNode> nodes) {
  double? worst;
  final seen = <String, MapNode>{};

  for (final node in nodes) {
    final first = seen[node.landmarkId];
    if (first == null) {
      seen[node.landmarkId] = node;
      continue;
    }
    // Same landmark, two placements: the distance between them is the error
    // the walk accumulated going round.
    final gap = first.distanceTo(node);
    if (worst == null || gap > worst) worst = gap;
  }

  return worst;
}
