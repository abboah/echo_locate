// Routing over rooms and the doors between them — floorplan spec §6.1.
//
// ## Why the nodes are doors, not rooms
//
// The obvious graph puts one node at each room's centroid and one edge per
// door. The floorplan spec does exactly that, and it does not survive contact
// with the thing built on top of it.
//
// A walker does not travel between centroids. They travel **door to door**,
// along the middle of a corridor. Put the nodes at centroids and two things
// break at once:
//
//   * **Distances are wrong.** "Walk to the corridor" becomes "walk to the
//     middle of the corridor", so a route down a 40 m hallway quotes half of
//     it. Guidance speaks these numbers to somebody who cannot see the corridor
//     to correct them.
//   * **Door counting is meaningless.** "The second door on your left" is
//     computed by projecting doors onto the leg being walked. With centroid
//     nodes that leg runs from the middle of the corridor *across* to the
//     middle of the destination room — a line nobody walks, roughly
//     perpendicular to the corridor, and the set of doors that projects onto it
//     is close to arbitrary.
//
// So the graph here has a node per **opening** (at the door's midpoint) and a
// node per **room** (so a route can start and end somewhere). Traversing a room
// is an edge from one of its openings to another. A leg down a corridor is then
// literally the line the walker walks, which is what makes `room_directions.dart`
// able to say which doors they pass and on which side.
//
// This is a navigation mesh at its simplest — the standard answer, not a novel
// one. It costs one extra node per door and buys correctness in the only
// instruction in the app that can confidently send somebody the wrong way.

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../core/models/room_plan.dart';
import 'room_geometry.dart';

/// What a waypoint on a route physically is.
enum WaypointKind {
  /// Where the walker starts — the middle of the origin room.
  start,

  /// A door or archway being passed through.
  opening,

  /// The middle of the destination room.
  destination,
}

/// One point on a walked route.
class RouteWaypoint {
  const RouteWaypoint({
    required this.nodeId,
    required this.at,
    required this.kind,
    this.roomId,
    this.openingId,
  });

  final String nodeId;
  final Offset at;
  final WaypointKind kind;

  /// The room this waypoint sits in, for a [WaypointKind.start] or
  /// [WaypointKind.destination].
  final String? roomId;

  /// The opening being passed through, for a [WaypointKind.opening].
  final String? openingId;

  @override
  String toString() => 'RouteWaypoint($nodeId, $kind)';
}

/// A path through a floor, as the polyline a walker actually follows.
class RoomRoute {
  const RoomRoute({
    required this.waypoints,
    required this.roomsPassed,
    this.polyline = const [],
  });

  final List<RouteWaypoint> waypoints;

  /// Rooms entered, in order, start and destination included. What the renderer
  /// highlights.
  final List<String> roomsPassed;

  /// The route as a line to draw, bent around the corridors it follows.
  ///
  /// Separate from [waypoints] on purpose, and the distinction is worth
  /// keeping straight:
  ///
  ///   * **waypoints are decision points** — a door, the middle of a room.
  ///     Directions walk them pairwise and produce one instruction per pair, so
  ///     adding a vertex here would add a sentence ("continue, continue, bear
  ///     slightly left") for a bend nobody needs told about.
  ///   * **the polyline is the drawn path.** It expands each corridor leg along
  ///     that corridor's centreline, so a route round an L follows the hallway
  ///     instead of cutting the corner through two walls.
  ///
  /// Falls back to the waypoint positions for a plan whose corridors were traced
  /// as bare polygons, which is exactly what was drawn before this existed.
  final List<Offset> polyline;

  bool get isEmpty => waypoints.length < 2;

  /// The straight-line total. See [walkedDistanceM] for the distance actually
  /// covered, which is longer wherever the route bends round a corridor.
  double get totalDistanceM {
    var total = 0.0;
    for (var i = 0; i + 1 < waypoints.length; i++) {
      total += (waypoints[i + 1].at - waypoints[i].at).distance;
    }
    return total;
  }

  /// Length of the path as drawn — the distance a walker really covers.
  double get walkedDistanceM =>
      polyline.length < 2 ? totalDistanceM : polylineLength(polyline);

