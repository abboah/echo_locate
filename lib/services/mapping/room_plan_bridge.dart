// Where the room layer meets the guidance the app already runs on.
//
// Two maps of the same floor exist, and both earn their place:
//
//   * the **landmark map** (`floor_graph.dart`, `route_planner.dart`) — points
//     with readable signs, joined by corridors somebody walked. It is what
//     `GuidanceBloc` consumes, it needs no ARCore, and it is what OCR confirms
//     the user against. It cannot say which side of a corridor a door is on.
//   * the **room map** (`room_graph.dart`, `room_directions.dart`) — areas with
//     shape. It knows which wall a door sits in and what else is on that wall,
//     which is the only way to say "the second door on your left".
//
// This file converts the second into the first. That direction, and not the
// other, because guidance is the part that is finished, tested and speaking to
// users: a traced room plan arrives as a `PlannedRoute` and a list of
// `Landmark`s, and **nothing in `GuidanceBloc` changes at all**. The door
// counting rides in as each leg's `instruction` string, which guidance already
// speaks aloud.
//
// The join is [Room.landmarkId] when a room has been matched to a landmark
// somebody recorded, and a derived id otherwise — see [landmarkIdFor].

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../core/models/landmark.dart';
import '../../core/models/room_plan.dart';
import 'floor_graph.dart';
import 'map_node.dart';
import 'room_directions.dart';
import 'room_geometry.dart';
import 'room_graph.dart';
import 'route_planner.dart';

/// A room plan expressed in the terms guidance understands.
class RoomPlanBridge {
  const RoomPlanBridge._();

  /// The landmark id standing for [room].
  ///
  /// A room already matched to a recorded landmark keeps that landmark's id, so
  /// a plan traced over a building somebody has walked joins up with their
  /// recordings rather than shadowing them. Otherwise the id is derived from
  /// the room's, deterministically — the same room yields the same id on every
  /// load, which is what lets a route survive a restart.
  static String landmarkIdFor(Room room) =>
      room.landmarkId ?? 'room-${room.id}';

  /// Landmarks for every traced room, so OCR can confirm arrival.
  ///
  /// This is the half of the integration that matters most for a blind user.
  /// The room layer knows *where* the second door on the left is; it has no way
  /// to know the user has reached it. The landmark layer does — it waits for
  /// the camera to read the plate on the door. Publishing rooms as landmarks is
  /// what lets a traced plan be *followed*, not merely drawn.
  ///
  /// [labelText] is the room's code, because that is what is painted on the
  /// door and printed on the board it was traced from. Where a contributor also
  /// typed the name off the door, it is added as an alias, so either reading
  /// confirms arrival.
  ///
  /// Stubs are excluded: a room nobody traced has no door anybody identified,
  /// and a landmark whose sign is unknown can never match.
  static List<Landmark> landmarksFrom(RoomPlan plan) => [
    for (final room in plan.drawableRooms)
      Landmark(
        id: landmarkIdFor(room),
        buildingId: plan.buildingId,
        floorId: room.floorId,
        kind: _kindOf(room),
        // The sign text to match against, which only a named room has. This
        // normalised `room.code` — an allocated `GF 7` that was never on any
        // door, so a reading could only ever match it by coincidence. Empty
        // for an unnamed room: there is nothing to confirm arrival against,
        // and saying so beats matching a number the building never used.
        labelText: room.isNamed ? Landmark.normalise(room.name!) : '',
        displayName: room.spokenName,
        aliases: [if (room.isNamed) room.name!],
        roomId: room.id,
      ),
  ];

  static LandmarkKind _kindOf(Room room) => switch (room.category) {
    RoomCategory.staircase => LandmarkKind.stairs,
    RoomCategory.elevator => LandmarkKind.lift,
    RoomCategory.corridor => LandmarkKind.junction,
    _ => LandmarkKind.door,
  };

