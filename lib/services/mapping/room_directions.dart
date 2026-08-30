// Spoken, egocentric directions over a room plan — floorplan spec §6.2.
//
// The plan is **allocentric**: fixed coordinates in a frame with no relation to
// anybody's body. Speech has to be **egocentric**: relative to where the walker
// is facing at that moment. "Left" is not a property of a building, and a
// direction that names one without knowing a heading is guessing.
//
// So a virtual heading is carried through the route and updated leg by leg,
// exactly as the walker's own would be. That is the whole idea, and it is the
// reason these instructions can be spoken to somebody who cannot see the
// corridor to correct them.
//
// ## The door-counting trap, and why the spine matters
//
// "Your destination is the second door on your left" is the single most
// dangerous sentence this app can say. It is confidently wrong — no error
// state, no hedge in the voice — whenever the map is missing a door that the
// walker will nonetheless walk past. `RoomPlan.corridorIsComplete` is the guard
// on that, and directions refuse to count when it fails.
//
// Getting the *geometry* right matters just as much. A leg down a corridor runs
// from one door to another, and both doors are on the walls — so the straight
// line between them cuts diagonally across the corridor. Deciding "left" from
// that diagonal puts doors on the wrong side of it near the ends.
//
// The fix is to measure sides against the corridor's **spine**: a line through
// the corridor's own centre, running in the direction of travel. Doors on the
// left wall then read left wherever along the corridor they sit, which is what
// a walker means. Ordering along the leg uses the same axis.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../core/models/room_plan.dart';
import 'room_geometry.dart';
import 'room_graph.dart';

/// One spoken step of a route.
class RoomInstruction {
  const RoomInstruction({
    required this.text,
    this.distanceM = 0,
    this.turnDegreesRight = 0,
    this.segmentIndex = 0,
  });

  /// What guidance says out loud.
  final String text;

  /// How far this step covers. Zero for a pure turn.
  final double distanceM;

  /// Positive is right, matching `PlannedLeg.turnDeg` and the capture UI's
  /// buttons. Zero for a step that involves no turn.
  final double turnDegreesRight;

  /// Which leg of the route this describes — the index of the waypoint pair,
  /// so `waypoints[segmentIndex]` → `waypoints[segmentIndex + 1]`.
  ///
  /// Carried so a caller can put the sentences back against the geometry that
  /// produced them. `room_plan_bridge.dart` needs exactly that to hand each
  /// spoken instruction to the right leg of a `PlannedRoute`; without it the
  /// only way to re-align them is to re-derive the walk, and two derivations
  /// that disagree would put a door count on the wrong corridor.
  final int segmentIndex;

  @override
  String toString() => text;
}

/// A door the walker passes on one leg, and which side it falls on.
class PassedDoor {
  const PassedDoor({
    required this.openingId,
    required this.roomId,
    required this.alongM,
    required this.onLeft,
  });

  final String openingId;

  /// The room behind the door — a stub when nobody traced it, which is exactly
  /// why stubs have to exist.
  final String? roomId;

  /// Distance along the leg at which it is passed.
  final double alongM;

  final bool onLeft;

  String get side => onLeft ? 'left' : 'right';
}

/// Turns a route into sentences.
///
/// [metresPerUnit] is how long one unit of the plan's coordinate frame is in
/// the real world, and null means nobody knows. A plan traced off a photograph
/// starts out that way — nobody measured the wall board — and quoting "walk
/// twelve metres" from arbitrary plan units is a confidently wrong number in a
/// blind user's ear. When it is null, distances are omitted and the
/// instructions lean on doors and landmarks instead, which are true either
/// way. Same reasoning as `FloorGraph.metric`.
///
/// **It is a multiplier, not a flag.** Everything this class emits with a
/// `distanceM` on it is in metres, converted here, so that a caller cannot
/// receive a number labelled metres that is really a fraction of a
/// photograph's width. That was the bug: the scale a user had taken the
/// trouble to measure was stored, turned `isMetric` true, and was then never
/// applied to anything — so setting it made the spoken distances worse than
/// leaving it unset.
class RoomDirections {
  const RoomDirections({this.metresPerUnit});

