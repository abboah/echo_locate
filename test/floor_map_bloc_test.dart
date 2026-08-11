import 'package:echo_locate/core/models/building.dart';
import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/traced_plan.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/routing/bloc/floor_map_bloc.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRoutes extends Mock implements RouteRepository {}

class _MockBuildings extends Mock implements BuildingRepository {}

void main() {
  late _MockRoutes routes;

  setUp(() {
    routes = _MockRoutes();
    // Most of these cases are about recorded walks, so the default is a
    // building nobody has traced. The cases that are about tracing override it.
    when(() => routes.tracedPlanOf('b1')).thenAnswer((_) async => null);
  });

  Landmark landmark(String id, {String? roomId}) => Landmark(
        id: id,
        buildingId: 'b1',
        floorId: 'f1',
        kind: LandmarkKind.sign,
        labelText: id.toUpperCase(),
        displayName: id,
        roomId: roomId,
      );

  WalkRoute route(String id, List<(String, String)> legs, {String? room}) =>
      WalkRoute(
        id: id,
        buildingId: 'b1',
        startLandmarkId: legs.first.$1,
        destinationRoomId: room ?? 'room-$id',
        steps: [
          for (var i = 0; i < legs.length; i++)
            RouteStep(
              seq: i + 1,
              fromLandmarkId: legs[i].$1,
              toLandmarkId: legs[i].$2,
              instruction: 'walk to ${legs[i].$2}',
              distanceM: 10,
            ),
        ],
      );

  Future<FloorMapBloc> loaded() async {
    final bloc = FloorMapBloc(routes);
    bloc.add(const FloorMapRequested('b1'));
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return bloc;
  }

  test('a building nobody has walked has no map yet', () async {
    when(() => routes.landmarksOf('b1')).thenAnswer((_) async => []);
    when(() => routes.routesOf('b1')).thenAnswer((_) async => []);

    final bloc = await loaded();

    expect(bloc.state.status, FloorMapStatus.empty);
    await bloc.close();
  });

  test('recorded walks are merged into one map', () async {
    when(() => routes.landmarksOf('b1')).thenAnswer(
      (_) async => [landmark('entrance'), landmark('junction'), landmark('204')],
    );
    when(() => routes.routesOf('b1')).thenAnswer(
      (_) async => [
        route('r1', [('entrance', 'junction'), ('junction', '204')]),
      ],
    );

    final bloc = await loaded();

    expect(bloc.state.status, FloorMapStatus.ready);
    expect(bloc.state.graph.nodes.keys, hasLength(3));
    // The walk starts where the contributor started.
    expect(bloc.state.fromId, 'entrance');
    await bloc.close();
  });

  test('a map opened cold looks up the building it belongs to', () async {
    // Reached from the Profile shortcut there is no Building object to read a
    // name from, and the screen was headed "Building".
    final buildings = _MockBuildings();
    when(() => buildings.byId('b1')).thenAnswer(
      (_) async => const Building(
        id: 'b1',
        name: 'KNUST Library',
        area: 'KNUST',
        floorsCount: 4,
        mappers: 12,
        mappedPercent: 94,
        distanceKm: 0.2,
        category: 'campus',
      ),
    );
    when(() => routes.landmarksOf('b1'))
        .thenAnswer((_) async => [landmark('a'), landmark('b')]);
    when(() => routes.routesOf('b1')).thenAnswer(
      (_) async => [
        route('r1', [('a', 'b')]),
      ],
    );

    final bloc = FloorMapBloc(routes, buildings: buildings);
    bloc.add(const FloorMapRequested('b1'));
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(bloc.state.buildingName, 'KNUST Library');
    await bloc.close();
  });

  test('a building whose name will not load still draws its map', () async {
    final buildings = _MockBuildings();
    when(() => buildings.byId('b1')).thenThrow(Exception('offline'));
    when(() => routes.landmarksOf('b1'))
        .thenAnswer((_) async => [landmark('a'), landmark('b')]);
    when(() => routes.routesOf('b1')).thenAnswer(
      (_) async => [
        route('r1', [('a', 'b')]),
      ],
    );

    final bloc = FloorMapBloc(routes, buildings: buildings);
    bloc.add(const FloorMapRequested('b1'));
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(bloc.state.status, FloorMapStatus.ready);
    expect(bloc.state.buildingName, isNull);
    await bloc.close();
  });

  test('picking two landmarks plans the way between them', () async {
    when(() => routes.landmarksOf('b1')).thenAnswer(
      (_) async => [
        landmark('entrance'),
        landmark('junction'),
        landmark('204', roomId: 'room-204'),
        landmark('209', roomId: 'room-209'),
      ],
    );
    when(() => routes.routesOf('b1')).thenAnswer(
      (_) async => [
        route('r1', [('entrance', 'junction'), ('junction', '204')]),
        route('r2', [('entrance', 'junction'), ('junction', '209')]),
      ],
    );

    final bloc = await loaded();
    bloc.add(const FloorMapFromSelected('204'));
    bloc.add(const FloorMapToSelected('209'));
    await Future<void>.delayed(Duration.zero);

    // Nobody walked 204 → 209; the map answers it anyway.
    expect(bloc.state.plan?.landmarkIds, ['204', 'junction', '209']);
    await bloc.close();
  });

  test('two landmarks with no path between them plan nothing', () async {
    when(() => routes.landmarksOf('b1'))
        .thenAnswer((_) async => [landmark('a'), landmark('x')]);
    when(() => routes.routesOf('b1')).thenAnswer(
      (_) async => [
        route('r1', [('a', 'b')]),
        route('r2', [('x', 'y')]),
      ],
    );

    final bloc = await loaded();
    bloc.add(const FloorMapFromSelected('a'));
    bloc.add(const FloorMapToSelected('y'));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.plan, isNull);
    expect(bloc.state.status, FloorMapStatus.ready);
    await bloc.close();
  });

  test('a failed load is reported, not thrown', () async {
    when(() => routes.landmarksOf('b1')).thenThrow(Exception('offline'));
    when(() => routes.routesOf('b1')).thenAnswer((_) async => []);

    final bloc = await loaded();

    expect(bloc.state.status, FloorMapStatus.failure);
    expect(bloc.state.error, isNotNull);
    await bloc.close();
  });

  test('a retry that succeeds does not keep the failure message', () async {
    // "Try again" after a corridor with no signal: the map arrives, and the
    // message about it being unavailable must not arrive with it.
    var attempts = 0;
    when(() => routes.landmarksOf('b1')).thenAnswer((_) async {
      if (attempts++ == 0) throw Exception('offline');
      return [landmark('a'), landmark('b')];
    });
    when(() => routes.routesOf('b1')).thenAnswer(
      (_) async => [
        route('r1', [('a', 'b')]),
      ],
    );

    final bloc = await loaded();
    expect(bloc.state.error, isNotNull);

    bloc.add(const FloorMapRequested('b1'));
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(bloc.state.status, FloorMapStatus.ready);
    expect(bloc.state.error, isNull);
    await bloc.close();
  });

  group('a building traced off its posted floor plan', () {
    TracedPlan planWithEntrance() => const TracedPlan(
          buildingId: 'b1',
          nodes: [
            TracedNode(
              ref: 'entrance',
              x: 0,
              y: 0,
              floorId: 'f1',
              kind: LandmarkKind.entrance,
              labelText: 'ENTRANCE',
              displayName: 'entrance',
            ),
            TracedNode(
              ref: '204',
              x: 0,
              y: 30,
              floorId: 'f1',
              kind: LandmarkKind.door,
              labelText: '204',
              displayName: '204',
            ),
          ],
          edges: [TracedEdge(fromRef: 'entrance', toRef: '204')],
        );

    test('is drawn from the plan, not from the walks people recorded',
        () async {
      when(() => routes.landmarksOf('b1')).thenAnswer(
        (_) async => [landmark('entrance'), landmark('204')],
      );
      when(() => routes.tracedPlanOf('b1'))
          .thenAnswer((_) async => planWithEntrance());
      // A recorded walk exists too, and disagrees: its turtle layout would put
      // 204 ten metres from the entrance, not thirty.
      when(() => routes.routesOf('b1')).thenAnswer(
        (_) async => [route('r1', [('entrance', '204')])],
      );

      final bloc = await loaded();

      expect(bloc.state.status, FloorMapStatus.ready);
      expect(bloc.state.graph.nodeOf('204')!.y, closeTo(30, 0.001));
      expect(bloc.state.graph.edges.single.distanceM, closeTo(30, 0.001));
      await bloc.close();
    });

    test('opens the "where are you" picker on the entrance', () async {
      when(() => routes.landmarksOf('b1')).thenAnswer(
        (_) async => [
          landmark('204'),
          const Landmark(
            id: 'entrance',
            buildingId: 'b1',
            floorId: 'f1',
            kind: LandmarkKind.entrance,
            labelText: 'ENTRANCE',
            displayName: 'entrance',
          ),
        ],
      );
      when(() => routes.tracedPlanOf('b1'))
          .thenAnswer((_) async => planWithEntrance());
      when(() => routes.routesOf('b1')).thenAnswer((_) async => []);

      final bloc = await loaded();

      // A traced plan has no walking order to take a starting point from.
      expect(bloc.state.fromId, 'entrance');
      await bloc.close();
    });

    test('a plan with no nodes falls back to the recorded walks', () async {
      when(() => routes.landmarksOf('b1')).thenAnswer(
        (_) async => [landmark('entrance'), landmark('204')],
      );
      when(() => routes.tracedPlanOf('b1'))
          .thenAnswer((_) async => TracedPlan.empty);
      when(() => routes.routesOf('b1')).thenAnswer(
        (_) async => [route('r1', [('entrance', '204')])],
      );

      final bloc = await loaded();

      expect(bloc.state.status, FloorMapStatus.ready);
      expect(bloc.state.graph.edges.single.distanceM, closeTo(10, 0.001));
      await bloc.close();
    });
  });
}