  /// The plan as a landmark graph, for the map view and for recovery replanning.
  ///
  /// Rooms become nodes at their own interior point and openings become edges.
  /// Deliberately coarser than [RoomNavGraph], which puts a node at every door:
  /// that resolution is what door counting needs and it is *not* what guidance
  /// needs, because a user cannot confirm they are at a doorway — there is no
  /// sign on a threshold. Guidance steps from named place to named place.
  ///
  /// Marked non-metric whenever the plan is, so nothing downstream turns
  /// arbitrary plan units into a step count. See [RoomPlan.metresPerUnit].
  ///
  /// Edge lengths are converted through that scale where there is one, so a
  /// `metric` graph's distances really are metres. Routing itself does not
  /// care — A* compares edges against each other and a uniform factor picks
  /// the same path — but everything that *reads* a distance off the result
  /// does, and until this conversion existed a measured plan handed guidance
  /// fractions of a photograph labelled as metres.
  static FloorGraph floorGraphFrom(RoomPlan plan) {
    final rooms = {for (final room in plan.drawableRooms) room.id: room};
    if (rooms.isEmpty) return FloorGraph.empty;

    final scale = plan.metresPerUnit ?? 1;

    // Coordinates converted too, not just the edge lengths, so the graph is
    // internally consistent: a caller that measures between two nodes gets the
    // same number the edge between them carries. [FloorGraph.fromPlan] does
    // the same for a traced landmark plan, and the mismatch is the kind that
    // hides — nothing looks wrong until a distance derived one way is compared
    // against one derived the other.
    final nodes = {
      for (final room in rooms.values)
        landmarkIdFor(room): MapNode(
          landmarkId: landmarkIdFor(room),
          floorId: room.floorId,
          x: room.centre.dx * scale,
          y: room.centre.dy * scale,
        ),
    };

    final edges = <GraphEdge>[];
    final seen = <String>{};
    for (final opening in plan.openings) {
      final a = rooms[opening.roomAId];
      final b = opening.roomBId == null ? null : rooms[opening.roomBId];
      // Exterior doors and doors to untraced rooms have nothing on the far
      // side to route to. The opening still exists and is still counted for
      // ordinals; it is simply not an edge.
      if (a == null || b == null) continue;

      final from = landmarkIdFor(a);
      final to = landmarkIdFor(b);
      final key = from.compareTo(to) <= 0 ? '$from|$to' : '$to|$from';
      if (!seen.add(key)) continue;

      edges.add(
        GraphEdge(
          fromId: from,
          toId: to,
          distanceM: (a.centre - b.centre).distance * scale,
        ),
      );
    }

    return FloorGraph(nodes: nodes, edges: edges, metric: plan.isMetric);
  }

  /// The same walk as a line on the floor, in metres, in the plan's frame.
  ///
  /// See [RoutePath].
  ///
  /// [plannedRouteFrom] collapses the route to one leg per room entered,
  /// because that is what guidance *speaks*. This keeps what that collapse
  /// throws away: every vertex of the path, bent round the corridors it
  /// follows. The AR layer needs it — an arrow that can only be told "twelve
  /// metres, then turn right" has to dead-reckon the twelve metres, and an
  /// arrow handed the actual line can point at the actual corner.
  ///
  /// In metres, using [dynamicScale], [RoomPlan.metresPerUnit], or the estimated
  /// architectural scale, so it is in the same units as ARCore's world and can be
  /// registered into it directly.
  static RoutePath? routePathFrom(
    RoomPlan plan, {
    required String fromRoomId,
    required String toRoomId,
    double? dynamicScale,
  }) {
    final scale = dynamicScale ?? plan.effectiveMetresPerUnit;

    final graph = RoomNavGraph.build(plan);
    final route = graph.route(fromRoomId: fromRoomId, toRoomId: toRoomId);
    if (route == null || route.isEmpty) return null;

    final line = route.drawnLine;
    if (line.length < 2) return null;

    // Where each leg ends, as a distance along the path. The AR layer measures
    // the walk against the whole route, and guidance counts down one leg at a
    // time; without this the two are measuring different things and the spoken
    // countdown would run to the end of the building.
    final cumulative = _cumulativeAlong(plan, graph, route);
    final entryAt = _entryWaypoints(graph, route);
    final legEnds = <double>[];
    for (
      var k = 0;
      k + 1 < route.roomsPassed.length && k + 1 < entryAt.length + 1;
      k++
    ) {
      legEnds.add(cumulative[_endOfLeg(route, entryAt, k)] * scale);
    }

    return RoutePath(
      pointsM: [for (final point in line) point * scale],
      legEndsM: legEnds,
      // Circulation spaces (corridors, stairs, atriums) have no internal room approach —
      // the walk starts directly on the corridor line.
      approachFromM: switch (plan.roomOf(fromRoomId)) {
        final Room r when r.category.isCirculation => null,
        final Room r => switch (r.centre) {
          final Offset centre => centre * scale,
          null => null,
        },
        null => null,
      },
    );
  }

