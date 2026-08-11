import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../core/models/traced_plan.dart';
import '../../core/models/walk_route.dart';
import 'route_layout.dart';

/// A corridor between two landmarks, as somebody actually walked it.
///
/// Undirected for traversal — a corridor walked north can be walked south —
/// but the recorded [instruction] is not. "Turn right at the help desk" read
/// backwards sends a blind user the wrong way, so instructions are kept per
/// direction and [instructionFor] returns nothing when the leg is traversed a
/// way nobody recorded. The caller generates a neutral instruction instead.
class GraphEdge extends Equatable {
  const GraphEdge({
    required this.fromId,
    required this.toId,
    required this.distanceM,
    this.instruction,
    this.reverseInstruction,
    this.turnDeg = 0,
  });

  final String fromId;
  final String toId;
  final double distanceM;

  /// As recorded walking [fromId] → [toId].
  final String? instruction;

  /// As recorded by some other contributor walking [toId] → [fromId].
  final String? reverseInstruction;

  final int turnDeg;

  bool connects(String a, String b) =>
      (fromId == a && toId == b) || (fromId == b && toId == a);

  String otherEnd(String id) => id == fromId ? toId : fromId;

  /// The recorded wording for walking away from [origin], or null when this
  /// leg has only ever been recorded the other way round.
  String? instructionFor(String origin) =>
      origin == fromId ? instruction : reverseInstruction;

  @override
  List<Object?> get props =>
      [fromId, toId, distanceM, instruction, reverseInstruction, turnDeg];
}

/// A landmark one leg away, and the leg that gets there.
class Neighbour {
  const Neighbour({required this.landmarkId, required this.edge});

  final String landmarkId;
  final GraphEdge edge;

  double get distanceM => edge.distanceM;
}

/// Every recorded walk in a building, stitched into one navigable map.
///
/// Nodes are landmarks positioned in metres, edges are the corridors between
/// them. Two routes through the same stairwell pass through the *same node*,
/// which is what lets A* answer a question nobody walked: it can leave one
/// contributor's route and join another's where they cross.
///
/// **This is a schematic, not a survey.** Positions come from tapped turns and
/// step counts, so angular error accumulates and loops do not close. Duplicate
/// sightings of a landmark are averaged and the error is left standing:
/// least-squares closure would buy prettier geometry, and geometry is not what
/// anybody navigates by here. Distances along edges stay exactly as recorded —
/// those are what guidance speaks, and they are the numbers that must be right.
class FloorGraph {
  FloorGraph({required this.nodes, required this.edges, this.metric = true})
      : _adjacency = _buildAdjacency(nodes, edges);

  /// Landmark id → position, relative to the first route's start.
  final Map<String, MapNode> nodes;
  final List<GraphEdge> edges;

  /// Whether [GraphEdge.distanceM] really is metres.
  ///
  /// False for a graph traced off a floor plan nobody has measured, where the
  /// lengths are in arbitrary plan units. **A\* does not care** — it compares
  /// edges against each other, and scaling every edge by the same unknown
  /// constant picks the same route — but anything that speaks a distance aloud
  /// does. Guidance checks this before promising "about twenty steps", because
  /// a step count computed from plan units is a confidently wrong number in a
  /// blind user's ear.
  final bool metric;

  final Map<String, List<Neighbour>> _adjacency;

  static const FloorGraph empty = FloorGraph._empty();

  const FloorGraph._empty()
      : nodes = const {},
        edges = const [],
        metric = true,
        _adjacency = const {};

  bool get isEmpty => nodes.isEmpty;

  List<Neighbour> neighboursOf(String landmarkId) =>
      _adjacency[landmarkId] ?? const [];

  MapNode? nodeOf(String landmarkId) => nodes[landmarkId];

  /// Every landmark connected to [landmarkId], itself included. Empty when the
  /// landmark is not on the map at all.
  Set<String> reachableFrom(String landmarkId) {
    if (!nodes.containsKey(landmarkId)) return const {};
    final seen = <String>{landmarkId};
    final queue = <String>[landmarkId];
    while (queue.isNotEmpty) {
      for (final neighbour in neighboursOf(queue.removeAt(0))) {
        if (seen.add(neighbour.landmarkId)) queue.add(neighbour.landmarkId);
      }
    }
    return seen;
  }

