import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:echo_locate/services/mapping/graph_route_path.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

WalkRoute routeOf(
  String id,
  List<({String from, String to, double distanceM, int turnDeg})> legs,
) => WalkRoute(
  id: id,
  buildingId: 'b1',
  startLandmarkId: legs.isEmpty ? '' : legs.first.from,
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

Landmark landmark(String id, {String floorId = 'f1'}) => Landmark(
  id: id,
  buildingId: 'b1',
  floorId: floorId,
  kind: LandmarkKind.sign,
  labelText: id.toUpperCase(),
  displayName: id,
);

void main() {
  /// Entrance → desk (10 m straight) → hall (12 m, right 90°).
  FloorGraph graphOf({Map<String, Landmark> landmarks = const {}}) =>
      FloorGraph.merge([
        routeOf('r1', [
          leg('entrance', 'desk', distanceM: 10),
          leg('desk', 'hall', distanceM: 12, turnDeg: 90),
        ]),
      ], landmarks);

  PlannedRoute? planOf(FloorGraph graph) =>
      const RoutePlanner().plan(graph, from: 'entrance', to: 'hall');

  test('THE POINT: a recorded walk becomes a line the AR layer can register', () {
    final graph = graphOf();
    final path = routePathThroughGraph(graph, planOf(graph)!);

    expect(path, isNotNull);
    // One point per landmark, and the turtle laid them out north then east.
    expect(path!.pointsM, hasLength(3));
    expect(path.pointsM[0].dx, closeTo(0, 1e-6));
    expect(path.pointsM[0].dy, closeTo(0, 1e-6));
    expect(path.pointsM[1].dx, closeTo(0, 1e-6));
    expect(path.pointsM[1].dy, closeTo(10, 1e-6));
    expect(path.pointsM[2].dx, closeTo(12, 1e-6));
    expect(path.pointsM[2].dy, closeTo(10, 1e-6));

    // The legs guidance speaks and the distances native measures against have
    // to be the same two legs, in the same order.
    expect(path.legEndsM, hasLength(2));
    expect(path.legEndsM[0], closeTo(10, 1e-6));
    expect(path.legEndsM[1], closeTo(22, 1e-6));
    expect(path.totalM, closeTo(22, 1e-6));
  });

  test('a graph in no particular unit is refused', () {
    final graph = graphOf();
    final unitless = FloorGraph(
      nodes: graph.nodes,
      edges: graph.edges,
      metric: false,
    );

    // Traced off an unmeasured image: A* still routes on it, but laying its
    // lengths into a room in metres would size the building by the tracing.
    expect(routePathThroughGraph(unitless, planOf(graph)!), isNull);
  });

  test('a route that changes floor is refused', () {
    // The stairwell and the landing above it are laid out at the same (x, y) —
    // the climb is real but vertical — so the leg between them is a segment of
    // no length on the floor plane, and ARCore has no idea the walker went up.
    final landmarks = {
      'entrance': landmark('entrance'),
      'desk': landmark('desk'),
      'hall': landmark('hall', floorId: 'f2'),
    };
    final graph = graphOf(landmarks: landmarks);

    expect(routePathThroughGraph(graph, planOf(graph)!), isNull);
  });

  test('a landmark the merge never placed is refused', () {
    final graph = graphOf();
    final plan = planOf(graph)!;
    final withoutHall = FloorGraph(
      nodes: {...graph.nodes}..remove('hall'),
      edges: graph.edges,
    );

    // Joining its neighbours instead would draw the route through whatever is
    // between them.
    expect(routePathThroughGraph(withoutHall, plan), isNull);
  });

  test('geometry that contradicts the recorded walk is refused', () {
    final graph = graphOf();
    final plan = planOf(graph)!;
    // The desk parked forty metres from where the walk says it is — what an
    // unanchored route looks like once it is dropped on the map beside the
    // rest rather than joined to it.
    final displaced = FloorGraph(
      nodes: {
        ...graph.nodes,
        'desk': graph.nodeOf('desk')!.moved(40, 40),
      },
      edges: graph.edges,
    );

    expect(routePathThroughGraph(displaced, plan), isNull);
  });

  test('the metre or two the merge averages away is carried, not refused', () {
    final graph = graphOf();
    final plan = planOf(graph)!;
    // A landmark seen by two walks and averaged between them lands slightly
    // off either one. That is the drift a landmark re-centring removes, and
    // refusing it would throw away the geometry to avoid an error smaller than
    // the one that remains without it.
    final nudged = FloorGraph(
      nodes: {
        ...graph.nodes,
        'desk': graph.nodeOf('desk')!.moved(0.8, 10.6),
      },
      edges: graph.edges,
    );

    expect(routePathThroughGraph(nudged, plan), isNotNull);
  });
}
