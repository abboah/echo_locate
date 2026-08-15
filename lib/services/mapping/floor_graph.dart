// Node snapping and graph merge — spec §6 A3.
//
// Routes in one building share landmarks: two walks through "floor 2
// stairwell" pass through the *same point*. Merging them is what turns a pile
// of recorded walks into a floor plan, and it is what lets A* answer a question
// nobody walked end to end — it can leave one contributor's route and join
// another's where they cross.

import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../core/models/landmark.dart';
import '../../core/models/traced_plan.dart';
import '../../core/models/walk_route.dart';
import 'map_node.dart';
import 'route_layout.dart';

/// A corridor between two landmarks, as somebody actually walked it.
///
/// Undirected for traversal — a corridor walked north can be walked south —
/// but the recorded [instruction] is not. "Turn right at the help desk" read
/// backwards sends a blind user the wrong way, so instructions are kept per
/// direction and [instructionFor] returns nothing when the leg is traversed a
/// way nobody recorded. The caller says something neutral instead.
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

  bool touches(String id) => fromId == id || toId == id;

  String otherEnd(String id) => id == fromId ? toId : fromId;

  /// Direction-independent identity, so the same corridor recorded by two
  /// contributors walking opposite ways is one edge, not two.
  String get key {
    final ends = [fromId, toId]..sort();
    return '${ends[0]}|${ends[1]}';
  }

  /// The recorded wording for walking away from [origin], or null when this
  /// leg has only ever been recorded the other way round.
  String? instructionFor(String origin) =>
      origin == fromId ? instruction : reverseInstruction;

  @override
  List<Object?> get props => [
    fromId,
    toId,
    distanceM,
    instruction,
    reverseInstruction,
    turnDeg,
  ];

  @override
  String toString() => 'GraphEdge($fromId <-> $toId, ${distanceM}m)';
}

/// A landmark one leg away, and the leg that gets there.
class Neighbour {
  const Neighbour({required this.landmarkId, required this.edge});

  final String landmarkId;
  final GraphEdge edge;

  double get distanceM => edge.distanceM;
}

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
  /// in their own coordinate frame, parked clear of the rest. Their geometry is
  /// internally consistent but unrelated — the painter must not draw them as if
  /// connected.
  final List<String> unanchoredRouteIds;

  double get worstSpreadM =>
      spreadM.values.fold<double>(0, (worst, s) => s > worst ? s : worst);
}

/// Every recorded walk in a building, stitched into one navigable map.
///
/// Nodes are landmarks positioned in metres, edges are the corridors between
/// them. Spans floors: nodes carry their own [MapNode.floorId] and edges may
/// cross between them (a stairs leg does exactly that). The painter filters to
/// one floor; A* does not, because a route between floors is a normal thing to
/// want.
///
/// **This is a schematic, not a survey.** Positions come from tapped turns and
/// step counts, so angular error accumulates and loops do not close. Duplicate
/// sightings of a landmark are averaged and the error is left standing and
/// *reported* ([MergeResult.spreadM]): least-squares closure would buy prettier
/// geometry, and geometry is not what anybody navigates by here. Distances
/// along edges stay exactly as recorded — those are what guidance speaks, and
/// they are the numbers that must be right.
class FloorGraph {
  FloorGraph({required this.nodes, required this.edges, this.metric = true})
    : _adjacency = _buildAdjacency(edges);

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

  /// Distinct floors this graph covers, in no particular order — the caller
  /// orders them by the building's floor ordinals, which the graph does not
  /// know about.
  Set<String> get floorIds => nodes.values.map((n) => n.floorId).toSet();

  Iterable<MapNode> nodesOn(String floorId) =>
      nodes.values.where((n) => n.floorId == floorId);

  /// Edges with both ends on [floorId]. A stairs leg is deliberately excluded:
  /// drawing it on either floor would imply a corridor that is not there.
  Iterable<GraphEdge> edgesOn(String floorId) => edges.where((e) {
    final from = nodes[e.fromId];
    final to = nodes[e.toId];
    return from?.floorId == floorId && to?.floorId == floorId;
  });

  Iterable<GraphEdge> edgesFrom(String landmarkId) =>
      edges.where((e) => e.touches(landmarkId));

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

  /// Stitches recorded routes into one map, keeping only the graph.
  static FloorGraph merge(
    List<WalkRoute> routes, [
    Map<String, Landmark> landmarks = const {},
  ]) => mergeWithDiagnostics(routes, landmarks).graph;