  /// Extent of the laid-out map in metres, for fitting it to a canvas.
  ({double minX, double minY, double maxX, double maxY}) get bounds {
    if (nodes.isEmpty) return (minX: 0, minY: 0, maxX: 0, maxY: 0);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final node in nodes.values) {
      minX = math.min(minX, node.x);
      minY = math.min(minY, node.y);
      maxX = math.max(maxX, node.x);
      maxY = math.max(maxY, node.y);
    }
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// Stitches recorded routes into one map.
  ///
  /// Each route is laid out in its own frame ([layout] starts every walk at the
  /// origin facing north), so a route cannot simply be dropped onto the map: it
  /// is first rotated and translated onto the landmarks it shares with what is
  /// already placed. One shared landmark fixes position, two fix rotation, and
  /// a route sharing nothing is parked clear of the rest rather than stacked on
  /// top of it — an unconnected wing of a building is a real thing to draw.
  ///
  /// Placement iterates to a fixed point so capture order does not decide
  /// whether a building comes out as one map or three: a route that shares
  /// nothing yet may share something once a later route lands.
  static FloorGraph merge(List<WalkRoute> routes) {
    if (routes.isEmpty) return empty;

    final samples = <String, List<MapNode>>{};
    final pending = [...routes];

    void absorb(List<MapNode> placed) {
      for (final node in placed) {
        (samples[node.landmarkId] ??= []).add(node);
      }
    }

    MapNode? placedPosition(String id) {
      final seen = samples[id];
      if (seen == null || seen.isEmpty) return null;
      final x = seen.map((n) => n.x).reduce((a, b) => a + b) / seen.length;
      final y = seen.map((n) => n.y).reduce((a, b) => a + b) / seen.length;
      return MapNode(landmarkId: id, x: x, y: y);
    }

    var placedAny = true;
    while (pending.isNotEmpty && placedAny) {
      placedAny = false;
      for (final route in [...pending]) {
        final local = layout(route);
        if (local.isEmpty) {
          pending.remove(route);
          continue;
        }
        if (samples.isEmpty) {
          // The first route defines the frame everything else is fitted to.
          absorb(local);
          pending.remove(route);
          placedAny = true;
          continue;
        }
        final anchors = [
          for (final node in local)
            if (placedPosition(node.landmarkId) != null) node,
        ];
        if (anchors.isEmpty) continue;
        absorb(_align(local, anchors, placedPosition));
        pending.remove(route);
        placedAny = true;
      }
    }

    // Whatever is left shares no landmark with anything: separate wings, or a
    // building whose routes have not been joined up yet. Park each clear of
    // what is already drawn so they do not render on top of each other.
    for (final route in pending) {
      final local = layout(route);
      if (local.isEmpty) continue;
      final shift = samples.isEmpty
          ? 0.0
          : samples.values
                  .expand((s) => s)
                  .map((n) => n.x)
                  .reduce(math.max) +
              _disconnectedGapM -
              local.map((n) => n.x).reduce(math.min);
      absorb([for (final node in local) node.moved(node.x + shift, node.y)]);
    }

    return FloorGraph(
      nodes: {
        for (final id in samples.keys) id: placedPosition(id)!,
      },
      edges: _edgesOf(routes),
    );
  }

  /// Builds a graph straight from a traced floor plan.
  ///
  /// The counterpart to [merge], and the reason both exist: [merge] *recovers*
  /// geometry from recorded walks, whose positions are chained from step counts
  /// and tapped turns and therefore drift — the schematic caveat above. A
  /// traced plan already carries absolute coordinates, so there is nothing to
  /// lay out, rotate, or average away. The graph is the plan.
  ///
  /// Edge lengths are the distance between the two ends, so a plan cannot hold
  /// an edge whose stated length disagrees with where it was drawn. Edges carry
  /// no wording: guidance generates a neutral instruction for a leg nobody
  /// phrased, the same path a direction walked only one way already takes.
  ///
  /// Usually **unitless** — see [metric]. Nobody is asked to measure the plan,
  /// and routing is identical either way.
  static FloorGraph fromPlan(TracedPlan plan) {
    if (plan.nodes.isEmpty) return empty;

    final scale = plan.metresPerUnit ?? 1;
    final nodes = {
      for (final node in plan.nodes)
        node.ref:
            MapNode(landmarkId: node.ref, x: node.x * scale, y: node.y * scale),
    };

    final edges = <GraphEdge>[];
    final seen = <String>{};
    for (final edge in plan.edges) {
      final from = nodes[edge.fromRef];
      final to = nodes[edge.toRef];
      // An edge naming a node the plan does not contain is dropped rather than
      // allowed to put a nameless, unroutable id into the adjacency map — the
      // same failure a half-saved capture caused before refs were resolved.
      if (from == null || to == null || edge.fromRef == edge.toRef) continue;
      final key = edge.fromRef.compareTo(edge.toRef) <= 0
          ? '${edge.fromRef} ${edge.toRef}'
          : '${edge.toRef} ${edge.fromRef}';
      // One corridor, however many times it was drawn: a duplicate would give
      // A* a parallel edge to weigh and draw the same line twice.
      if (!seen.add(key)) continue;
      edges.add(
        GraphEdge(
          fromId: edge.fromRef,
          toId: edge.toRef,
          distanceM: from.distanceTo(to),
        ),
      );
    }

    return FloorGraph(
      nodes: nodes,
      edges: edges,
      metric: plan.metresPerUnit != null,
    );
  }