  /// The line to draw: [polyline] when there is one, the waypoints otherwise.
  ///
  /// Saves every renderer from having to know which, and keeps a route built
  /// before paths existed drawing exactly as it always did.
  List<Offset> get drawnLine =>
      polyline.length >= 2 ? polyline : [for (final w in waypoints) w.at];
}

class _Edge {
  const _Edge(this.to, this.cost, this.throughRoomId);

  final String to;
  final double cost;

  /// The room this edge crosses, or null when it is the step through a doorway
  /// itself. Directions need it to know which corridor's doors to count.
  final String? throughRoomId;
}

/// A floor's rooms and doors, as a graph A* can search.
class RoomNavGraph {
  RoomNavGraph._(this._plan, this._positions, this._adjacency, this._nodeRooms);

  final RoomPlan _plan;
  final Map<String, Offset> _positions;
  final Map<String, List<_Edge>> _adjacency;

  /// Node id → the room it belongs to, for room nodes only.
  final Map<String, String> _nodeRooms;

  static String roomNode(String roomId) => 'room:$roomId';
  static String openingNode(String openingId) => 'door:$openingId';

  RoomPlan get plan => _plan;

  Offset? positionOf(String nodeId) => _positions[nodeId];

  /// Builds the graph for one floor.
  ///
  /// Stub rooms — doors counted but never traced, spec §6.3 — get no room node
  /// and no through-room edges, because they have no geometry to cross. Their
  /// *opening* still becomes a node, which is the whole point of recording
  /// them: it keeps them in the count when directions say "the second door on
  /// your left". Asking a stub for its centroid is what makes the spec's own
  /// version throw.
  factory RoomNavGraph.build(RoomPlan plan) {
    final positions = <String, Offset>{};
    final adjacency = <String, List<_Edge>>{};
    final nodeRooms = <String, String>{};

    void connect(String a, String b, double cost, String? throughRoomId) {
      (adjacency[a] ??= []).add(_Edge(b, cost, throughRoomId));
      (adjacency[b] ??= []).add(_Edge(a, cost, throughRoomId));
    }

    for (final opening in plan.openings) {
      positions[openingNode(opening.id)] = opening.position;
    }

    for (final room in plan.rooms) {
      if (room.isStub) continue;

      final node = roomNode(room.id);
      positions[node] = room.centre;
      nodeRooms[node] = room.id;

      final openings = plan.openingsOn(room.id).toList();

      // How far apart two points in this room are *to walk*.
      //
      // Straight-line for an ordinary room, where crossing it is a straight
      // walk. Along the centreline for a corridor drawn as a path, where it is
      // not: two doors at opposite ends of an L are close together in a
      // straight line and a long way apart on foot, and A* handed the straight
      // line will happily route through the corner.
      final spine = room.hasSpine ? room.spine : null;
      double cost(Offset a, Offset b) {
        if (spine == null) return (b - a).distance;
        final from = projectOntoPolyline(spine, a);
        final to = projectOntoPolyline(spine, b);
        return (to.along - from.along).abs() + from.distance + to.distance;
      }

      // The room's own middle joins to each of its doors, so a route can begin
      // or end inside it.
      for (final opening in openings) {
        connect(
          node,
          openingNode(opening.id),
          cost(room.centre, opening.position),
          room.id,
        );
      }

      // Crossing the room: any door to any other door. For a corridor this is
      // the set of legs a walker can take along it, and each one is a real line
      // down the corridor rather than a detour via its centre.
      for (var i = 0; i < openings.length; i++) {
        for (var j = i + 1; j < openings.length; j++) {
          connect(
            openingNode(openings[i].id),
            openingNode(openings[j].id),
            cost(openings[i].position, openings[j].position),
            room.id,
          );
        }
      }
    }

    return RoomNavGraph._(plan, positions, adjacency, nodeRooms);
  }