  /// [merge], keeping the error measurements it computes along the way.
  ///
  /// Each route is laid out in its own frame ([layout] starts every walk at the
  /// origin facing 0°), so a route cannot simply be dropped onto the map: it is
  /// first rotated and translated onto the landmarks it shares with what is
  /// already placed. One shared landmark fixes position, two fix rotation, and
  /// a route sharing nothing is parked clear of the rest rather than stacked on
  /// top of it — an unconnected wing of a building is a real thing to draw.
  ///
  /// Routes are placed most-overlapping first, so capture order does not decide
  /// whether a building comes out as one map or three: a route that shares
  /// nothing yet may share something once a later route lands.
  static MergeResult mergeWithDiagnostics(
    List<WalkRoute> routes, [
    Map<String, Landmark> landmarks = const {},
  ]) {
    if (routes.isEmpty) {
      return const MergeResult(
        graph: empty,
        spreadM: {},
        unanchoredRouteIds: [],
      );
    }

    // Indexed by position, never by route id: ids are unique in Postgres but
    // nothing here enforces it, and keying on them would silently drop a route
    // that shares an id with another — losing whole wings of a building rather
    // than failing loudly.
    final frames = <({String routeId, List<MapNode> nodes})>[];
    for (final route in routes) {
      final nodes = layout(route, landmarks);
      if (nodes.isNotEmpty) frames.add((routeId: route.id, nodes: nodes));
    }

    // Every placement of every landmark, in the shared frame.
    final placements = <String, List<MapNode>>{};
    final unanchored = <String>[];

    void place(List<MapNode> nodes) {
      for (final node in nodes) {
        (placements[node.landmarkId] ??= []).add(node);
      }
    }

    MapNode? placedPosition(String id) {
      final seen = placements[id];
      if (seen == null || seen.isEmpty) return null;
      final x = seen.map((n) => n.x).reduce((a, b) => a + b) / seen.length;
      final y = seen.map((n) => n.y).reduce((a, b) => a + b) / seen.length;
      return seen.first.moved(x, y);
    }

    final pending = [for (var i = 0; i < frames.length; i++) i];

    // Always take the route that overlaps what is already placed the most: a
    // route sharing two landmarks can be rotated into place, one sharing none
    // cannot be placed at all, so deferring the isolated ones gives every route
    // its best chance of finding an anchor once its neighbours have landed.
    while (pending.isNotEmpty) {
      int? next;
      var bestOverlap = 0;

      for (final index in pending) {
        final overlap = frames[index].nodes
            .map((n) => n.landmarkId)
            .toSet()
            .where(placements.containsKey)
            .length;
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          next = index;
        }
      }

      if (next != null) {
        place(_align(frames[next].nodes, placedPosition));
      } else {
        // Nothing overlaps anything placed.
        next = pending.first;
        if (placements.isEmpty) {
          // The first route defines the frame everything else is fitted to.
          place(frames[next].nodes);
        } else {
          // A separate wing, or a building whose routes have not been joined up
          // yet. Park it clear of what is already drawn so they do not render
          // on top of each other.
          unanchored.add(frames[next].routeId);
          place(_parked(frames[next].nodes, placements));
        }
      }

      pending.remove(next);
    }

    // Average duplicates. No least-squares: spec §6 A3 says loops will not close
    // and forbids fighting it. Averaging is the honest compromise — every
    // observation counts equally and the artifact stays a schematic.
    final nodes = <String, MapNode>{};
    final spread = <String, double>{};

    placements.forEach((landmarkId, seen) {
      final placed = placedPosition(landmarkId)!;
      nodes[landmarkId] = MapNode(
        landmarkId: landmarkId,
        // The landmark itself is authoritative about its floor; a placement's
        // floor is only the inherited fallback from layout().
        floorId: landmarks[landmarkId]?.floorId ?? placed.floorId,
        x: placed.x,
        y: placed.y,
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
        node.ref: MapNode(
          landmarkId: node.ref,
          floorId: node.floorId,
          x: node.x * scale,
          y: node.y * scale,
        ),
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

  /// Shifts a route that anchors to nothing clear of everything already placed.
  static List<MapNode> _parked(
    List<MapNode> local,
    Map<String, List<MapNode>> placements,
  ) {
    final placedMaxX = placements.values
        .expand((s) => s)
        .map((n) => n.x)
        .reduce(math.max);
    final localMinX = local.map((n) => n.x).reduce(math.min);
    final shift = placedMaxX + _disconnectedGapM - localMinX;
    return [for (final node in local) node.moved(node.x + shift, node.y)];
  }

  /// Rotates and translates a freshly laid-out route onto the placed frame.
  ///
  /// Only the first one or two correspondences are used. Fitting all of them
  /// least-squares would spread the error evenly instead of concentrating it,
  /// which reads as a plan that is uniformly slightly wrong rather than one
  /// that is right near its anchors — and spec §6 A3 rules it out regardless.
  static List<MapNode> _align(
    List<MapNode> local,
    MapNode? Function(String) placedPosition,
  ) {
    final anchors = [
      for (final node in local)
        if (placedPosition(node.landmarkId) != null) node,
    ];
    if (anchors.isEmpty) return local;

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
    if (pivot != null && best > 0.5) {
      final pivotPlaced = placedPosition(pivot.landmarkId)!;
      final placedSpan = pivotPlaced.distanceTo(anchorPlaced);
      if (placedSpan > 0.5) {
        rotation =
            math.atan2(
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
        (a.compareTo(b) <= 0 ? '$a $b' : '$b $a');

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
        wording['${step.fromLandmarkId} ${step.toLandmarkId}'] ??=
            step.instruction;
      }
    }

    return [
      for (final entry in firstSeen.entries)
        GraphEdge(
          fromId: entry.value.from,
          toId: entry.value.to,
          distanceM:
              distances[entry.key]!.reduce((a, b) => a + b) /
              distances[entry.key]!.length,
          instruction: wording['${entry.value.from} ${entry.value.to}'],
          reverseInstruction: wording['${entry.value.to} ${entry.value.from}'],
          turnDeg: entry.value.turnDeg,
        ),
    ];
  }

  static Map<String, List<Neighbour>> _buildAdjacency(List<GraphEdge> edges) {
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