  /// Reads the answer off the plan rather than making the caller remember it.
  ///
  /// The safer constructor, and the one screens should use: a caller who
  /// forgets to pass the scale for a traced plan gets metres invented out of
  /// arbitrary units, and nothing about the output looks wrong.
  factory RoomDirections.forPlan(RoomPlan plan) =>
      RoomDirections(metresPerUnit: plan.metresPerUnit);

  /// Real-world length of one plan unit, or null when it was never measured.
  final double? metresPerUnit;

  /// Whether distances may be spoken at all.
  bool get metric => metresPerUnit != null;

  /// The multiplier from plan units to metres, or 1 when there is no scale.
  ///
  /// Only ever used on paths already guarded by [metric], so the fallback
  /// never reaches a spoken sentence — it exists so the arithmetic below reads
  /// the same on both branches.
  double get _scale => metresPerUnit ?? 1;

  /// Describes [route], starting from [initialHeading].
  ///
  /// [initialHeading] is the direction the walker faces when they set off, in
  /// the plan's frame (+x east, +y north). Supply it and the first instruction
  /// orients them — "turn left, then walk…" — which the spec's version omits,
  /// leaving the walker to set off facing whichever way they happened to be
  /// standing. Pass null when the heading genuinely is not known; the first leg
  /// is then described without a turn rather than with a guessed one.
  List<RoomInstruction> describe(
    RoomNavGraph graph,
    RoomRoute route, {
    Offset? initialHeading,
  }) {
    if (route.isEmpty) return const [];

    final plan = graph.plan;
    final out = <RoomInstruction>[];
    var heading = initialHeading;

    for (var i = 0; i + 1 < route.waypoints.length; i++) {
      final from = route.waypoints[i];
      final to = route.waypoints[i + 1];
      final leg = to.at - from.at;
      if (leg.distanceSquared < 1e-9) continue;

      // Turn first: the walker has to be facing the leg before they walk it.
      if (heading != null) {
        final turn = turnDegreesRight(heading, leg);
        if (turn.abs() >= _straightAheadDeg) {
          out.add(
            RoomInstruction(
              text: _turnPhrase(turn),
              turnDegreesRight: turn,
              segmentIndex: i,
            ),
          );
        }
      }

      final throughRoomId = graph.roomBetween(from.nodeId, to.nodeId);
      final throughRoom = throughRoomId == null
          ? null
          : plan.roomOf(throughRoomId);

      // Doors passed, when this leg runs along circulation space and the map is
      // allowed to count them.
      if (throughRoom != null &&
          throughRoom.isCirculation &&
          to.openingId != null) {
        final counted = _countDoors(
          plan: plan,
          corridor: throughRoom,
          from: from.at,
          to: to.at,
          targetOpeningId: to.openingId!,
        );
        if (counted != null) {
          out.add(
            RoomInstruction(
              text: _doorPhrase(counted, plan, leg.distance * _scale),
              distanceM: leg.distance * _scale,
              segmentIndex: i,
            ),
          );
          heading = leg / leg.distance;
          continue;
        }
      }

      out.add(
        RoomInstruction(
          text: _walkPhrase(leg.distance * _scale, to, plan, throughRoom),
          distanceM: leg.distance * _scale,
          segmentIndex: i,
        ),
      );
      heading = leg / leg.distance;
    }

    _arrivalTurn(out, route, plan, heading);
    return out;
  }

