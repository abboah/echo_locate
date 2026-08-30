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

  group('plan grid', () {
    test('a rectilinear route reports the axis its corridors run on', () {
      // North 10, east 8, north 6: three legs on two perpendicular axes, which
      // is one grid.
      final path = [
        const Offset(0, 0),
        const Offset(0, 10),
        const Offset(8, 10),
        const Offset(8, 16),
      ];
      expect(deg(Registration.planGridOf(path)!), closeTo(0, 1e-6));
    });

    test('a route on a building rotated 30 degrees reports 30', () {
      final turn = rad(30);
      // Rotated the way a *bearing* runs — clockwise from plan north — so that
      // turning the building by thirty degrees turns every leg's bearing by
      // thirty too. The other sign convention would be just as correct and
      // would read as sixty, which is the same folded grid seen from its other
      // axis.
      Offset rotate(Offset p) => Offset(
        p.dx * math.cos(turn) + p.dy * math.sin(turn),
        -p.dx * math.sin(turn) + p.dy * math.cos(turn),
      );
      final path = [
        const Offset(0, 0),
        const Offset(0, 10),
        const Offset(8, 10),
      ].map(rotate).toList();

      // Folded to a quarter turn, so a 30-degree building reads as 30 whichever
      // of its axes the route happened to start along.
      expect(deg(Registration.planGridOf(path)!), closeTo(30, 1e-6));
    });

    test('legs shorter than a corridor do not vote', () {
      // A 20m corridor with a 1m dogleg round a pillar at 45 degrees. The
      // dogleg is the one leg that is not on the grid, and it is excluded by
      // length before it can drag the answer off.
      final path = [
        const Offset(0, 0),
        const Offset(0, 20),
        const Offset(0.7, 20.7),
        const Offset(0.7, 40),
      ];
      expect(deg(Registration.planGridOf(path)!), closeTo(0, 1e-6));
    });

    test('a path with no leg long enough has no grid', () {
      final path = [
        const Offset(0, 0),
        const Offset(0, 1),
        const Offset(1, 1),
      ];
      expect(Registration.planGridOf(path), isNull);
    });

    test('legs that disagree too much are not a grid', () {
      // A curve: every leg long, none of them on a common axis.
      final path = <Offset>[];
      for (var i = 0; i <= 8; i++) {
        final a = rad(i * 11.0);
        path.add(Offset(math.sin(a) * 40, math.cos(a) * 40));
      }
      expect(Registration.planGridOf(path), isNull);
    });
  });

  group('snapping to a wall grid', () {
    // A walk straight up the plan, where ARCore's forward happens to be plan
    // north, so the true yaw is zero.
    final path = [
      const Offset(0, 0),
      const Offset(0, 20),
      const Offset(8, 20),
    ];

    Registration solvedWithYawError(double errorDeg) => Registration.solve(
      planAt: Offset.zero,
      planDirection: north,
      worldAt: origin,
      // The walker set off a few degrees off the corridor — out of a doorway,
      // round somebody — and the whole building inherits it.
      worldHeadingRad: rad(errorDeg),
      confidence: RegistrationConfidence.measured,
    )!;

    test('takes a few degrees of departure error back out', () {
      final wrong = solvedWithYawError(9);
      expect(deg(wrong.yawRad), closeTo(9, 1e-9));

      // 9 degrees at 20 metres is over three metres off the line.
      expect(
        wrong.worldFromPlan(const Offset(0, 20)).distanceTo(
          const WorldPoint(0, -20),
        ),
        greaterThan(3),
      );

      final snapped = wrong.snappedToGrid(
        // The walls say the building runs along ARCore's own axes.
        worldGridRad: 0,
        planGridRad: Registration.planGridOf(path),
      );

      expect(deg(snapped.yawRad), closeTo(0, 1e-9));
      expect(
        snapped.worldFromPlan(const Offset(0, 20)),
        closeToPoint(0, -20),
      );
    });

    test('picks the quarter turn the measured yaw is nearest', () {
      // The walker set off down a corridor that runs east in the plan, so the
      // true yaw is a quarter turn away from the previous case. The grid is
      // identical — that is what folding costs — and the measured yaw is the
      // only thing that can choose.
      final wrong = solvedWithYawError(87);
      final snapped = wrong.snappedToGrid(
        worldGridRad: 0,
        planGridRad: Registration.planGridOf(path),
      );
      expect(deg(snapped.yawRad), closeTo(90, 1e-9));
    });

    test('a building at an angle snaps onto that angle, not onto zero', () {
      final wrong = Registration.solve(
        planAt: Offset.zero,
        planDirection: north,
        worldAt: origin,
        worldHeadingRad: rad(28),
        confidence: RegistrationConfidence.measured,
      )!;

      // Walls measured at 33 degrees: the building really is skewed relative to
      // where the session started, and the answer is the walls' angle.
      final snapped = wrong.snappedToGrid(
        worldGridRad: rad(33),
        planGridRad: Registration.planGridOf(path),
      );
      expect(deg(snapped.yawRad), closeTo(33, 1e-9));
    });

    test('refuses a correction too large to be departure error', () {
      // 40 degrees is not a walker leaving a doorway untidily. Either the
      // measured yaw landed in the wrong quadrant or the planes fitted are not
      // the corridor's, and rotating the building onto that is worse than the
      // error already there.
      final wrong = solvedWithYawError(40);
      final snapped = wrong.snappedToGrid(
        worldGridRad: 0,
        planGridRad: Registration.planGridOf(path),
      );
      expect(snapped.yawRad, wrong.yawRad);
    });

    test('no walls means the registration is left exactly as solved', () {
      final wrong = solvedWithYawError(9);
      expect(
        wrong
            .snappedToGrid(
              worldGridRad: null,
              planGridRad: Registration.planGridOf(path),
            )
            .yawRad,
        wrong.yawRad,
      );
    });

    test('an unsquare plan means the registration is left as solved', () {
      final wrong = solvedWithYawError(9);
      expect(
        wrong.snappedToGrid(worldGridRad: 0, planGridRad: null).yawRad,
        wrong.yawRad,
      );
    });

    test('the anchor is untouched by a snap', () {
      final wrong = solvedWithYawError(9);
      final snapped = wrong.snappedToGrid(
        worldGridRad: 0,
        planGridRad: Registration.planGridOf(path),
      );
      // The walker is still standing where they are standing. Only the
      // building's rotation about them changed.
      expect(snapped.planAnchor, wrong.planAnchor);
      expect(snapped.worldAnchor, wrong.worldAnchor);
      expect(snapped.confidence, wrong.confidence);
    });
  });
}
