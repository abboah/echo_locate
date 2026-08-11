import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

WalkRoute routeOf(
  String id,
  List<({String from, String to, double distanceM, int turnDeg})> legs,
) =>
    WalkRoute(
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
}) =>
    (from: from, to: to, distanceM: distanceM, turnDeg: turnDeg);

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
      routeOf('long', [leg('a', 'b', distanceM: 10), leg('b', 'd', distanceM: 10)]),
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
}
