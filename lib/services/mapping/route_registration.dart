// Putting a floor plan into the room — floorplan spec §6.4.
//
// Everything else in `services/mapping` works in the plan's own frame: a flat
// drawing with +x east and +y north and an origin wherever the tracing started.
// ARCore works in a frame it invents at session start, with +y up and the floor
// in the x–z plane. Guidance has always bridged the two by refusing to: it
// walked a chain of *relative* turns, each one measured from the last, so no
// absolute direction was ever needed and none was ever known.
//
// That is why the arrow could not navigate. A chain of relative turns is only
// as good as the direction the first link was hung from, and that direction was
// whichever way the phone happened to be pointing when the walk began. Nothing
// downstream could recover from it, because nothing downstream knew.
//
// This file computes the missing link: one rotation and one translation that
// carry plan coordinates into ARCore's world. With it the whole route can be
// laid into the room at once, and the arrow points at the actual destination
// rather than at the far end of a guess.
//
// ## What it takes to solve, and why that much is available
//
// A similarity transform in the plane has four unknowns: scale, rotation, and
// two of translation. Scale is not one of them here — `RoomPlan.metresPerUnit`
// is measured by the user and applied in `room_plan_bridge.dart`, so both
// frames are already in metres. That leaves three, and three is exactly what
// one point plus one direction gives you:
//
//   * **the point** — the walker is standing at a known place on the plan when
//     guidance starts, because they picked the room they are in. Their ARCore
//     position at that moment is the same place in the other frame.
//   * **the direction** — after a few steps ARCore knows which way they are
//     travelling, and the plan knows which way the first leg of their route
//     runs. Assume those are the same direction and the rotation falls out.
//
// The assumption in the second one is the whole risk of this file, and it is
// deliberately a small one: it is asked at the moment a walker sets off toward
// a destination they have just chosen, down the only corridor leaving the room
// they said they are in. [Registration.confidence] is what a caller uses to
// decide whether to trust it, and re-registering at a confirmed landmark
// replaces the assumption with a measurement.
//
// ## The handedness trap
//
// The plan is a right-handed 2D frame read from above: +x east, +y north. The
// floor of ARCore's world, read the same way, is *left*-handed — +x is east if
// you like, but +z runs toward the viewer, which is south. So the transform
// between them is not a rotation. It is a rotation and a flip, and the flip is
// invisible in every test that only checks distances. `worldFromPlan` below
// carries it, and `route_registration_test` walks a square in both frames to
// pin it down.

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A point on the floor of ARCore's world, in metres.
///
/// Only x and z: the arrows live on the floor, whose height is assumed rather
/// than measured (`ArGuidanceHandler.EYE_HEIGHT_M`), so a third coordinate here
/// would be three decimal places of fiction.
class WorldPoint {
  const WorldPoint(this.x, this.z);

  final double x;
  final double z;

  double distanceTo(WorldPoint other) {
    final dx = x - other.x;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dz * dz);
  }

  @override
  String toString() => 'WorldPoint(${x.toStringAsFixed(2)}, '
      '${z.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      other is WorldPoint && other.x == x && other.z == z;

  @override
  int get hashCode => Object.hash(x, z);
}

/// How much a [Registration] deserves to be believed.
enum RegistrationConfidence {
  /// Solved from a measured direction of travel. The normal case once the
  /// walker has taken a few steps.
  measured,

  /// Solved from where the phone was pointing, because there was no motion to
  /// read. Better than nothing — a walker usually does face the way they are
  /// about to go — but wrong often enough that the screen should say so and
  /// the first few steps should replace it.
  guessed,
}

/// The transform from plan coordinates into ARCore's world.
///
/// Solve one with [Registration.solve] and apply it with [worldFromPlan]. It is
/// immutable: re-registering makes a new one rather than moving an existing
/// one, so a frame drawn half way through an update cannot mix two transforms.
class Registration {
  const Registration({
    required this.yawRad,
    required this.planAnchor,
    required this.worldAnchor,
    required this.confidence,
  });

  /// Rotation from plan bearings to world bearings, in radians.
  ///
  /// Both bearings are measured the way the rest of this repo measures them:
  /// clockwise from "forward", where forward is plan +y and world −z. Adding
  /// this to a plan bearing gives the world bearing of the same line.
  final double yawRad;

