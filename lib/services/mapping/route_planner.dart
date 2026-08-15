// A* over the landmark graph — spec §6 A4.
//
// This is what the crowdsourcing is *for*. Contributors record walks to
// particular destinations; merging them into one graph and searching it means
// the app can answer routes nobody recorded — 204 to 209 via the junction they
// share — so coverage grows faster than the number of walks.
//
// Finding the path is the easy half. The hard half is that a path spliced from
// fragments of other people's walks cannot blindly reuse their words or their
// turns: an instruction recorded walking north is false walking south, and a
// turn recorded after one approach is wrong after a different one. Both are
// handled below.

import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../core/models/landmark.dart';
import '../../core/models/walk_route.dart';
import 'floor_graph.dart';
import 'map_node.dart';

/// One leg of a route the user is about to walk.
///
/// [instruction] is null when this leg is being walked in a direction — or from
/// an approach — nobody recorded: the corridor is known, the wording for it is
/// not. Guidance says something neutral there ("continue about twenty steps to
/// the stairwell") rather than replaying somebody else's turn instruction into
/// a situation it was never true of.
class PlannedLeg extends Equatable {
  const PlannedLeg({
    required this.fromLandmarkId,
    required this.toLandmarkId,
    required this.distanceM,
    this.instruction,
    this.turnDeg = 0,
  });

  final String fromLandmarkId;
  final String toLandmarkId;
  final double distanceM;
  final String? instruction;
  final int turnDeg;

  @override
  List<Object?> get props => [
    fromLandmarkId,
    toLandmarkId,
    distanceM,
    instruction,
    turnDeg,
  ];
}

/// A route to walk, whether recorded whole or assembled from several walks.
///
/// Guidance takes this rather than [WalkRoute] so following a contributor's
/// recording and following an A* path are the same code path — the second is
/// the harder case, and it would rot if only the demo exercised it.
class PlannedRoute extends Equatable {
  const PlannedRoute({required this.legs, this.synthesised = false});

  final List<PlannedLeg> legs;

  /// True when no single contributor walked this: it was stitched from more
  /// than one recording. Worth saying out loud in the report, and worth
  /// leaning harder on landmark confirmation for.
  final bool synthesised;

  /// A recorded walk, followed exactly as it was captured.
  factory PlannedRoute.fromRecorded(WalkRoute route) {
    final ordered = [...route.steps]..sort((a, b) => a.seq.compareTo(b.seq));
    return PlannedRoute(
      legs: [
        for (final step in ordered)
          PlannedLeg(
            fromLandmarkId: step.fromLandmarkId,
            toLandmarkId: step.toLandmarkId,
            distanceM: step.distanceM,
            instruction: step.instruction,
            turnDeg: step.turnDeg,
          ),
      ],
    );
  }

  bool get isEmpty => legs.isEmpty;

  double get totalDistanceM => legs.fold(0, (sum, leg) => sum + leg.distanceM);

  /// Landmarks in walking order, start included.
  List<String> get landmarkIds => [
    if (legs.isNotEmpty) legs.first.fromLandmarkId,
    for (final leg in legs) leg.toLandmarkId,
  ];

  @override
  List<Object?> get props => [legs, synthesised];
}

/// A* over the landmark graph.
///
/// Textbook A*, deliberately: these graphs are tens of nodes, and the honest
/// engineering answer to "tens of nodes" is the algorithm everybody can read.
class RoutePlanner {
  const RoutePlanner();