  /// The turn into the destination, spoken even though it is no longer walked.
  ///
  /// A route runs door to door now (see [RoomNavGraph]), so it stops on the
  /// destination's threshold and the segment that used to generate this — the
  /// stretch from that door to the middle of the room — is not part of the walk
  /// any more. Losing the distance is the point. Losing the *turn* with it was
  /// not: a walker arriving at the end of a corridor still has to know whether
  /// the room is on their left or their right, and on a corridor whose door
  /// ordinals are withheld — declared doors nobody placed — this is the only
  /// thing left that tells them.
  ///
  /// Which side a door is on is something the plan genuinely knows. How far
  /// into the room somebody then walks is not guidance's business, and is why
  /// this emits a turn and no distance.
  void _arrivalTurn(
    List<RoomInstruction> out,
    RoomRoute route,
    RoomPlan plan,
    Offset? heading,
  ) {
    if (heading == null || route.waypoints.length < 2) return;

    final last = route.waypoints.last;
    // A route that ends inside its destination — the shared-door fallback in
    // [RoomNavGraph._doorToDoor] — already walked this turn and said it.
    if (last.kind != WaypointKind.destination || last.openingId == null) return;

    final room = plan.roomOf(last.roomId ?? '');
    // Asking a stub for its centroid is meaningless, not merely imprecise.
    if (room == null || room.isStub) return;

    final into = room.centre - last.at;
    if (into.distanceSquared < 1e-9) return;

    final turn = turnDegreesRight(heading, into);
    if (turn.abs() < _straightAheadDeg) return;

    out.add(
      RoomInstruction(
        text: _turnPhrase(turn),
        turnDegreesRight: turn,
        // The last segment, so it lands on the leg that ends at this door
        // rather than falling off the end of the route.
        segmentIndex: route.waypoints.length - 2,
      ),
    );
  }

  /// Below this, a turn is not worth saying.
  static const double _straightAheadDeg = 20;

  String _turnPhrase(double degreesRight) {
    final side = degreesRight < 0 ? 'left' : 'right';
    final magnitude = degreesRight.abs();
    if (magnitude < _straightAheadDeg) return 'Continue straight ahead.';
    if (magnitude < 60) return 'Bear slightly $side.';
    if (magnitude < 120) return 'Turn $side.';
    if (magnitude < 160) return 'Turn sharply $side.';
    return 'Turn around.';
  }

  String _walkPhrase(
    double distanceM,
    RouteWaypoint to,
    RoomPlan plan,
    Room? throughRoom,
  ) {
    final target = switch (to.kind) {
      WaypointKind.destination =>
        plan.roomOf(to.roomId ?? '')?.spokenName ?? 'your destination',
      WaypointKind.opening => _openingNoun(to.openingId, plan),
      WaypointKind.start => 'the start',
    };

    if (!metric) return 'Continue to $target.';
    return 'Walk ${_roundMetres(distanceM)} to $target.';
  }

  String _openingNoun(String? openingId, RoomPlan plan) {
    for (final opening in plan.openings) {
      if (opening.id == openingId) {
        return opening.isExterior ? 'the exit' : 'the ${opening.spokenNoun}';
      }
    }
    return 'the door';
  }

  /// "Walk 12 metres. Reading Hall is the second door on your left."
  ///
  /// The distance leads, because it is what the walker acts on first and
  /// because this sentence is now the *only* one on a route that is a single
  /// corridor. Door-to-door routing removed the stretch from the destination's
  /// door to the middle of its room, and that stretch used to be what carried a
  /// spoken distance on exactly this shape of walk — leaving a metric plan
  /// describing a whole route without quoting a single number.
  ///
  /// Omitted, as everywhere else, when the plan has no scale: plan units read
  /// out as metres are a confidently wrong number in a blind user's ear.
  String _doorPhrase(_CountedDoors counted, RoomPlan plan, double distanceM) {
    final ordinal = _ordinal(counted.ordinal);
    final behind = counted.targetRoomId == null
        ? null
        : plan.roomOf(counted.targetRoomId!);

    final noun = behind == null || behind.isStub ? 'door' : behind.spokenName;
    final lead = metric ? 'Walk ${_roundMetres(distanceM)}. ' : '';

    if (behind == null || behind.isStub) {
      return '${lead}Your destination is the $ordinal $noun on your '
          '${counted.side}.';
    }
    return '$lead${_sentenceCase(noun)} is the $ordinal door on your '
        '${counted.side}.';
  }