  /// The shortest walk from one room to another, or null when the plan does
  /// not connect them.
  ///
  /// Null is a normal answer, not an error: a room whose door nobody tagged is
  /// genuinely unreachable on this map, and the UI says "no route on this
  /// floor" rather than failing.
  RoomRoute? route({required String fromRoomId, required String toRoomId}) {
    final start = roomNode(fromRoomId);
    final goal = roomNode(toRoomId);
    if (!_positions.containsKey(start) || !_positions.containsKey(goal)) {
      return null;
    }
    if (fromRoomId == toRoomId) {
      return RoomRoute(
        waypoints: [
          RouteWaypoint(
            nodeId: start,
            at: _positions[start]!,
            kind: WaypointKind.start,
            roomId: fromRoomId,
          ),
        ],
        roomsPassed: [fromRoomId],
      );
    }

    final path = _search(start, goal);
    if (path == null) return null;

    final waypoints = _waypointsFor(path, fromRoomId, toRoomId);
    return RoomRoute(
      waypoints: waypoints,
      roomsPassed: _roomsAlong(path),
      polyline: _drawnPath(waypoints),
    );
  }

  /// The waypoints expanded into the line a walker follows.
  ///
  /// Each leg that crosses a corridor drawn as a path is replaced by the stretch
  /// of that corridor's centreline between its two ends, so the drawn route
  /// bends round the hallway instead of cutting through the wall at the corner.
  /// Every other leg stays the straight line it already was.
  List<Offset> _drawnPath(List<RouteWaypoint> waypoints) {
    if (waypoints.length < 2) return [for (final w in waypoints) w.at];

    final out = <Offset>[waypoints.first.at];

    for (var i = 0; i + 1 < waypoints.length; i++) {
      final from = waypoints[i];
      final to = waypoints[i + 1];
      final roomId = roomBetween(from.nodeId, to.nodeId);
      final room = roomId == null ? null : _plan.roomOf(roomId);

      if (room != null && room.hasSpine) {
        final spine = room.spine;
        final a = projectOntoPolyline(spine, from.at);
        final b = projectOntoPolyline(spine, to.at);
        for (final point in polylineSlice(spine, a.along, b.along)) {
          if ((point - out.last).distance > 1e-9) out.add(point);
        }
      }

      if ((to.at - out.last).distance > 1e-9) out.add(to.at);
    }

    return out;
  }

  /// Textbook A* with a Euclidean heuristic.
  ///
  /// Admissible because every edge cost *is* the straight-line distance between
  /// its ends, so the heuristic can never overestimate. A floor is tens of
  /// nodes, so the open set is a sorted insert rather than a heap — the same
  /// call `route_planner.dart` makes, and for the same reason.
  List<String>? _search(String start, String goal) {
    final goalAt = _positions[goal]!;
    final cameFrom = <String, String>{};
    final costSoFar = <String, double>{start: 0};
    // Records are not Comparable, so the ordering is given explicitly. The node
    // id is the tie-break, which keeps the search deterministic — two equal-cost
    // routes must not depend on map iteration order, or the same query answers
    // differently between runs and a field test cannot be reproduced.
    final open = SplayTreeMap<(double, String), String>((a, b) {
      final byCost = a.$1.compareTo(b.$1);
      return byCost != 0 ? byCost : a.$2.compareTo(b.$2);
    });

    double heuristic(String node) => (_positions[node]! - goalAt).distance;

    open[(heuristic(start), start)] = start;

    while (open.isNotEmpty) {
      final firstKey = open.firstKey()!;
      final current = open.remove(firstKey)!;
      if (current == goal) return _rebuild(cameFrom, start, goal);

      for (final edge in _adjacency[current] ?? const <_Edge>[]) {
        final cost = costSoFar[current]! + edge.cost;
        final known = costSoFar[edge.to];
        if (known != null && known <= cost) continue;
        costSoFar[edge.to] = cost;
        cameFrom[edge.to] = current;
        open[(cost + heuristic(edge.to), edge.to)] = edge.to;
      }
    }
    return null;
  }

  List<String> _rebuild(
    Map<String, String> cameFrom,
    String start,
    String goal,
  ) {
    final path = <String>[goal];
    var cursor = goal;
    while (cursor != start) {
      cursor = cameFrom[cursor]!;
      path.add(cursor);
    }
    return path.reversed.toList();
  }

