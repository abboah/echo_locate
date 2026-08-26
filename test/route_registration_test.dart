import 'dart:math' as math;

import 'package:echo_locate/services/mapping/route_registration.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plan frame: +x east, +y north, metres.
/// World frame: ARCore's floor, +x right of the initial pose, −z forward.
void main() {
  const origin = WorldPoint(0, 0);
  const north = Offset(0, 1);
  const east = Offset(1, 0);
  const south = Offset(0, -1);
  const west = Offset(-1, 0);

  double deg(double radians) => radians * 180 / math.pi;
  double rad(double degrees) => degrees * math.pi / 180;

  Matcher closeToPoint(double x, double z) => predicate<WorldPoint>(
    (p) => (p.x - x).abs() < 1e-9 && (p.z - z).abs() < 1e-9,
    'world point near ($x, $z)',
  );

  Matcher closeToOffset(double x, double y) => predicate<Offset>(
    (p) => (p.dx - x).abs() < 1e-9 && (p.dy - y).abs() < 1e-9,
    'plan point near ($x, $y)',
  );

  group('solving', () {
    test('a walker heading up the plan with the phone forward is identity', () {
      // Standing at the plan origin, walking plan-north, and ARCore says they
      // are walking straight ahead. Nothing is rotated.
      final r = Registration.solve(
        planAt: Offset.zero,
        planDirection: north,
        worldAt: origin,
        worldHeadingRad: 0,
        confidence: RegistrationConfidence.measured,
      )!;

      expect(deg(r.yawRad), closeTo(0, 1e-9));
      // Ten metres north on the plan is ten metres straight ahead, which in
      // ARCore is −z. This is the assertion the flip exists for: without it
      // the destination lands behind the walker.
      expect(r.worldFromPlan(const Offset(0, 10)), closeToPoint(0, -10));
      // And ten metres east on the plan is ten metres to the right.
      expect(r.worldFromPlan(const Offset(10, 0)), closeToPoint(10, 0));
    });

    test('a walker heading east with the phone forward rotates the plan', () {
      // Same standing position, but the route leaves eastward while ARCore
      // still reports travel straight ahead. The plan has to turn 90° left
      // under them so that plan-east becomes world-forward.
      final r = Registration.solve(
        planAt: Offset.zero,
        planDirection: east,
        worldAt: origin,
        worldHeadingRad: 0,
        confidence: RegistrationConfidence.measured,
      )!;

      expect(deg(r.yawRad), closeTo(-90, 1e-9));
      expect(r.worldFromPlan(const Offset(10, 0)), closeToPoint(0, -10));
      // Plan north is then off to the walker's left, which is −x.
      expect(r.worldFromPlan(const Offset(0, 10)), closeToPoint(-10, 0));
    });

    test('the walker being somewhere other than the plan origin', () {
      final r = Registration.solve(
        planAt: const Offset(30, 12),
        planDirection: north,
        worldAt: const WorldPoint(-4, 7),
        worldHeadingRad: 0,
        confidence: RegistrationConfidence.measured,
      )!;

      // The anchor maps to the anchor, whatever else happens.
      expect(r.worldFromPlan(const Offset(30, 12)), closeToPoint(-4, 7));
      expect(r.worldFromPlan(const Offset(30, 22)), closeToPoint(-4, -3));
    });

    test('a route whose first two waypoints coincide refuses to solve', () {
      expect(
        Registration.solve(
          planAt: Offset.zero,
          planDirection: Offset.zero,
          worldAt: origin,
          worldHeadingRad: 1,
          confidence: RegistrationConfidence.measured,
        ),
        isNull,
      );
    });
  });

  group('handedness — a square walked in both frames', () {
    /// The test the header promises. Distances alone cannot catch a mirrored
    /// transform: a reflected square has the same side lengths as a real one.
    /// Walking it in order and checking the *turns* can, because a mirror
    /// turns every left into a right.
    test('a clockwise square on the plan is clockwise in the world', () {
      final r = Registration.solve(
        planAt: Offset.zero,
        planDirection: north,
        worldAt: origin,
        worldHeadingRad: 0,
        confidence: RegistrationConfidence.measured,
      )!;

      // North, east, south, west — a clockwise circuit seen from above.
      const planLoop = [
        Offset(0, 0),
        Offset(0, 10),
        Offset(10, 10),
        Offset(10, 0),
      ];
      final world = planLoop.map(r.worldFromPlan).toList();

      // Cross products of consecutive edges. Seen from above with +z toward
      // the viewer, a clockwise circuit turns one consistent way throughout,
      // and a mirrored one turns the other. All four must share a sign.
      final signs = <double>[];
      for (var i = 0; i < world.length; i++) {
        final a = world[i];
        final b = world[(i + 1) % world.length];
        final c = world[(i + 2) % world.length];
        final abx = b.x - a.x;
        final abz = b.z - a.z;
        final bcx = c.x - b.x;
        final bcz = c.z - b.z;
        signs.add(abx * bcz - abz * bcx);
      }

      expect(signs.every((s) => s > 0), isTrue, reason: 'turns: $signs');
    });

    test('a right turn on the plan is a right turn in the world', () {
      final r = Registration.solve(
        planAt: Offset.zero,
        planDirection: north,
        worldAt: origin,
        worldHeadingRad: 0,
        confidence: RegistrationConfidence.measured,
      )!;

      // Walking north then turning to walk east is a right turn. In world
      // bearings — clockwise from forward — that must be +90, not −90.
      final before = r.worldBearingFor(north);
      final after = r.worldBearingFor(east);
      expect(deg(after - before), closeTo(90, 1e-9));

      // And the other three, so a sign error cannot hide in one quadrant.
      expect(deg(r.worldBearingFor(south) - before), closeTo(180, 1e-9));
      expect(deg(r.worldBearingFor(west) - before), closeTo(-90, 1e-9));
    });
  });

  group('round trip', () {
    test('planFromWorld undoes worldFromPlan at an arbitrary rotation', () {
      final r = Registration.solve(
        planAt: const Offset(5, -3),
        planDirection: const Offset(0.6, 0.8),
        worldAt: const WorldPoint(11, 2),
        worldHeadingRad: rad(37),
        confidence: RegistrationConfidence.measured,
      )!;

      for (final p in const [
        Offset(0, 0),
        Offset(12, 40),
        Offset(-8, 3),
        Offset(5, -3),
      ]) {
        expect(r.planFromWorld(r.worldFromPlan(p)), closeToOffset(p.dx, p.dy));
      }
    });

    test('distances survive the transform — it is rigid', () {
      final r = Registration.solve(
        planAt: const Offset(2, 2),
        planDirection: const Offset(-1, 2),
        worldAt: const WorldPoint(-7, 4),
        worldHeadingRad: rad(-113),
        confidence: RegistrationConfidence.guessed,
      )!;

      const a = Offset(0, 0);
      const b = Offset(9, 12); // 15 metres away.
      expect(
        r.worldFromPlan(a).distanceTo(r.worldFromPlan(b)),
        closeTo(15, 1e-9),
      );
    });
  });

  group('recentring at a landmark', () {
    test('moves the origin without touching the rotation', () {
      final drifted = Registration.solve(
        planAt: Offset.zero,
        planDirection: north,
        worldAt: origin,
        worldHeadingRad: rad(20),
        confidence: RegistrationConfidence.measured,
      )!;

      // The walker is confirmed at a door 20 m north on the plan, but ARCore
      // has them somewhere that does not quite agree — a metre of drift.
      final fixed = drifted.recentredAt(
        planAt: const Offset(0, 20),
        worldAt: const WorldPoint(7.5, -18.0),
      );

      expect(fixed.yawRad, drifted.yawRad);
      expect(fixed.worldFromPlan(const Offset(0, 20)), closeToPoint(7.5, -18));
      // Everything else moves with it, by exactly the correction applied.
      final beforeElsewhere = drifted.worldFromPlan(const Offset(4, 30));
      final afterElsewhere = fixed.worldFromPlan(const Offset(4, 30));
      final correction = drifted
          .worldFromPlan(const Offset(0, 20))
          .distanceTo(const WorldPoint(7.5, -18));
      expect(
        beforeElsewhere.distanceTo(afterElsewhere),
        closeTo(correction, 1e-9),
      );
    });
  });
}