  /// Metres left between two route groups that share no landmark.
  static const double _disconnectedGapM = 20;

  /// Rotates and translates a freshly laid-out route onto the placed frame.
  static List<MapNode> _align(
    List<MapNode> local,
    List<MapNode> anchors,
    MapNode? Function(String) placedPosition,
  ) {
    final anchor = anchors.first;
    final anchorPlaced = placedPosition(anchor.landmarkId)!;

    // A second shared landmark gives the rotation. The furthest one is used:
    // the angle between two landmarks a metre apart is mostly noise, and that
    // noise would be applied to the whole route.
    MapNode? pivot;
    var best = 0.0;
    for (final candidate in anchors.skip(1)) {
      final span = candidate.distanceTo(anchor);
      if (span > best) {
        best = span;
        pivot = candidate;
      }
    }

    var rotation = 0.0;
    if (pivot != null && best > 0.01) {
      final pivotPlaced = placedPosition(pivot.landmarkId)!;
      final placedSpan = pivotPlaced.distanceTo(anchorPlaced);
      if (placedSpan > 0.01) {
        rotation = math.atan2(
              pivotPlaced.y - anchorPlaced.y,
              pivotPlaced.x - anchorPlaced.x,
            ) -
            math.atan2(pivot.y - anchor.y, pivot.x - anchor.x);
      }
    }

    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    return [
      for (final node in local)
        node.moved(
          anchorPlaced.x +
              (node.x - anchor.x) * cos -
              (node.y - anchor.y) * sin,
          anchorPlaced.y +
              (node.x - anchor.x) * sin +
              (node.y - anchor.y) * cos,
        ),
    ];
  }

  /// One edge per corridor, however many people walked it.
  ///
  /// Two recordings of the same leg are one corridor, not two: left separate
  /// they would draw the map twice over and give A* a parallel edge to weigh.
  /// Distances are averaged across every recording — contributors disagree by
  /// a metre or two and none of them is the authority — while the wording is
  /// kept per direction, since an instruction reversed is a wrong turn.
  static List<GraphEdge> _edgesOf(List<WalkRoute> routes) {
    String pairKey(String a, String b) =>
        (a.compareTo(b) <= 0 ? '$a $b' : '$b $a');

    final firstSeen = <String, ({String from, String to, int turnDeg})>{};
    final distances = <String, List<double>>{};
    final wording = <String, String>{};

    for (final route in routes) {
      for (final step in route.steps) {
        if (step.fromLandmarkId == step.toLandmarkId) continue;
        final key = pairKey(step.fromLandmarkId, step.toLandmarkId);
        firstSeen[key] ??= (
          from: step.fromLandmarkId,
          to: step.toLandmarkId,
          turnDeg: step.turnDeg,
        );
        (distances[key] ??= []).add(step.distanceM);
        wording['${step.fromLandmarkId} ${step.toLandmarkId}'] ??=
            step.instruction;
      }
    }

    return [
      for (final entry in firstSeen.entries)
        GraphEdge(
          fromId: entry.value.from,
          toId: entry.value.to,
          distanceM: distances[entry.key]!.reduce((a, b) => a + b) /
              distances[entry.key]!.length,
          instruction: wording['${entry.value.from} ${entry.value.to}'],
          reverseInstruction:
              wording['${entry.value.to} ${entry.value.from}'],
          turnDeg: entry.value.turnDeg,
        ),
    ];
  }

  static Map<String, List<Neighbour>> _buildAdjacency(
    Map<String, MapNode> nodes,
    List<GraphEdge> edges,
  ) {
    final adjacency = <String, List<Neighbour>>{};
    for (final edge in edges) {
      adjacency
          .putIfAbsent(edge.fromId, () => [])
          .add(Neighbour(landmarkId: edge.toId, edge: edge));
      adjacency
          .putIfAbsent(edge.toId, () => [])
          .add(Neighbour(landmarkId: edge.fromId, edge: edge));
    }
    return adjacency;
  }
}
