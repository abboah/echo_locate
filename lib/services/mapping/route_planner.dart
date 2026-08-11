import 'package:equatable/equatable.dart';

import '../../core/models/walk_route.dart';
import 'floor_graph.dart';

/// One leg of a route the user is about to walk.
///
/// [instruction] is null when this leg is being walked in a direction nobody
/// recorded — the corridor is known, the wording for it is not. Guidance says
/// something neutral there ("continue about twenty steps to the stairwell")
/// rather than replaying a turn instruction backwards.
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
  List<Object?> get props =>
      [fromLandmarkId, toLandmarkId, distanceM, instruction, turnDeg];
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

  double get totalDistanceM =>
      legs.fold(0, (sum, leg) => sum + leg.distanceM);

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
/// This is what the crowdsourcing is *for*. Contributors record walks to
/// particular destinations; merging them into one graph and searching it means
/// the app can answer routes nobody recorded — 204 to 209 via the junction they
/// share — so coverage grows faster than the number of walks.
///
/// Textbook A*, deliberately: these graphs are tens of nodes, and the honest
/// engineering answer to "tens of nodes" is the algorithm everybody can read.
class RoutePlanner {
  const RoutePlanner();

  /// The shortest walk from [from] to [to], or null when the graph does not
  /// connect them — a landmark nobody has recorded a way to is unreachable,
  /// which the UI reports as "no recorded route" rather than as an error.
  PlannedRoute? plan(
    FloorGraph graph, {
    required String from,
    required String to,
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
      if (current == to) return _reconstruct(cameFrom, from, to);

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
  /// turtle layout cannot do — it walks the recorded metres. Where accumulated
  /// angular error makes it briefly optimistic the search stays correct; where
  /// it made it pessimistic A* could return a slightly long path, which on a
  /// graph this size is a metre or two, not a wrong corridor.
  double _heuristic(FloorGraph graph, String a, String b) {
    final from = graph.nodeOf(a);
    final to = graph.nodeOf(b);
    if (from == null || to == null) return 0;
    return from.distanceTo(to);
  }

  PlannedRoute _reconstruct(
    Map<String, Neighbour> cameFrom,
    String from,
    String to,
  ) {
    final legs = <PlannedLeg>[];
    var cursor = to;

    while (cursor != from) {
      final previous = cameFrom[cursor]!;
      final origin = previous.landmarkId;
      legs.insert(
        0,
        PlannedLeg(
          fromLandmarkId: origin,
          toLandmarkId: cursor,
          distanceM: previous.edge.distanceM,
          // Only the direction somebody actually walked has words.
          instruction: previous.edge.instructionFor(origin),
          turnDeg: previous.edge.fromId == origin ? previous.edge.turnDeg : 0,
        ),
      );
      cursor = origin;
    }

    return PlannedRoute(
      legs: legs,
      synthesised: legs.any((leg) => leg.instruction == null),
    );
  }
}
