// Node snapping and graph merge — spec §6 A3.
//
// Routes in one building share landmarks: two walks through "floor 2
// stairwell" pass through the *same point*. Merging them is what turns a pile
// of recorded walks into a floor plan, and it is what lets A* find a path
// nobody walked end to end.

import 'dart:math' as math;

import '../../core/models/landmark.dart';
import '../../core/models/walk_route.dart';
import 'map_node.dart';
import 'route_layout.dart';

/// A merged graph plus the evidence of how well it merged.
///
/// [spreadM] is how far apart a landmark's separate placements were *before*
/// averaging — accumulated turn and distance error, made visible. Spec §10
/// asks for this as a reported measure, so it is returned rather than
/// discarded: a schematic that admits its own error is a result, one that
/// hides it is a lie.
class MergeResult {
  const MergeResult({
    required this.graph,
    required this.spreadM,
    required this.unanchoredRouteIds,
  });

  final FloorGraph graph;

  /// Landmark id → distance between its furthest-apart placements, in metres.
  /// Only landmarks seen by more than one route appear.
  final Map<String, double> spreadM;

  /// Routes that shared no landmark with anything already placed, so they sit
  /// in their own coordinate frame. Their geometry is internally consistent but
  /// unrelated to the rest — the painter must not draw them as if connected.
  final List<String> unanchoredRouteIds;

  double get worstSpreadM =>
      spreadM.values.fold<double>(0, (worst, s) => s > worst ? s : worst);
}

/// Merges every recorded route in a building into one graph — spec §6 A3.
///
/// Nodes are landmarks, edges are legs weighted by walked distance.
FloorGraph merge(List<WalkRoute> routes, List<Landmark> landmarks) =>
    mergeWithDiagnostics(routes, landmarks).graph;

/// [merge], keeping the error measurements it computes along the way.
MergeResult mergeWithDiagnostics(
  List<WalkRoute> routes,
  List<Landmark> landmarks,
) {
  final byId = {for (final l in landmarks) l.id: l};

  // Each route laid out in its own frame: origin at its own start, facing 0°.
  final frames = <String, List<MapNode>>{};
  for (final route in routes) {
    final nodes = layout(route, byId);
    if (nodes.isNotEmpty) frames[route.id] = nodes;
  }

  // Every placement of every landmark, in the shared frame.
  final placements = <String, List<MapNode>>{};
  final unanchored = <String>[];

  void place(List<MapNode> nodes) {
    for (final node in nodes) {
      (placements[node.landmarkId] ??= []).add(node);
    }
  }

  final pending = frames.keys.toList();

  // Anchor routes onto the shared frame one at a time, always taking a route
  // that overlaps what is already placed. Order matters: a route sharing two
  // landmarks can be rotated into place, one sharing none cannot be placed at
  // all, so deferring the isolated ones gives every route its best chance of
  // finding an anchor once its neighbours have landed.
  while (pending.isNotEmpty) {
    String? next;
    var bestOverlap = 0;

    for (final routeId in pending) {
      final overlap = frames[routeId]!
          .map((n) => n.landmarkId)
          .toSet()
          .where(placements.containsKey)
          .length;
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        next = routeId;
      }
    }

    if (next == null) {
      // Nothing overlaps. Seed the frame with the first route still pending —
      // on the first iteration this is simply "the first route wins the
      // origin"; later it means a genuinely disconnected component.
      next = pending.first;
      if (placements.isNotEmpty) unanchored.add(next);
      place(frames[next]!);
    } else {
      place(_align(frames[next]!, placements));
    }

    pending.remove(next);
  }

  // Average duplicates. No least-squares: spec §6 A3 says loops will not close
  // and forbids fighting it. Averaging is the honest compromise — every
  // observation counts equally and the artifact stays a schematic.
  final nodes = <String, MapNode>{};
  final spread = <String, double>{};

  placements.forEach((landmarkId, seen) {
    final meanX = seen.fold<double>(0, (s, n) => s + n.x) / seen.length;
    final meanY = seen.fold<double>(0, (s, n) => s + n.y) / seen.length;

    nodes[landmarkId] = MapNode(
      landmarkId: landmarkId,
      // The landmark itself is authoritative about its floor; a placement's
      // floor is only the inherited fallback from layout().
      floorId: byId[landmarkId]?.floorId ?? seen.first.floorId,
      x: meanX,
      y: meanY,
    );

    if (seen.length > 1) {
      var worst = 0.0;
      for (var i = 0; i < seen.length; i++) {
        for (var j = i + 1; j < seen.length; j++) {
          final gap = seen[i].distanceTo(seen[j]);
          if (gap > worst) worst = gap;
        }
      }
      if (worst > 0) spread[landmarkId] = worst;
    }
  });

  return MergeResult(
    graph: FloorGraph(nodes: nodes, edges: _edgesOf(routes)),
    spreadM: spread,
    unanchoredRouteIds: unanchored,
  );
}

