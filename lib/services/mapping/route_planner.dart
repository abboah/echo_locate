// A* over the landmark graph, and the synthesis of a walkable route from the
// path it finds — spec §6 A4.
//
// This is the payoff of merging: somebody walked the entrance to the Reading
// Hall and somebody else walked the entrance to Study Room 2B, and from those
// two recordings the app can guide a user from the Reading Hall to Study Room
// 2B — a journey nobody ever recorded.
//
// Finding the path is the easy half. The hard half is that a path spliced from
// fragments of other people's walks cannot reuse their words: an instruction
// recorded walking north is false walking south, and a turn recorded after one
// approach is wrong after a different one. Both are recomputed here.

import 'dart:math' as math;

import '../../core/models/landmark.dart';
import '../../core/models/walk_route.dart';
import 'floor_graph.dart';
import 'map_node.dart';

/// Marks a route this class invented rather than one a contributor walked.
///
/// Guidance treats the two identically — that is the point — but the evaluation
/// chapter must never count a computed distance as measured evidence, and the
/// UI says "estimated route" rather than implying somebody verified it.
const String plannedRoutePrefix = 'planned:';

extension PlannedWalkRoute on WalkRoute {
  bool get isPlanned => id.startsWith(plannedRoutePrefix);
}

/// Plans journeys across everything recorded in one building.
///
/// Built once per building and held by the Bloc: merging is not free and the
/// graph does not change while the screen is open.
class RoutePlanner {
  RoutePlanner({
    required this.graph,
    required List<WalkRoute> recorded,
    required List<Landmark> landmarks,
  })  : _landmarks = {for (final l in landmarks) l.id: l},
        _recorded = recorded,
        _legs = _indexLegs(recorded) {
    _buildingId = landmarks.isNotEmpty
        ? landmarks.first.buildingId
        : (recorded.isNotEmpty ? recorded.first.buildingId : '');
  }

  /// Merges [routes] and plans over the result.
  factory RoutePlanner.from(List<WalkRoute> routes, List<Landmark> landmarks) =>
      RoutePlanner(
        graph: merge(routes, landmarks),
        recorded: routes,
        landmarks: landmarks,
      );

  final FloorGraph graph;
  final Map<String, Landmark> _landmarks;
  final List<WalkRoute> _recorded;

  /// Ordered landmark pair → the best recording of that leg.
  final Map<String, _RecordedLeg> _legs;

  late final String _buildingId;

  /// The landmark standing at a room's door, or null when nobody has recorded
  /// one. A room with no landmark cannot be navigated to — the caller says so
  /// rather than pretending otherwise.
  String? landmarkForRoom(String roomId) {
    String? fallback;
    for (final landmark in _landmarks.values) {
      if (landmark.roomId != roomId) continue;
      // Prefer a landmark the graph actually reaches; an unreachable one is
      // only useful as a "recorded but not connected" diagnosis.
      if (graph.nodes.containsKey(landmark.id)) return landmark.id;
      fallback ??= landmark.id;
    }
    return fallback;
  }

  /// Landmark ids from [fromLandmarkId] to [toLandmarkId] inclusive, or an
  /// empty list when the two are not connected.
  ///
  /// Textbook A*. These graphs are tens of nodes, so the heuristic — straight
  /// line between laid-out positions — is about legibility, not speed. It is
  /// admissible: laid-out distance never exceeds walked distance, and a
  /// cross-floor pair sits at the same point, so climbing is estimated at zero.
  List<String> findPath(String fromLandmarkId, String toLandmarkId) {
    if (!graph.nodes.containsKey(fromLandmarkId) ||
        !graph.nodes.containsKey(toLandmarkId)) {
      return const [];
    }
    if (fromLandmarkId == toLandmarkId) return [fromLandmarkId];

    final goal = graph.nodes[toLandmarkId]!;
    double heuristic(String id) => graph.nodes[id]!.distanceTo(goal);

    final cameFrom = <String, String>{};
    final costSoFar = <String, double>{fromLandmarkId: 0};
    final open = HeapPriorityQueue<_Candidate>();
    open.add(_Candidate(fromLandmarkId, heuristic(fromLandmarkId)));

    final settled = <String>{};

    while (open.isNotEmpty) {
      final current = open.removeFirst();
      if (current.id == toLandmarkId) break;
      if (!settled.add(current.id)) continue;

      for (final edge in graph.edgesFrom(current.id)) {
        final next = edge.otherEnd(current.id);
        if (next == null || !graph.nodes.containsKey(next)) continue;

        final cost = costSoFar[current.id]! + edge.distanceM;
        if (costSoFar.containsKey(next) && cost >= costSoFar[next]!) continue;

        costSoFar[next] = cost;
        cameFrom[next] = current.id;
        open.add(_Candidate(next, cost + heuristic(next)));
      }
    }

    if (!cameFrom.containsKey(toLandmarkId)) return const [];

    final path = <String>[toLandmarkId];
    var cursor = toLandmarkId;
    while (cursor != fromLandmarkId) {
      cursor = cameFrom[cursor]!;
      path.add(cursor);
    }
    return path.reversed.toList();
  }