  List<RouteWaypoint> _waypointsFor(
    List<String> path,
    String fromRoomId,
    String toRoomId,
  ) => [
    for (var i = 0; i < path.length; i++)
      RouteWaypoint(
        nodeId: path[i],
        at: _positions[path[i]]!,
        kind: switch (i) {
          0 => WaypointKind.start,
          _ when i == path.length - 1 => WaypointKind.destination,
          _ => WaypointKind.opening,
        },
        roomId: _nodeRooms[path[i]],
        openingId: path[i].startsWith('door:') ? path[i].substring(5) : null,
      ),
  ];

  /// Rooms the path passes through, in order and without repeats.
  ///
  /// Read off the edges rather than the nodes: a door node belongs to two rooms
  /// at once, so only the edge knows which one is being crossed.
  List<String> _roomsAlong(List<String> path) {
    final rooms = <String>[];
    for (var i = 0; i + 1 < path.length; i++) {
      final edge = (_adjacency[path[i]] ?? const <_Edge>[])
          .where((e) => e.to == path[i + 1])
          .fold<_Edge?>(
            null,
            (best, e) => best == null || e.cost < best.cost ? e : best,
          );
      final room = edge?.throughRoomId;
      if (room != null && (rooms.isEmpty || rooms.last != room)) {
        rooms.add(room);
      }
    }
    return rooms;
  }

  /// The room an edge of the route crosses, for directions.
  String? roomBetween(String nodeA, String nodeB) {
    for (final edge in _adjacency[nodeA] ?? const <_Edge>[]) {
      if (edge.to == nodeB) return edge.throughRoomId;
    }
    return null;
  }

  /// Every room reachable on foot from [roomId], itself included.
  ///
  /// What the editor uses to spot a wing nobody joined up: a room missing from
  /// this set is drawn on the plan and cannot be walked to.
  Set<String> reachableRooms(String roomId) {
    final start = roomNode(roomId);
    if (!_positions.containsKey(start)) return const {};

    final seen = <String>{start};
    final queue = Queue<String>()..add(start);
    while (queue.isNotEmpty) {
      for (final edge in _adjacency[queue.removeFirst()] ?? const <_Edge>[]) {
        if (seen.add(edge.to)) queue.add(edge.to);
      }
    }

    return {
      for (final node in seen)
        if (_nodeRooms[node] case final room?) room,
    };
  }

  /// Rooms on the plan that nothing can reach from [roomId] — the missing-door
  /// report the editor prompts on.
  Set<String> unreachableFrom(String roomId) {
    final reachable = reachableRooms(roomId);
    return {
      for (final room in _plan.drawableRooms)
        if (!reachable.contains(room.id)) room.id,
    };
  }

  /// Whether a room's shape and connectivity make it circulation space.
  ///
  /// Elongation alone is not enough — a long thin store cupboard is not a
  /// corridor — so it takes three or more doors as well, per spec §4. Uses the
  /// axis-aligned bounding box, which is why `cleanupPolygon` must have run
  /// first: a corridor lying diagonal to its own grid has a nearly square box
  /// and would be missed.
  static bool looksLikeCorridor(Room room, RoomPlan plan) {
    if (room.isStub) return false;
    return room.elongation > 3 && plan.openingsOn(room.id).length >= 3;
  }

  /// Pairs of rooms sharing a long stretch of near-parallel wall with no
  /// opening recorded between them — floorplan spec §8's "is there a door
  /// here?" prompt.
  ///
  /// Cheap geometric cover for the failure §6.3 warns about: a door that was
  /// never tagged is invisible to every other check, but the wall it sits in is
  /// still drawn on both sides.
  List<({String roomA, String roomB, Offset near})> missingConnections({
    double minSharedWallM = 1.0,
    double toleranceM = 0.4,
  }) {
    final rooms = _plan.drawableRooms.toList();
    final found = <({String roomA, String roomB, Offset near})>[];

    for (var i = 0; i < rooms.length; i++) {
      for (var j = i + 1; j < rooms.length; j++) {
        final a = rooms[i];
        final b = rooms[j];
        if (_plan.openings.any((o) => o.touches(a.id) && o.touches(b.id))) {
          continue;
        }
        final shared = _sharedWall(a, b, toleranceM);
        if (shared != null && shared.length >= minSharedWallM) {
          found.add((roomA: a.id, roomB: b.id, near: shared.midpoint));
        }
      }
    }
    return found;
  }