  /// Capitalises a room name for the start of a sentence without touching the
  /// rest of it — `'office GF 2'` becomes `'Office GF 2'`, and a real label
  /// like `'Digital Forensic Office'` is left exactly as its sign reads.
  static String _sentenceCase(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  /// Doors passed on this leg, and where the target sits among them.
  ///
  /// Returns null — meaning "say something neutral instead" — when the corridor
  /// is not known to be complete. An uncounted door on that wall makes every
  /// ordinal after it wrong, so the honest failure is silence about ordinals,
  /// not a number that might be off by one.
  _CountedDoors? _countDoors({
    required RoomPlan plan,
    required Room corridor,
    required Offset from,
    required Offset to,
    required String targetOpeningId,
  }) {
    if (!plan.corridorIsComplete(corridor.id)) return null;

    final passed = doorsPassedAlong(
      plan: plan,
      corridor: corridor,
      from: from,
      to: to,
    );

    final target = passed
        .where((d) => d.openingId == targetOpeningId)
        .firstOrNull;
    if (target == null) return null;

    final sameSide = passed.where((d) => d.onLeft == target.onLeft).toList();
    final ordinal =
        sameSide.indexWhere((d) => d.openingId == targetOpeningId) + 1;
    if (ordinal < 1) return null;

    return _CountedDoors(
      ordinal: ordinal,
      side: target.side,
      targetRoomId: target.roomId,
    );
  }

  /// Rounded the way a person says a distance. Nobody walks 12.4 metres.
  String _roundMetres(double metres) {
    if (metres < 1.5) return 'about a metre';
    final rounded = metres < 10 ? metres.round() : (metres / 5).round() * 5;
    return '$rounded metres';
  }

  static String _ordinal(int n) => switch (n) {
    1 => 'first',
    2 => 'second',
    3 => 'third',
    4 => 'fourth',
    5 => 'fifth',
    6 => 'sixth',
    7 => 'seventh',
    8 => 'eighth',
    9 => 'ninth',
    10 => 'tenth',
    _ => '${n}th',
  };
}

class _CountedDoors {
  const _CountedDoors({
    required this.ordinal,
    required this.side,
    required this.targetRoomId,
  });