  /// A walk between two rooms, as guidance consumes it.
  ///
  /// Routed on [RoomNavGraph] — through doors, along corridor spines — so the
  /// distances are the ones a walker covers and the door ordinals are computed
  /// against the wall they are actually passing. The result is then collapsed
  /// to one leg per room entered, because that is the granularity guidance
  /// speaks and confirms at.
  ///
  /// Returns null when the plan does not connect the two rooms, which is a
  /// normal answer: a room whose door nobody tagged is genuinely unreachable.
  static PlannedRoute? plannedRouteFrom(
    RoomPlan plan, {
    required String fromRoomId,
    required String toRoomId,
    Offset? initialHeading,
  }) {
    final graph = RoomNavGraph.build(plan);
    final route = graph.route(fromRoomId: fromRoomId, toRoomId: toRoomId);
    if (route == null || route.isEmpty) return null;

    final spoken = RoomDirections.forPlan(
      plan,
    ).describe(graph, route, initialHeading: initialHeading);

    final cumulative = _cumulativeAlong(plan, graph, route);
    final entryAt = _entryWaypoints(graph, route);
    return _legsFrom(
      plan: plan,
      route: route,
      spoken: spoken,
      cumulative: cumulative,
      entryAt: entryAt,
    );
  }

  /// Cumulative walked distance at each waypoint, in plan units.
  ///
  /// A leg's length is the polyline the user follows rather than the straight
  /// line between two room centres. Each step is measured *along the corridor
  /// it crosses* when that corridor was drawn as a path: a leg round the bend
  /// of an L is longer than the straight line between its ends by however
  /// sharp the bend is, and this number is what becomes "about forty steps" in
  /// somebody's ear — so the straight line would quietly stop them short of
  /// the corner every time.
  static List<double> _cumulativeAlong(
    RoomPlan plan,
    RoomNavGraph graph,
    RoomRoute route,
  ) {
    final cumulative = <double>[0];
    for (var i = 0; i + 1 < route.waypoints.length; i++) {
      final from = route.waypoints[i];
      final to = route.waypoints[i + 1];
      final crossingId = graph.roomBetween(from.nodeId, to.nodeId);
      final crossing = crossingId == null ? null : plan.roomOf(crossingId);

      final double step;
      if (crossing != null && crossing.hasSpine) {
        final spine = crossing.spine;
        final a = projectOntoPolyline(spine, from.at);
        final b = projectOntoPolyline(spine, to.at);
        step = (b.along - a.along).abs() + a.distance + b.distance;
      } else {
        step = (to.at - from.at).distance;
      }

      cumulative.add(cumulative.last + step);
    }
    return cumulative;
  }

  /// Waypoint index at which each room on the walk is entered — one per entry
  /// in `roomsPassed`. The first room is entered at the start; every other at
  /// the door leading into it.
  static List<int> _entryWaypoints(RoomNavGraph graph, RoomRoute route) {
    final entryAt = <int>[0];
    var roomCursor = 0;
    for (var i = 0; i + 1 < route.waypoints.length; i++) {
      final crossing = graph.roomBetween(
        route.waypoints[i].nodeId,
        route.waypoints[i + 1].nodeId,
      );
      if (crossing != null &&
          roomCursor + 1 < route.roomsPassed.length &&
          crossing == route.roomsPassed[roomCursor + 1]) {
        roomCursor++;
        entryAt.add(i);
      }
    }
    return entryAt;
  }