  /// A navigable route between two landmarks, or null when no path exists.
  WalkRoute? planBetweenLandmarks({
    required String fromLandmarkId,
    required String toLandmarkId,
  }) {
    final path = findPath(fromLandmarkId, toLandmarkId);
    if (path.length < 2) return null;

    // If somebody already walked exactly this, hand back their recording
    // rather than a reconstruction of it. Same corridors either way, but the
    // recording carries its verification count and the contributor's own step
    // counts — and calling a walk somebody actually made an "estimated route"
    // undersells the only real evidence the app has.
    final walked = _recordedAlong(path);
    if (walked != null) return walked;

    final steps = <RouteStep>[];
    for (var i = 0; i + 1 < path.length; i++) {
      steps.add(
        _legBetween(
          previousId: i > 0 ? path[i - 1] : null,
          fromId: path[i],
          toId: path[i + 1],
          seq: i + 1,
        ),
      );
    }

    return WalkRoute(
      id: '$plannedRoutePrefix$fromLandmarkId>$toLandmarkId',
      buildingId: _buildingId,
      startLandmarkId: fromLandmarkId,
      destinationRoomId: _landmarks[toLandmarkId]?.roomId ?? '',
      totalDistanceM: steps.fold<double>(0, (sum, s) => sum + s.distanceM),
      steps: steps,
    );
  }

  /// A navigable route from a landmark to a room's door.
  WalkRoute? planToRoom({
    required String fromLandmarkId,
    required String roomId,
  }) {
    final destination = landmarkForRoom(roomId);
    if (destination == null) return null;
    return planBetweenLandmarks(
      fromLandmarkId: fromLandmarkId,
      toLandmarkId: destination,
    );
  }

  /// The demo case: door to door between two rooms, over legs recorded on
  /// unrelated journeys.
  WalkRoute? planBetweenRooms({
    required String fromRoomId,
    required String toRoomId,
  }) {
    final start = landmarkForRoom(fromRoomId);
    final destination = landmarkForRoom(toRoomId);
    if (start == null || destination == null) return null;
    return planBetweenLandmarks(
      fromLandmarkId: start,
      toLandmarkId: destination,
    );
  }

  /// The most-verified recording that runs along exactly [path], or null when
  /// no single walk covers it.
  WalkRoute? _recordedAlong(List<String> path) {
    WalkRoute? best;
    for (final route in _recorded) {
      final walked = route.landmarkIds;
      if (walked.length != path.length) continue;
      var matches = true;
      for (var i = 0; i < path.length; i++) {
        if (walked[i] != path[i]) {
          matches = false;
          break;
        }
      }
      if (!matches) continue;
      if (best == null || route.verifiedCount > best.verifiedCount) {
        best = route;
      }
    }
    if (best == null) return null;

    // `total_distance_m` is a denormalised column: nothing stops a client
    // writing a route whose stored total disagrees with the legs it also
    // wrote. The legs are the evidence, so they win — otherwise guidance
    // announces a distance remaining that its own steps never add up to.
    final summed = best.steps.fold<double>(0, (sum, s) => sum + s.distanceM);
    return (best.totalDistanceM - summed).abs() < 0.01
        ? best
        : best.copyWith(totalDistanceM: summed);
  }

  // --- leg synthesis -------------------------------------------------------

  RouteStep _legBetween({
    required String? previousId,
    required String fromId,
    required String toId,
    required int seq,
  }) {
    final recorded = _legs['$fromId>$toId'];
    final distanceM = _distanceBetween(fromId, toId, recorded);

    // The recorded sentence is only true if the user arrives the way its
    // author did. "Turn right; the stairwell is at the end of the corridor"
    // becomes a lie approached from anywhere else — and a lie spoken to
    // somebody who cannot see the corridor is worse than silence.
    final approachMatches =
        recorded != null && recorded.previousLandmarkId == previousId;

    if (approachMatches) {
      return RouteStep(
        seq: seq,
        fromLandmarkId: fromId,
        toLandmarkId: toId,
        instruction: recorded.step.instruction,
        distanceM: distanceM,
        turnDeg: recorded.step.turnDeg,
        // Never carried over: the contributor's count belongs to the walk they
        // actually took, and this is not it.
      );
    }

    final turnDeg = _turnAt(previousId, fromId, toId);
    return RouteStep(
      seq: seq,
      fromLandmarkId: fromId,
      toLandmarkId: toId,
      instruction: _describe(
        turnDeg: turnDeg,
        fromId: fromId,
        toId: toId,
        distanceM: distanceM,
      ),
      distanceM: distanceM,
      turnDeg: turnDeg,
    );
  }