  /// The shortest walk from [from] to [to], or null when the graph does not
  /// connect them — a landmark nobody has recorded a way to is unreachable,
  /// which the UI reports as "no recorded route" rather than as an error.
  ///
  /// [landmarks] and [recorded] are optional and only sharpen the result.
  /// Without them the turns are still recomputed from the merged geometry (that
  /// needs nothing but the graph) and wording still comes from the edge, which
  /// is main-line behaviour. With [recorded], a recorded sentence is reused
  /// only when the user will *arrive the way its author did* — see
  /// [_instructionFor].
  PlannedRoute? plan(
    FloorGraph graph, {
    required String from,
    required String to,
    Map<String, Landmark> landmarks = const {},
    List<WalkRoute> recorded = const [],
  }) {
    if (graph.nodeOf(from) == null || graph.nodeOf(to) == null) return null;
    if (from == to) return const PlannedRoute(legs: []);

    final cameFrom = <String, Neighbour>{};
    final costSoFar = <String, double>{from: 0};
    final open = <String>[from];

    while (open.isNotEmpty) {
      // A list scan rather than a heap: a floor holds tens of landmarks, and
      // the constant factor of a priority queue is not worth the code.
      var currentIndex = 0;
      var bestEstimate = double.infinity;
      for (var i = 0; i < open.length; i++) {
        final estimate = costSoFar[open[i]]! + _heuristic(graph, open[i], to);
        if (estimate < bestEstimate) {
          bestEstimate = estimate;
          currentIndex = i;
        }
      }
      final current = open.removeAt(currentIndex);
      if (current == to) {
        return _reconstruct(graph, cameFrom, from, to, landmarks, recorded);
      }

      for (final neighbour in graph.neighboursOf(current)) {
        final cost = costSoFar[current]! + neighbour.distanceM;
        final known = costSoFar[neighbour.landmarkId];
        if (known != null && known <= cost) continue;
        costSoFar[neighbour.landmarkId] = cost;
        cameFrom[neighbour.landmarkId] = Neighbour(
          landmarkId: current,
          edge: neighbour.edge,
        );
        if (!open.contains(neighbour.landmarkId)) {
          open.add(neighbour.landmarkId);
        }
      }
    }
    return null;
  }

  /// Straight-line metres between two landmarks as laid out.
  ///
  /// Admissible as long as the schematic does not stretch distances, which the
  /// turtle layout cannot do — it walks the recorded metres. A cross-floor pair
  /// sits at the same point, so climbing is estimated at zero, which is
  /// admissible too. Where accumulated angular error makes it briefly
  /// optimistic the search stays correct; where it made it pessimistic A* could
  /// return a slightly long path, which on a graph this size is a metre or two,
  /// not a wrong corridor.
  double _heuristic(FloorGraph graph, String a, String b) {
    final from = graph.nodeOf(a);
    final to = graph.nodeOf(b);
    if (from == null || to == null) return 0;
    return from.distanceTo(to);
  }

  PlannedRoute _reconstruct(
    FloorGraph graph,
    Map<String, Neighbour> cameFrom,
    String from,
    String to,
    Map<String, Landmark> landmarks,
    List<WalkRoute> recorded,
  ) {
    // Walk the chain back to [from] first, so each leg knows what precedes it.
    final path = <String>[to];
    var cursor = to;
    while (cursor != from) {
      cursor = cameFrom[cursor]!.landmarkId;
      path.add(cursor);
    }
    final ordered = path.reversed.toList();

    final legIndex = _indexLegs(recorded);
    final legs = <PlannedLeg>[];

    for (var i = 0; i + 1 < ordered.length; i++) {
      final previousId = i > 0 ? ordered[i - 1] : null;
      final originId = ordered[i];
      final targetId = ordered[i + 1];
      final edge = cameFrom[targetId]!.edge;

      legs.add(
        PlannedLeg(
          fromLandmarkId: originId,
          toLandmarkId: targetId,
          distanceM: edge.distanceM,
          instruction: _instructionFor(
            edge: edge,
            legIndex: legIndex,
            previousId: previousId,
            originId: originId,
            targetId: targetId,
            hasRecordings: recorded.isNotEmpty,
          ),
          turnDeg: _turnAt(graph, previousId, originId, targetId, landmarks),
        ),
      );
    }

    return PlannedRoute(
      legs: legs,
      synthesised: legs.any((leg) => leg.instruction == null),
    );
  }