  /// Where leg [k] stops, as a waypoint index.
  ///
  /// The final leg runs to the last waypoint — the middle of the destination
  /// room — rather than stopping at its door, so the legs partition the whole
  /// polyline and their distances sum to the route. Stopping at the door
  /// instead dropped the last stretch from the total, took the turn into the
  /// room with it, and lost the sentence that names the destination.
  static int _endOfLeg(RoomRoute route, List<int> entryAt, int k) =>
      k + 2 == route.roomsPassed.length
      ? route.waypoints.length - 1
      : entryAt[k + 1];

  /// Collapses the walk to one leg per room entered — what guidance speaks.
  static PlannedRoute? _legsFrom({
    required RoomPlan plan,
    required RoomRoute route,
    required List<RoomInstruction> spoken,
    required List<double> cumulative,
    required List<int> entryAt,
  }) {
    int endOf(int k) => _endOfLeg(route, entryAt, k);

    final legs = <PlannedLeg>[];
    for (
      var k = 0;
      k + 1 < route.roomsPassed.length && k + 1 < entryAt.length + 1;
      k++
    ) {
      final fromRoom = plan.roomOf(route.roomsPassed[k]);
      final toRoom = plan.roomOf(route.roomsPassed[k + 1]);
      if (fromRoom == null || toRoom == null) continue;

      final start = entryAt[k];
      final end = endOf(k);

      // Every sentence generated for a segment inside this leg, in order.
      final within = [
        for (final instruction in spoken)
          if (instruction.segmentIndex >= start &&
              instruction.segmentIndex < end)
            instruction,
      ];
      final turn = within.where((i) => i.turnDegreesRight != 0).firstOrNull;

      legs.add(
        PlannedLeg(
          fromLandmarkId: landmarkIdFor(fromRoom),
          toLandmarkId: landmarkIdFor(toRoom),
          // In metres where the plan has a scale, and in plan units where it
          // has none — which is what `PlannedRoute` means by non-metric, and
          // what `GuidanceSession.metric` warns its consumers about.
          distanceM: (cumulative[end] - cumulative[start]) *
              (plan.metresPerUnit ?? 1),
          // Null rather than an empty string when nothing was generated:
          // guidance treats null as "say something neutral", and an empty
          // instruction would be spoken as silence where a sentence belongs.
          instruction: within.isEmpty
              ? null
              : within.map((i) => i.text).join(' '),
          turnDeg: turn == null ? 0 : turn.turnDegreesRight.round(),
        ),
      );
    }

    if (legs.isEmpty) return null;

    // Not `synthesised`: every leg came from one traced plan, not stitched
    // together out of several contributors' walks. The flag exists to tell
    // guidance to lean harder on landmark confirmation where wording was
    // spliced, and nothing was spliced here.
    return PlannedRoute(legs: legs);
  }
}

/// A route as a line on the floor, in metres, in the plan's own frame.
///
/// What the AR layer registers into ARCore's world. [PlannedRoute] is the same
/// walk described as a chain of turns and lengths — enough to *speak*, and the
/// only thing a phone without ARCore can use — but a chain of relative turns
/// cannot say where anything is, which is why an arrow driven from one could
/// only ever point along a guess. This carries the geometry that answers that.
class RoutePath {
  const RoutePath({
    required this.pointsM,
    required this.legEndsM,
    this.approachFromM,
  });

  /// Every vertex of the path, bent round the corridors it follows.
  ///
  /// Runs **door to door**: the first point is the origin room's doorway, not
  /// the middle of that room, because a walker needs no directions to a door
  /// they can see. See `RoomNavGraph._doorToDoor`.
  final List<Offset> pointsM;

