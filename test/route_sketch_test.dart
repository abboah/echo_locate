import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/features/guidance/guidance_session.dart';
import 'package:echo_locate/services/mapping/room_plan_bridge.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';
import 'package:echo_locate/services/mapping/route_sketch.dart';
import 'package:flutter_test/flutter_test.dart';

PlannedLeg leg(String from, String to, double distanceM, {int turnDeg = 0}) =>
    PlannedLeg(
      fromLandmarkId: from,
      toLandmarkId: to,
      distanceM: distanceM,
      turnDeg: turnDeg,
    );

Landmark landmark(String id) => Landmark(
  id: id,
  buildingId: 'b1',
  floorId: 'f1',
  kind: LandmarkKind.sign,
  labelText: id.toUpperCase(),
  displayName: id,
);

/// Straight on for 10, then right for 5.
PlannedRoute routeOf() => PlannedRoute(
  legs: [
    leg('entrance', 'desk', 10),
    leg('desk', 'hall', 5, turnDeg: 90),
  ],
);

GuidanceSession sessionOf({RoutePath? path}) => GuidanceSession(
  plan: routeOf(),
  landmarks: [landmark('entrance'), landmark('desk'), landmark('hall')],
  destinationName: 'Reading Hall',
  routePath: path,
);

void main() {
  group('the turtle', () {
    test('turns and lengths become a shape', () {
      final sketch = RouteSketch.fromTurns(routeOf())!;

      // Heading 0 is +y, and a positive turn goes right toward +x — the same
      // convention `route_layout` and `route_registration` use, so a drawing
      // and an arrow mean the same thing by a right angle.
      expect(sketch.points, hasLength(3));
      expect(sketch.points[0], const Offset(0, 0));
      expect(sketch.points[1].dx, closeTo(0, 1e-9));
      expect(sketch.points[1].dy, closeTo(10, 1e-9));
      expect(sketch.points[2].dx, closeTo(5, 1e-9));
      expect(sketch.points[2].dy, closeTo(10, 1e-9));

      expect(sketch.legEnds, hasLength(2));
      expect(sketch.legEnds[0], closeTo(10, 1e-9));
      expect(sketch.legEnds[1], closeTo(15, 1e-9));
      expect(sketch.totalLength, closeTo(15, 1e-9));
      // And says what it is: a diagram of the way, not a survey of the floor.
      expect(sketch.surveyed, isFalse);
    });

    test('a route with no legs draws nothing rather than a dot', () {
      expect(RouteSketch.fromTurns(const PlannedRoute(legs: [])), isNull);
    });
  });

  group('choosing a source', () {
    test('measured geometry wins where there is any', () {
      final sketch = RouteSketch.of(
        sessionOf(
          path: const RoutePath(
            pointsM: [Offset(0, 0), Offset(0, 20), Offset(12, 20)],
            legEndsM: [20, 32],
          ),
        ),
      )!;

      expect(sketch.surveyed, isTrue);
      expect(sketch.totalLength, closeTo(32, 1e-9));
    });

    test('a route with no scale still gets a line', () {
      // The commonest case in this app: a plan traced off a photograph that
      // nobody measured. Refusing to draw it would leave a blank panel where
      // the map belongs on most walks.
      final sketch = RouteSketch.of(sessionOf())!;

      expect(sketch.surveyed, isFalse);
      expect(sketch.isDrawable, isTrue);
    });
  });

  group('walking along it', () {
    test('the point and the walked line agree at the same distance', () {
      final sketch = RouteSketch.fromTurns(routeOf())!;

      expect(sketch.pointAt(4).dy, closeTo(4, 1e-9));
      expect(sketch.pointAt(12).dx, closeTo(2, 1e-9));
      expect(sketch.upTo(12).last, sketch.pointAt(12));
      // Clamped at both ends rather than extrapolated through the wall behind.
      expect(sketch.pointAt(-3), sketch.points.first);
      expect(sketch.pointAt(99), sketch.points.last);
    });

    test('THE POINT: progress is a fraction of a leg, not a distance', () {
      // The sketch is in plan units and `walkedM` is real metres. On a traced
      // plan those are different units, and adding one to the other walks the
      // dot off the end of a small plan within a few strides. Halfway down a
      // 5 m leg is halfway down the leg however either is measured.
      final sketch = RouteSketch.fromTurns(routeOf())!;

      final along = sketch.progressAlong(
        legIndex: 1,
        walkedM: 21,
        legMetres: 42,
      );

      // Leg 1 runs from 10 to 15 on the line; half of it is 12.5.
      expect(along, closeTo(12.5, 1e-9));
    });

    test('a leg whose length nobody knows leaves the walker at its start', () {
      final sketch = RouteSketch.fromTurns(routeOf())!;

      // `legMetres` is zero before a traced plan has learned its scale. The
      // honest position then is the last place the walker was known to be,
      // which is the landmark they set off from.
      expect(
        sketch.progressAlong(legIndex: 1, walkedM: 8, legMetres: 0),
        closeTo(10, 1e-9),
      );
    });

    test('overshooting a leg does not run into the next one', () {
      final sketch = RouteSketch.fromTurns(routeOf())!;

      expect(
        sketch.progressAlong(legIndex: 0, walkedM: 40, legMetres: 10),
        closeTo(10, 1e-9),
      );
    });
  });
}