  /// How much wall two rooms have in common, and where.
  ({double length, Offset midpoint})? _sharedWall(
    Room a,
    Room b,
    double toleranceM,
  ) {
    ({double length, Offset midpoint})? best;

    for (final edgeA in _edgesOf(a.corners)) {
      for (final edgeB in _edgesOf(b.corners)) {
        // Sampled rather than solved analytically: walls are metres long and a
        // 20 cm sample is finer than the tracing error, so an exact overlap
        // computation would be false precision on top of tapped corners.
        final length = (edgeA.$2 - edgeA.$1).distance;
        if (length < 1e-6) continue;
        final samples = math.max(2, (length / 0.2).ceil());

        var runStart = -1.0;
        var runEnd = -1.0;
        for (var s = 0; s <= samples; s++) {
          final t = s / samples;
          final point = edgeA.$1 + (edgeA.$2 - edgeA.$1) * t;
          final near =
              _distanceToSegment(point, edgeB.$1, edgeB.$2) <= toleranceM;
          if (near) {
            if (runStart < 0) runStart = t;
            runEnd = t;
          }
        }

        if (runStart < 0) continue;
        final overlap = (runEnd - runStart) * length;
        if (best == null || overlap > best.length) {
          best = (
            length: overlap,
            midpoint:
                edgeA.$1 + (edgeA.$2 - edgeA.$1) * ((runStart + runEnd) / 2),
          );
        }
      }
    }
    return best;
  }

  static Iterable<(Offset, Offset)> _edgesOf(List<Offset> polygon) sync* {
    for (var i = 0; i < polygon.length; i++) {
      yield (polygon[i], polygon[(i + 1) % polygon.length]);
    }
  }

  /// Which rooms a point sits on the boundary of, nearest first.
  ///
  /// Measures to the **boundary**, not the centre: a door is in a wall, and the
  /// nearest room by centroid to a door halfway down a long corridor is
  /// routinely the wrong one.
  ///
  /// [radius] is in the plan's own units, which differ between the two capture
  /// paths and is the whole reason it is a parameter — a traced plan is in
  /// fractions of an image width, a captured one is in metres. A single
  /// hard-coded value would be wrong in one of them by a factor of thirty.
  static List<Room> roomsBorderingPoint(
    RoomPlan plan,
    Offset at, {
    required double radius,
  }) {
    final near = <({Room room, double distance})>[];
    for (final room in plan.drawableRooms) {
      final distance = distanceToBoundary(room.corners, at);
      if (distance <= radius) near.add((room: room, distance: distance));
    }
    near.sort((a, b) => a.distance.compareTo(b.distance));
    return [for (final entry in near) entry.room];
  }

  /// The two rooms a door at [at] joins, worked out from the geometry.
  ///
  /// The alternative — pick room A from a list, then room B — is three
  /// interactions for something the map already knows. Both capture flows share
  /// this so the rule cannot drift between them: one returns points from a
  /// finger on a photograph, the other from an ARCore hit-test, and by the time
  /// they get here they are just points on a plan.
  ///
  /// `roomA` null means the tap touched no wall at all. `roomB` null with
  /// `roomA` set means only one room borders that point, which is an exterior
  /// door — a real thing to record, and the way out of a building.
  static ({Room? roomA, Room? roomB}) inferDoorAt(
    RoomPlan plan,
    Offset at, {
    required double radius,
  }) {
    final near = roomsBorderingPoint(plan, at, radius: radius);
    return (
      roomA: near.isEmpty ? null : near.first,
      roomB: near.length > 1 ? near[1] : null,
    );
  }

  /// Shortest distance from [point] to any wall of the polygon.
  static double distanceToBoundary(List<Offset> polygon, Offset point) {
    if (polygon.length < 2) return double.infinity;
    var best = double.infinity;
    for (var i = 0; i < polygon.length; i++) {
      final result = projectOntoSegment(
        polygon[i],
        polygon[(i + 1) % polygon.length],
        point,
      );
      if (result.distance < best) best = result.distance;
    }
    return best;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSq = ab.distanceSquared;
    if (lengthSq < 1e-12) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    return (p - (a + Offset(ab.dx * t, ab.dy * t))).distance;
  }
}