  /// Where the walker was standing when they said which room they were in.
  ///
  /// **Not part of the route, and deliberately not its first point.** The route
  /// starts at the doorway; this is the place the walker walks *from* to reach
  /// that doorway, and it is the origin room's centre because that is the best
  /// the app can know from "I am in room 12".
  ///
  /// It exists for exactly one job: registration. ARCore's origin is fixed
  /// wherever the phone was when the session opened, which is inside the room —
  /// so pairing that world position with the route's first point declares the
  /// walker to be standing in their own doorway when they are not. In a reading
  /// room twenty metres across that is ten metres of pure translation error
  /// applied to the whole building, and it is the same ten metres however
  /// accurate the scale and the rotation are.
  ///
  /// Null when the origin room has no usable centre, in which case registration
  /// falls back to treating the doorway as the starting point — the old
  /// behaviour, and wrong by however far into the room they were standing.
  final Offset? approachFromM;

  /// How far the walker travels to reach the route's first point.
  ///
  /// Zero when there is no [approachFromM] to measure from.
  double get approachM => approachFromM == null || pointsM.isEmpty
      ? 0
      : (pointsM.first - approachFromM!).distance;

  /// The line the walker actually covers, from where they stood to the end.
  ///
  /// [pointsM] with the approach stretch on the front. Used only to work out
  /// how far along they have got — never sent to ARCore, which is given the
  /// door-to-door route and nothing else.
  List<Offset> get walkedLineM =>
      approachFromM == null ? pointsM : [approachFromM!, ...pointsM];

  /// How far along the path each leg of the spoken route ends.
  ///
  /// The join between the two descriptions. Native measures progress against
  /// the whole path; guidance counts down one leg at a time; this is what lets
  /// one number be turned into the other, so the ring on the floor and the
  /// voice in the walker's ear are talking about the same corridor.
  ///
  /// One entry per leg of the matching [PlannedRoute], in the same order.
  final List<double> legEndsM;

  /// Total walked length of the path.
  double get totalM {
    var total = 0.0;
    for (var i = 0; i + 1 < pointsM.length; i++) {
      total += (pointsM[i + 1] - pointsM[i]).distance;
    }
    return total;
  }

  /// How far along the path leg [index] begins.
  double startOfLeg(int index) =>
      index <= 0 ? 0 : legEndsM[(index - 1).clamp(0, legEndsM.length - 1)];
}

extension RoutePathGeometry on RoutePath {
  /// The point [distanceM] along the path, clamped to its ends.
  ///
  /// Used to re-anchor a registration mid-walk: the walker is a known distance
  /// along the route and physically somewhere ARCore can name, and those two
  /// facts are a correspondence exactly like the one at the start.
  Offset pointAtM(double distanceM) {
    if (pointsM.isEmpty) return Offset.zero;
    if (distanceM <= 0) return pointsM.first;

    var remaining = distanceM;
    for (var i = 0; i + 1 < pointsM.length; i++) {
      final span = (pointsM[i + 1] - pointsM[i]).distance;
      if (span < 1e-9) continue;
      if (remaining <= span) {
        return pointsM[i] + (pointsM[i + 1] - pointsM[i]) * (remaining / span);
      }
      remaining -= span;
    }
    return pointsM.last;
  }

  /// The direction the path runs at [distanceM] along it.
  Offset directionAtM(double distanceM) {
    var remaining = distanceM.clamp(0.0, double.infinity);
    for (var i = 0; i + 1 < pointsM.length; i++) {
      final delta = pointsM[i + 1] - pointsM[i];
      final span = delta.distance;
      if (span < 1e-9) continue;
      if (remaining <= span) return delta;
      remaining -= span;
    }
    return pointsM.length < 2
        ? const Offset(0, 1)
        : pointsM.last - pointsM[pointsM.length - 2];
  }

  /// The dominant direction the initial corridor leg runs along.
  ///
  /// Ignores short lateral or diagonal transitions from a side doorway onto the hallway centreline.
  Offset get corridorDepartureDirection {
    if (pointsM.length < 2) return const Offset(0, 1);
    var longest = pointsM[1] - pointsM[0];
    var maxLen = longest.distance;
    final limit = math.min(pointsM.length - 1, 4);
    for (var i = 0; i < limit; i++) {
      final delta = pointsM[i + 1] - pointsM[i];
      final len = delta.distance;
      if (len > maxLen) {
        maxLen = len;
        longest = delta;
      }
    }
    return longest;
  }
}