  /// The plan point that [worldAnchor] is the same place as, in metres.
  final Offset planAnchor;

  /// Where [planAnchor] is in ARCore's world.
  final WorldPoint worldAnchor;

  final RegistrationConfidence confidence;

  /// Solves for the transform from one correspondence and one direction.
  ///
  /// [planAt] and [planDirection] are in the plan's frame — the position the
  /// walker occupies and the direction the route leaves it in. [worldAt] and
  /// [worldHeadingRad] are the same two things as ARCore sees them.
  ///
  /// Returns null for a [planDirection] with no length, which is a route whose
  /// first two waypoints are the same place: there is no direction in it to
  /// match, and solving anyway would rotate the building by whatever the noise
  /// in an atan2 of two zeroes came to.
  static Registration? solve({
    required Offset planAt,
    required Offset planDirection,
    required WorldPoint worldAt,
    required double worldHeadingRad,
    required RegistrationConfidence confidence,
  }) {
    if (planDirection.distanceSquared < 1e-12) return null;

    return Registration(
      yawRad: worldHeadingRad - planBearingOf(planDirection),
      planAnchor: planAt,
      worldAnchor: worldAt,
      confidence: confidence,
    );
  }

  /// Bearing of a plan-frame direction, clockwise from plan north (+y).
  ///
  /// The same convention `PlannedLeg.turnDeg`, `route_layout` and
  /// `ArGuidanceHandler`'s trail all use, so a turn of ninety degrees means the
  /// same thing in all four.
  static double planBearingOf(Offset direction) =>
      math.atan2(direction.dx, direction.dy);

  /// Bearing of a world-frame direction, clockwise from world forward (−z).
  static double worldBearingOf(double dx, double dz) => math.atan2(dx, -dz);

  /// Where a plan point lands in ARCore's world.
  WorldPoint worldFromPlan(Offset planPoint) {
    final dx = planPoint.dx - planAnchor.dx;
    final dy = planPoint.dy - planAnchor.dy;
    final cos = math.cos(yawRad);
    final sin = math.sin(yawRad);

    // The rotation *and the flip* — see the handedness note in the header.
    // Plan +y is world −z, so the second row is negated relative to the
    // rotation matrix you would write for two frames of the same handedness.
    // With yaw zero this reduces to (x, y) -> (x, -y), which is the identity
    // between a plan read from above and a floor read from above.
    return WorldPoint(
      worldAnchor.x + dx * cos + dy * sin,
      worldAnchor.z + dx * sin - dy * cos,
    );
  }

  /// Where a world point falls on the plan. The inverse of [worldFromPlan].
  ///
  /// Used to answer "which room am I standing in", which is the question the
  /// whole app could not previously ask.
  Offset planFromWorld(WorldPoint world) {
    final dx = world.x - worldAnchor.x;
    final dz = world.z - worldAnchor.z;
    final cos = math.cos(yawRad);
    final sin = math.sin(yawRad);

    // The transform above is its own inverse in structure — a rotation
    // composed with a reflection is an involution up to the rotation's sign —
    // so this is the same matrix with the rotation run backwards.
    return Offset(
      planAnchor.dx + dx * cos + dz * sin,
      planAnchor.dy + dx * sin - dz * cos,
    );
  }

  /// The world bearing of a plan-frame direction.
  double worldBearingFor(Offset planDirection) =>
      yawRad + planBearingOf(planDirection);

  /// The same transform re-solved against a fresh correspondence.
  ///
  /// What a confirmed landmark buys: the walker is standing at a known place,
  /// so the translation can be replaced outright and the accumulated drift
  /// with it. The rotation is kept — one point says nothing about it — which
  /// is also why this cannot repair a registration that came out facing the
  /// wrong way. Only motion does that.
  Registration recentredAt({
    required Offset planAt,
    required WorldPoint worldAt,
  }) => Registration(
    yawRad: yawRad,
    planAnchor: planAt,
    worldAnchor: worldAt,
    confidence: confidence,
  );

  @override
  String toString() =>
      'Registration(yaw ${(yawRad * 180 / math.pi).toStringAsFixed(0)}deg, '
      'plan $planAnchor = $worldAnchor, ${confidence.name})';
}
