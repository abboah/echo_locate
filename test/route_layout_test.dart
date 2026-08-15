import 'dart:math' as math;

import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/route_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// A leg from [from] to [to]: turn first, then walk [distanceM].
RouteStep leg(
  String from,
  String to, {
  required double distanceM,
  int turnDeg = 0,
  int seq = 1,
}) => RouteStep(
  seq: seq,
  fromLandmarkId: from,
  toLandmarkId: to,
  instruction: 'walk',
  distanceM: distanceM,
  turnDeg: turnDeg,
);

WalkRoute routeOf(List<RouteStep> steps) => WalkRoute(
  id: 'r1',
  buildingId: 'b1',
  startLandmarkId: steps.isEmpty ? '' : steps.first.fromLandmarkId,
  destinationRoomId: 'room',
  steps: [for (var i = 0; i < steps.length; i++) steps[i].copyWith(seq: i + 1)],
);

void main() {
  test('a route with no legs lays out nothing', () {
    expect(layout(routeOf([])), isEmpty);
  });

  test('the start landmark sits at the origin', () {
    final nodes = layout(routeOf([leg('a', 'b', distanceM: 12)]));

    expect(nodes.first.landmarkId, 'a');
    expect(nodes.first.x, closeTo(0, 1e-9));
    expect(nodes.first.y, closeTo(0, 1e-9));
  });

  test('one node per landmark, in walking order', () {
    final nodes = layout(
      routeOf([
        leg('a', 'b', distanceM: 10),
        leg('b', 'c', distanceM: 10, turnDeg: 90),
      ]),
    );

    expect(nodes.map((n) => n.landmarkId), ['a', 'b', 'c']);
  });

  test('a leg with no turn advances along the current heading', () {
    final nodes = layout(routeOf([leg('a', 'b', distanceM: 12)]));

    // Heading starts at 0° — due north, which is +y.
    expect(nodes[1].x, closeTo(0, 1e-9));
    expect(nodes[1].y, closeTo(12, 1e-9));
  });

  test('a right turn heads east, a left turn west', () {
    final right = layout(routeOf([leg('a', 'b', distanceM: 10, turnDeg: 90)]));
    final left = layout(routeOf([leg('a', 'b', distanceM: 10, turnDeg: -90)]));

    expect(right[1].x, closeTo(10, 1e-9));
    expect(right[1].y, closeTo(0, 1e-9));
    expect(left[1].x, closeTo(-10, 1e-9));
    expect(left[1].y, closeTo(0, 1e-9));
  });

  test('the turn applies before the leg it is recorded on', () {
    // Two legs, the turn on the second: the walk goes north then east, so the
    // corner is the first leg's end, not the start.
    final nodes = layout(
      routeOf([
        leg('a', 'b', distanceM: 10),
        leg('b', 'c', distanceM: 10, turnDeg: 90),
      ]),
    );

    expect(nodes[1].y, closeTo(10, 1e-9));
    expect(nodes[2].x, closeTo(10, 1e-9));
    expect(nodes[2].y, closeTo(10, 1e-9));
  });

  test('a four-leg square closes on its origin', () {
    final nodes = layout(
      routeOf([
        for (var i = 0; i < 4; i++)
          leg('l$i', 'l${i + 1}', distanceM: 10, turnDeg: 90),
      ]),
    );

    final last = nodes.last;
    final drift = math.sqrt(last.x * last.x + last.y * last.y);
    expect(drift, lessThan(0.01));
  });

  test('sharp turns are honoured', () {
    final nodes = layout(routeOf([leg('a', 'b', distanceM: 10, turnDeg: 135)]));

    // 135° clockwise from north: south-east.
    expect(nodes[1].x, closeTo(10 * math.sin(135 * math.pi / 180), 1e-9));
    expect(nodes[1].y, closeTo(10 * math.cos(135 * math.pi / 180), 1e-9));
  });
}