  /// The recorded wording for this leg, or null when none of it applies.
  ///
  /// Only the direction somebody actually walked has words at all. Beyond that,
  /// the recorded sentence is only true if the user arrives the way its author
  /// did: "Turn right; the stairwell is at the end of the corridor" becomes a
  /// lie approached from anywhere else — and a lie spoken to somebody who
  /// cannot see the corridor is worse than silence.
  ///
  /// Without any recordings to check the approach against, the edge's wording
  /// is taken at face value; that is the only information available, and it is
  /// right whenever the route follows a single contributor's walk.
  String? _instructionFor({
    required GraphEdge edge,
    required Map<String, _RecordedLeg> legIndex,
    required String? previousId,
    required String originId,
    required String targetId,
    required bool hasRecordings,
  }) {
    final walked = edge.instructionFor(originId);
    if (walked == null) return null;
    if (!hasRecordings) return walked;

    final leg = legIndex['$originId>$targetId'];
    if (leg == null) return walked;
    // The first leg of a recording has no approach of its own, so it is safe
    // wherever the user starts.
    if (leg.previousLandmarkId == null) return walked;
    return leg.previousLandmarkId == previousId ? walked : null;
  }

  /// The turn a walker makes at [originId], arriving from [previousId] and
  /// leaving towards [targetId].
  ///
  /// Recomputed from the merged geometry rather than reused, because a recorded
  /// `turnDeg` is relative to the leg that preceded it *in that recording*.
  /// Splice legs from two different walks together and the stored angle refers
  /// to an approach the user never made.
  int _turnAt(
    FloorGraph graph,
    String? previousId,
    String originId,
    String targetId,
    Map<String, Landmark> landmarks,
  ) {
    if (previousId == null) return 0;

    final previous = graph.nodeOf(previousId);
    final origin = graph.nodeOf(originId);
    final target = graph.nodeOf(targetId);
    if (previous == null || origin == null || target == null) return 0;

    // A floor change puts two nodes at the same point, leaving no direction to
    // measure. Stairs are described, not turned into.
    final incoming = _bearing(previous, origin);
    final outgoing = _bearing(origin, target);
    if (incoming == null || outgoing == null) return 0;

    var delta = outgoing - incoming;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta <= -180) {
      delta += 360;
    }

    // Snapped to the buttons the capture UI offers plus a u-turn. Speaking
    // "turn 73 degrees" to somebody who cannot see the corner is useless; the
    // vocabulary has to match what a person can actually do.
    const options = [-180, -135, -90, -45, 0, 45, 90, 135, 180];
    var best = 0;
    var bestGap = double.infinity;
    for (final option in options) {
      final gap = (delta - option).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = option;
      }
    }
    return best == -180 ? 180 : best;
  }

  double? _bearing(MapNode from, MapNode to) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    if (dx.abs() < 0.01 && dy.abs() < 0.01) return null;
    return math.atan2(dx, dy) * 180 / math.pi;
  }

  /// Indexes every recorded leg by the direction it was walked, remembering
  /// what preceded it so [_instructionFor] can tell whether its wording still
  /// applies. Where several contributors recorded the same leg the most-verified
  /// route wins.
  static Map<String, _RecordedLeg> _indexLegs(List<WalkRoute> routes) {
    final indexed = <String, _RecordedLeg>{};

    for (final route in routes) {
      final legs = [...route.steps]..sort((a, b) => a.seq.compareTo(b.seq));
      for (var i = 0; i < legs.length; i++) {
        final leg = legs[i];
        final key = '${leg.fromLandmarkId}>${leg.toLandmarkId}';
        final existing = indexed[key];
        if (existing != null && existing.verifiedCount >= route.verifiedCount) {
          continue;
        }
        indexed[key] = _RecordedLeg(
          previousLandmarkId: i > 0 ? legs[i - 1].fromLandmarkId : null,
          verifiedCount: route.verifiedCount,
        );
      }
    }

    return indexed;
  }
}

class _RecordedLeg {
  const _RecordedLeg({
    required this.previousLandmarkId,
    required this.verifiedCount,
  });

  /// Where the contributor came from before this leg, or null if they started
  /// here. The recorded instruction is only valid for this approach.
  final String? previousLandmarkId;

  final int verifiedCount;
}