  /// Metres walked, preferring what somebody measured over what the schematic
  /// implies. Laid-out geometry is derived from these distances, so falling
  /// back to it is a last resort for an edge the graph has but no route does.
  double _distanceBetween(String fromId, String toId, _RecordedLeg? recorded) {
    for (final edge in graph.edgesFrom(fromId)) {
      if (edge.otherEnd(fromId) == toId) return edge.distanceM;
    }
    if (recorded != null) return recorded.step.distanceM;
    final from = graph.nodes[fromId];
    final to = graph.nodes[toId];
    return from != null && to != null ? from.distanceTo(to) : 0;
  }

  /// The turn a walker makes at [fromId], arriving from [previousId] and
  /// leaving towards [toId].
  ///
  /// Recomputed from the merged geometry rather than reused, because a
  /// recorded `turnDeg` is relative to the leg that preceded it *in that
  /// recording*. Splice legs from two different walks together and the stored
  /// angle refers to an approach the user never made.
  int _turnAt(String? previousId, String fromId, String toId) {
    if (previousId == null) return 0;

    final previous = graph.nodes[previousId];
    final from = graph.nodes[fromId];
    final to = graph.nodes[toId];
    if (previous == null || from == null || to == null) return 0;

    // A floor change puts two nodes at the same point, leaving no direction to
    // measure. Stairs are described, not turned into.
    final incoming = _bearing(previous, from);
    final outgoing = _bearing(from, to);
    if (incoming == null || outgoing == null) return 0;

    var delta = outgoing - incoming;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta <= -180) {
      delta += 360;
    }

    // Snapped to the six buttons the capture UI offers plus a u-turn. Speaking
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

  String _describe({
    required int turnDeg,
    required String fromId,
    required String toId,
    required double distanceM,
  }) {
    final destination = _landmarks[toId]?.displayName ?? 'the next landmark';
    final fromFloor = _landmarks[fromId]?.floorId;
    final toFloor = _landmarks[toId]?.floorId;

    if (fromFloor != null && toFloor != null && fromFloor != toFloor) {
      final byLift = _landmarks[fromId]?.kind == LandmarkKind.lift ||
          _landmarks[toId]?.kind == LandmarkKind.lift;
      return byLift
          ? 'Take the lift to $destination'
          : 'Take the stairs to $destination';
    }

    final metres = distanceM.round();
    return switch (turnDeg) {
      0 => 'Continue straight for about $metres metres to $destination',
      45 => 'Bear right, then about $metres metres to $destination',
      -45 => 'Bear left, then about $metres metres to $destination',
      90 => 'Turn right, then about $metres metres to $destination',
      -90 => 'Turn left, then about $metres metres to $destination',
      135 => 'Turn sharp right, then about $metres metres to $destination',
      -135 => 'Turn sharp left, then about $metres metres to $destination',
      180 => 'Turn around, then about $metres metres to $destination',
      _ => 'Continue about $metres metres to $destination',
    };
  }

  /// Indexes every recorded leg by the direction it was walked, remembering
  /// what preceded it so [_legBetween] can tell whether its wording still
  /// applies. Where several contributors recorded the same leg the
  /// most-verified route wins.
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
          step: leg,
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
    required this.step,
    required this.previousLandmarkId,
    required this.verifiedCount,
  });

  final RouteStep step;

  /// Where the contributor came from before this leg, or null if they started
  /// here. The recorded instruction and turn are only valid for this approach.
  final String? previousLandmarkId;

  final int verifiedCount;
}

class _Candidate implements Comparable<_Candidate> {
  const _Candidate(this.id, this.priority);

  final String id;
  final double priority;

  @override
  int compareTo(_Candidate other) => priority.compareTo(other.priority);
}

/// Minimal binary heap.
///
/// `package:collection` would supply this, but it is not a dependency and spec
/// §8 lists `pubspec.yaml` as shared with Stream B — thirty lines here is
/// cheaper than a merge conflict over a package neither stream needs elsewhere.
class HeapPriorityQueue<T extends Comparable<T>> {
  final List<T> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(T item) {
    _items.add(item);
    var child = _items.length - 1;
    while (child > 0) {
      final parent = (child - 1) ~/ 2;
      if (_items[child].compareTo(_items[parent]) >= 0) break;
      _swap(child, parent);
      child = parent;
    }
  }

  T removeFirst() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var parent = 0;
      while (true) {
        final left = parent * 2 + 1;
        final right = left + 1;
        var smallest = parent;
        if (left < _items.length &&
            _items[left].compareTo(_items[smallest]) < 0) {
          smallest = left;
        }
        if (right < _items.length &&
            _items[right].compareTo(_items[smallest]) < 0) {
          smallest = right;
        }
        if (smallest == parent) break;
        _swap(parent, smallest);
        parent = smallest;
      }
    }
    return first;
  }

  void _swap(int a, int b) {
    final tmp = _items[a];
    _items[a] = _items[b];
    _items[b] = tmp;
  }
}
