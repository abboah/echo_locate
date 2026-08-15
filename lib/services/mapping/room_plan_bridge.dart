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
  static FloorGraph floorGraphFrom(RoomPlan plan) {
    final rooms = {for (final room in plan.drawableRooms) room.id: room};
    if (rooms.isEmpty) return FloorGraph.empty;

    final nodes = {
      for (final room in rooms.values)
        landmarkIdFor(room): MapNode(
          landmarkId: landmarkIdFor(room),
          floorId: room.floorId,
          x: room.centre.dx,
          y: room.centre.dy,
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
          distanceM: (a.centre - b.centre).distance,
        ),
      );
    }

    return FloorGraph(nodes: nodes, edges: edges, metric: plan.isMetric);
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

    // Cumulative walked distance at each waypoint, so a leg's length is the
    // polyline the user follows rather than the straight line between two room
    // centres.
    //
    // Each step measured *along the corridor it crosses* when that corridor was
    // drawn as a path. A leg round the bend of an L is longer than the straight
    // line between its ends by however sharp the bend is, and this number is
    // what becomes "about forty steps" in somebody's ear — so the straight line
    // would quietly stop them short of the corner every time.
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

    // Waypoint index at which each room on the walk is entered — one per entry
    // in `roomsPassed`. The first room is entered at the start; every other at
    // the door leading into it.
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

    /// Where leg [k] stops.
    ///
    /// The final leg runs to the last waypoint — the middle of the destination
    /// room — rather than stopping at its door, so the legs partition the whole
    /// polyline and their distances sum to the route. Stopping at the door
    /// instead dropped the last stretch from the total, took the turn into the
    /// room with it, and lost the sentence that names the destination.
    int endOf(int k) => k + 2 == route.roomsPassed.length
        ? route.waypoints.length - 1
        : entryAt[k + 1];

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
          distanceM: cumulative[end] - cumulative[start],
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