  final int ordinal;
  final String side;
  final String? targetRoomId;
}

/// The doors a walker passes going from [from] to [to] along [corridor], in the
/// order they are passed, each with the side it falls on.
///
/// The single implementation of door counting — directions call it, and §10's
/// field harness calls it directly to check a generated route against a wall
/// board without having to parse the spoken sentences.
///
/// ## Why the corridor's axis and not the leg
///
/// The leg runs door-to-door, and doors sit on opposite walls, so the straight
/// line between them is tilted relative to the corridor. In a 2 m-wide corridor
/// a leg ending 1 m off-centre over 10 m is tilted 11°, which drifts 2 m across
/// a 20 m hallway — wider than the corridor itself. Side-of-line against that
/// tilted leg therefore puts the doors at the far end on the *wrong side*, and
/// it does it silently: the sentence still reads perfectly.
///
/// So sides and ordering are both measured against the corridor's own axis
/// through its own centre, signed to point the way the walker is going. That
/// line stays inside the corridor for its whole length, which is what makes
/// "left" mean the left wall.
List<PassedDoor> doorsPassedAlong({
  required RoomPlan plan,
  required Room corridor,
  required Offset from,
  required Offset to,
}) {
  final leg = to - from;
  if (leg.distanceSquared < 1e-9 || corridor.isStub) return const [];

  return corridor.hasSpine
      ? _alongCentreline(plan, corridor, from, to)
      : _alongLongestWall(plan, corridor, from, to, leg);
}

/// Door counting for a corridor drawn as a path.
///
/// The exact version, and the reason [Room.centreline] exists. Position along
/// the corridor is arc length on the centreline, and "left" is measured against
/// the direction of travel **at each door's own position** rather than against
/// one axis for the whole corridor. Both stay correct round a bend, where a
/// single straight axis flips the sides of every door past the corner.
List<PassedDoor> _alongCentreline(
  RoomPlan plan,
  Room corridor,
  Offset from,
  Offset to,
) {
  final spine = corridor.spine;
  final startAlong = projectOntoPolyline(spine, from).along;
  final endAlong = projectOntoPolyline(spine, to).along;

  // Which way along the centreline the walker is going. A corridor is walked
  // both ways and the centreline was drawn only one way.
  final forwards = endAlong >= startAlong;
  if ((endAlong - startAlong).abs() < 1e-9) return const [];

  final passed = <PassedDoor>[];
  for (final opening in plan.openingsOn(corridor.id)) {
    final hit = projectOntoPolyline(spine, opening.position);
    final travelled = forwards
        ? hit.along - startAlong
        : startAlong - hit.along;
    final total = (endAlong - startAlong).abs();
    // Strictly past the start — the door being walked out of is not passed —
    // and no further than the one being walked to, which is.
    if (travelled <= 1e-6 || travelled > total + 1e-6) continue;

    var heading = polylineDirectionAt(spine, hit.along);
    if (!forwards) heading = -heading;

    final side = sideOfLine(hit.at, hit.at + heading, opening.position);
    if (side == 0) continue;

    passed.add(
      PassedDoor(
        openingId: opening.id,
        roomId: opening.otherSideOf(corridor.id),
        alongM: travelled,
        onLeft: side < 0,
      ),
    );
  }

  passed.sort((a, b) => a.alongM.compareTo(b.alongM));
  return passed;
}

/// Door counting for a corridor traced as a bare outline.
///
/// The approximation, kept for every plan drawn before paths existed and for
/// AR capture, which produces polygons. Good for a straight hallway and wrong
/// round a bend — see [longestEdgeDirection].
List<PassedDoor> _alongLongestWall(
  RoomPlan plan,
  Room corridor,
  Offset from,
  Offset to,
  Offset leg,
) {
  // The corridor's axis, flipped if necessary to face the way we are walking.
  final axis = longestEdgeDirection(corridor.corners);
  final forward = (axis.dx * leg.dx + axis.dy * leg.dy) >= 0 ? axis : -axis;

  final spineOrigin = corridor.centre;
  final spineAhead = spineOrigin + forward;

  double along(Offset p) =>
      (p - spineOrigin).dx * forward.dx + (p - spineOrigin).dy * forward.dy;

  final startAlong = along(from);
  final endAlong = along(to);
  if (endAlong <= startAlong) return const [];

  final passed = <PassedDoor>[];
  for (final opening in plan.openingsOn(corridor.id)) {
    final at = along(opening.position);
    if (at <= startAlong + 1e-6 || at > endAlong + 1e-6) continue;

    final side = sideOfLine(spineOrigin, spineAhead, opening.position);
    // Dead on the spine: a door in the end wall rather than a side wall. It has
    // no side, so it is not counted as one — "the door straight ahead" is a
    // different sentence.
    if (side == 0) continue;

    passed.add(
      PassedDoor(
        openingId: opening.id,
        roomId: opening.otherSideOf(corridor.id),
        alongM: at - startAlong,
        onLeft: side < 0,
      ),
    );
  }

  passed.sort((a, b) => a.alongM.compareTo(b.alongM));
  return passed;
}

/// The bearing of [heading] in degrees clockwise from north, for logging and
/// for handing a heading to the compass-based parts of guidance.
double headingDegrees(Offset heading) =>
    (math.atan2(heading.dx, heading.dy) * 180 / math.pi + 360) % 360;