/// Rotates and translates [nodes] so its landmarks line up with where earlier
/// routes already put them.
///
/// Two shared landmarks fix both rotation and position. One fixes position
/// only, so the route keeps its own heading — which is a guess, but a better
/// one than leaving it at a frame origin metres away from where it belongs.
///
/// Only the first one or two correspondences are used. Fitting all of them
/// least-squares would spread the error evenly instead of concentrating it,
/// which reads as a plan that is uniformly slightly wrong rather than one that
/// is right near its anchors — and spec §6 A3 rules it out regardless.
List<MapNode> _align(List<MapNode> nodes, Map<String, List<MapNode>> placed) {
  MapNode? anchorOf(String landmarkId) {
    final seen = placed[landmarkId];
    return seen == null || seen.isEmpty ? null : seen.first;
  }

  final shared = nodes.where((n) => placed.containsKey(n.landmarkId)).toList();
  if (shared.isEmpty) return nodes;

  final sourceA = shared.first;
  final targetA = anchorOf(sourceA.landmarkId)!;

  // A second correspondence far enough away to define a direction. Adjacent
  // landmarks a few centimetres apart would make the angle noise.
  MapNode? sourceB;
  for (final candidate in shared.skip(1)) {
    if (candidate.distanceTo(sourceA) > 0.5) {
      sourceB = candidate;
      break;
    }
  }

  var rotation = 0.0;
  if (sourceB != null) {
    final targetB = anchorOf(sourceB.landmarkId)!;
    if (targetB.distanceTo(targetA) > 0.5) {
      final sourceAngle =
          math.atan2(sourceB.x - sourceA.x, sourceB.y - sourceA.y);
      final targetAngle =
          math.atan2(targetB.x - targetA.x, targetB.y - targetA.y);
      rotation = targetAngle - sourceAngle;
    }
  }

  final cos = math.cos(rotation);
  final sin = math.sin(rotation);

  return [
    for (final node in nodes)
      () {
        final dx = node.x - sourceA.x;
        final dy = node.y - sourceA.y;
        return MapNode(
          landmarkId: node.landmarkId,
          floorId: node.floorId,
          x: targetA.x + dx * cos + dy * sin,
          y: targetA.y - dx * sin + dy * cos,
        );
      }(),
  ];
}

/// One edge per distinct corridor, whichever direction it was walked.
///
/// When several contributors record the same leg their distances disagree by a
/// stride or two; the mean is used, which is the only defensible answer without
/// deciding whose walk was more careful.
List<MapEdge> _edgesOf(List<WalkRoute> routes) {
  final distances = <String, List<double>>{};
  final ends = <String, MapEdge>{};

  for (final route in routes) {
    for (final leg in route.steps) {
      if (leg.fromLandmarkId == leg.toLandmarkId) continue;
      final edge = MapEdge(
        fromId: leg.fromLandmarkId,
        toId: leg.toLandmarkId,
        distanceM: leg.distanceM,
      );
      (distances[edge.key] ??= []).add(leg.distanceM);
      ends.putIfAbsent(edge.key, () => edge);
    }
  }

  return [
    for (final entry in ends.entries)
      MapEdge(
        fromId: entry.value.fromId,
        toId: entry.value.toId,
        distanceM: distances[entry.key]!.reduce((a, b) => a + b) /
            distances[entry.key]!.length,
      ),
  ];
}
