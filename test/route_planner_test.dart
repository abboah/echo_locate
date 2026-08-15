import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

WalkRoute routeOf(
  String id,
  List<({String from, String to, double distanceM, int turnDeg})> legs,
) => WalkRoute(
  id: id,
  buildingId: 'b1',
  startLandmarkId: legs.first.from,
  destinationRoomId: 'room-$id',
  steps: [
    for (var i = 0; i < legs.length; i++)
      RouteStep(
        seq: i + 1,
        fromLandmarkId: legs[i].from,
        toLandmarkId: legs[i].to,
        instruction: 'walk to ${legs[i].to}',
        distanceM: legs[i].distanceM,
        turnDeg: legs[i].turnDeg,
      ),
  ],
);

({String from, String to, double distanceM, int turnDeg}) leg(
  String from,
  String to, {
  double distanceM = 10,
  int turnDeg = 0,
}) => (from: from, to: to, distanceM: distanceM, turnDeg: turnDeg);

void main() {
  const planner = RoutePlanner();

  test('a landmark that is not on the map has no route', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
    ]);

    expect(planner.plan(graph, from: 'a', to: 'nowhere'), isNull);
    expect(planner.plan(graph, from: 'nowhere', to: 'b'), isNull);
  });

  test('standing at the destination is a route with no legs', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
    ]);

    final plan = planner.plan(graph, from: 'a', to: 'a');

    expect(plan, isNotNull);
    expect(plan!.legs, isEmpty);
    expect(plan.totalDistanceM, 0);
  });

  test('an unconnected landmark has no route', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
      routeOf('r2', [leg('x', 'y')]),
    ]);

    expect(planner.plan(graph, from: 'a', to: 'y'), isNull);
  });

  test('a recorded leg keeps the wording its contributor spoke', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b', distanceM: 14)]),
    ]);

    final plan = planner.plan(graph, from: 'a', to: 'b')!;

    expect(plan.legs.single.instruction, 'walk to b');
    expect(plan.legs.single.distanceM, 14);
    expect(plan.totalDistanceM, 14);
  });

  test('a leg walked against its recording carries no wording', () {
    final graph = FloorGraph.merge([
      routeOf('r1', [leg('a', 'b')]),
    ]);

    final plan = planner.plan(graph, from: 'b', to: 'a')!;

    expect(plan.legs.single.fromLandmarkId, 'b');
    expect(plan.legs.single.instruction, isNull);
  });

  test('the shorter way round is chosen', () {
    final graph = FloorGraph.merge([
      routeOf('long', [
        leg('a', 'b', distanceM: 10),
        leg('b', 'd', distanceM: 10),
      ]),
      routeOf('short', [
        leg('a', 'c', distanceM: 4, turnDeg: 90),
        leg('c', 'd', distanceM: 4, turnDeg: -90),
      ]),
    ]);

    final plan = planner.plan(graph, from: 'a', to: 'd')!;

    expect(plan.landmarkIds, ['a', 'c', 'd']);
    expect(plan.totalDistanceM, closeTo(8, 0.01));
  });

  test('routes recorded separately join up into a walk nobody recorded', () {
    // The demo moment (spec §6 A4): one contributor walked entrance→204,
    // another walked entrance→209. Nobody ever walked 204→209.
    final graph = FloorGraph.merge([
      routeOf('to-204', [
        leg('entrance', 'junction', distanceM: 12),
        leg('junction', '204', distanceM: 8, turnDeg: 90),
      ]),
      routeOf('to-209', [
        leg('entrance', 'junction', distanceM: 12),
        leg('junction', '209', distanceM: 6, turnDeg: -90),
      ]),
    ]);

    final plan = planner.plan(graph, from: '204', to: '209')!;

    expect(plan.landmarkIds, ['204', 'junction', '209']);
    expect(plan.totalDistanceM, closeTo(14, 0.01));
    // Leaving 204 runs against the recording, so nothing is put in the
    // contributor's words; rejoining a recorded direction is spoken as walked.
    expect(plan.legs.first.instruction, isNull);
    expect(plan.legs.last.instruction, 'walk to 209');
  });

  test('a recorded route can be followed without planning', () {
    final recorded = routeOf('r1', [leg('a', 'b'), leg('b', 'c')]);

    final plan = PlannedRoute.fromRecorded(recorded);

    expect(plan.landmarkIds, ['a', 'b', 'c']);
    expect(plan.legs.first.instruction, 'walk to b');
    expect(plan.totalDistanceM, 20);
  });

  group('turns are recomputed from the merged geometry', () {
    // A recorded turnDeg is relative to the leg that preceded it *in that
    // recording*. Splice legs from two walks together and the stored angle
    // refers to an approach the user never made — so it is recomputed from
    // where the landmarks actually ended up.

    test('a corner is measured from the approach actually taken', () {
      // Walk 1 goes north up the spine: south → junction → north.
      // Walk 2 turns off it: south → junction → east.
      final graph = FloorGraph.merge([
        routeOf('spine', [leg('south', 'junction'), leg('junction', 'north')]),
        routeOf('branch', [
          leg('south', 'junction'),
          leg('junction', 'east', turnDeg: 90),
        ]),
      ]);

      // Coming up the spine and turning off onto the branch is a right turn,
      // and nobody recorded that pairing.
      final plan = planner.plan(graph, from: 'south', to: 'east');

      expect(plan, isNotNull);
      expect(plan!.landmarkIds, ['south', 'junction', 'east']);
      expect(plan.legs.last.turnDeg, 90);
    });

    test('the first leg has no approach, so it has no turn', () {
      final graph = FloorGraph.merge([
        routeOf('r', [leg('a', 'b', turnDeg: 90), leg('b', 'c', turnDeg: 90)]),
      ]);

      final plan = planner.plan(graph, from: 'a', to: 'c');

      // Recorded as a 90° turn entering the first leg, but a user starting at
      // 'a' has not come from anywhere — there is nothing to turn relative to.
      expect(plan!.legs.first.turnDeg, 0);
    });

    test('walking a recorded route backwards inverts its corner', () {
      final graph = FloorGraph.merge([
        routeOf('r', [leg('a', 'b'), leg('b', 'c', turnDeg: 90)]),
      ]);

      final forward = planner.plan(graph, from: 'a', to: 'c')!;
      final backward = planner.plan(graph, from: 'c', to: 'a')!;

      expect(forward.legs.last.turnDeg, 90);
      // The same corner taken from the other side is a left turn. Replaying
      // the recorded +90 here would send a blind user into a wall.
      expect(backward.legs.last.turnDeg, -90);
    });

    test('a floor change is described rather than turned into', () {
      // Stairs put both ends at the same point, so there is no direction to
      // measure and no turn to speak.
      final graph = FloorGraph.merge(
        [
          routeOf('r', [
            leg('door', 'stairs-g'),
            leg('stairs-g', 'landing-2'),
            leg('landing-2', 'hall'),
          ]),
        ],
        {
          'door': _landmark('door', 'floor-g'),
          'stairs-g': _landmark('stairs-g', 'floor-g'),
          'landing-2': _landmark('landing-2', 'floor-2'),
          'hall': _landmark('hall', 'floor-2'),
        },
      );

      final plan = planner.plan(graph, from: 'door', to: 'hall')!;

      expect(plan.landmarkIds, ['door', 'stairs-g', 'landing-2', 'hall']);
      // The climb itself, and the leg leaving the landing: neither has a
      // horizontal bearing to turn against.
      expect(plan.legs[1].turnDeg, 0);
      expect(plan.legs[2].turnDeg, 0);
    });
  });

  group('wording only survives where it is still true', () {
    test('a sentence recorded from a different approach is dropped', () {
      // "walk to c" was recorded by somebody arriving at 'b' from 'a'. A user
      // arriving from 'x' is being told something that was never true of their
      // journey, so they are told nothing instead.
      final routes = [
        routeOf('recorded', [leg('a', 'b'), leg('b', 'c')]),
        routeOf('other', [leg('x', 'b')]),
      ];
      final graph = FloorGraph.merge(routes);

      final plan = planner.plan(graph, from: 'x', to: 'c', recorded: routes);

      expect(plan!.landmarkIds, ['x', 'b', 'c']);
      expect(plan.legs.last.instruction, isNull);
      // Silence on a leg is exactly what "stitched from several walks" means.
      expect(plan.synthesised, isTrue);
    });

    test('the same approach keeps the contributor’s words', () {
      final routes = [
        routeOf('recorded', [leg('a', 'b'), leg('b', 'c')]),
      ];
      final graph = FloorGraph.merge(routes);

      final plan = planner.plan(graph, from: 'a', to: 'c', recorded: routes);

      expect(plan!.legs.last.instruction, 'walk to c');
      expect(plan.synthesised, isFalse);
    });

    test('without recordings the edge wording is taken at face value', () {
      // Guidance replans mid-walk with only the graph to hand. That is the
      // main line, and it must not go silent for want of the route list.
      final routes = [
        routeOf('recorded', [leg('a', 'b'), leg('b', 'c')]),
        routeOf('other', [leg('x', 'b')]),
      ];
      final graph = FloorGraph.merge(routes);

      final plan = planner.plan(graph, from: 'x', to: 'c');

      expect(plan!.legs.last.instruction, 'walk to c');
    });
  });
}

Landmark _landmark(String id, String floorId) => Landmark(
  id: id,
  buildingId: 'b1',
  floorId: floorId,
  kind: LandmarkKind.sign,
  labelText: id.toUpperCase(),
  displayName: id,
);
