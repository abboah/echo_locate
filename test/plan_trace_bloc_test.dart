import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/traced_plan.dart';
import 'package:echo_locate/data/repository_mixin.dart';
import 'package:echo_locate/core/models/building.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/plan_trace/bloc/plan_trace_bloc.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:echo_locate/services/mapping/plan_photo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRoutes extends Mock implements RouteRepository {}

class _MockPhotos extends Mock implements PlanPhotoService {}

class _MockBuildings extends Mock implements BuildingRepository {}

void main() {
  late _MockRoutes routes;
  late _MockPhotos photos;
  late _MockBuildings buildings;

  setUpAll(() => registerFallbackValue(TracedPlan.empty));

  setUp(() {
    routes = _MockRoutes();
    photos = _MockPhotos();
    buildings = _MockBuildings();
    // The building's real floors: a traced node stores a `floors.id`, so these
    // are what the trace is filed under.
    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'floor-uuid-g', label: 'G', rooms: []),
        BuildingFloor(id: 'floor-uuid-2', label: '2', rooms: []),
      ],
    );
    when(() => photos.start()).thenAnswer((_) async => true);
    when(() => photos.stop()).thenAnswer((_) async {});
    when(() => photos.capture()).thenAnswer((_) async => '/tmp/plan.jpg');
    when(() => routes.saveTracedPlan(any()))
        .thenAnswer((_) async => TracedPlan.empty);
  });

  Future<void> pump() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// A bloc past the photo step, tracing on a blank grid.
  Future<PlanTraceBloc> tracing() async {
    final bloc = PlanTraceBloc(routes, photos, buildings);
    bloc.add(const PlanTraceStarted('b1'));
    await pump();
    bloc.add(const PlanPhotoSkipped());
    await pump();
    return bloc;
  }

  void place(PlanTraceBloc bloc, String name, double u, double v) => bloc.add(
        PlanNodeAdded(
          u: u,
          v: v,
          kind: LandmarkKind.door,
          labelText: name.toUpperCase(),
          displayName: name,
        ),
      );

  group('getting a plan on screen', () {
    test('a camera that will not open still lets the plan be traced', () async {
      when(() => photos.start()).thenAnswer((_) async => false);
      final bloc = PlanTraceBloc(routes, photos, buildings);

      bloc.add(const PlanTraceStarted('b1'));
      await pump();

      // The photo is a backdrop to tap against; the graph is the taps. A dead
      // camera must not take the whole feature down with it.
      expect(bloc.state.cameraReady, isFalse);
      expect(bloc.state.stage, PlanTraceStage.photo);
      await bloc.close();
    });

    test('taking the photo goes straight to tracing — nothing to measure first',
        () async {
      final bloc = PlanTraceBloc(routes, photos, buildings);
      bloc.add(const PlanTraceStarted('b1'));
      await pump();

      bloc.add(const PlanPhotoTaken());
      await pump();

      expect(bloc.state.photoPath, '/tmp/plan.jpg');
      expect(bloc.state.stage, PlanTraceStage.trace);
      await bloc.close();
    });

    test('re-shooting the plan keeps the points already placed', () async {
      final bloc = await tracing();
      place(bloc, '204', 0.5, 0.5);
      await pump();

      bloc.add(const PlanPhotoRetaken());
      await pump();

      // Re-shooting is about a bad angle, not a wrong trace.
      expect(bloc.state.points, hasLength(1));
      expect(bloc.state.stage, PlanTraceStage.photo);
      await bloc.close();
    });
  });

  group('nobody is asked to measure anything', () {
    test('a plan with one landmark on it is savable', () async {
      final bloc = await tracing();
      place(bloc, 'entrance', 0.2, 0.2);
      await pump();

      // No scale, no distance, no calibration: a landmark the camera can
      // confirm is already a usable map.
      expect(bloc.state.canSave, isTrue);
      await bloc.close();
    });

    test('the saved plan is unitless', () async {
      final bloc = await tracing();
      place(bloc, 'a', 0, 0);
      place(bloc, 'b', 0.3, 0);
      await pump();

      expect(bloc.toPlan().metresPerUnit, isNull);
      await bloc.close();
    });

    test('an unmeasured plan still routes, but is not spoken in steps',
        () async {
      final bloc = await tracing();
      place(bloc, 'a', 0, 0);
      place(bloc, 'b', 0.3, 0);
      place(bloc, 'c', 0.9, 0);
      await pump();

      final graph = FloorGraph.fromPlan(bloc.toPlan());

      // A* compares edges with each other, so relative lengths are all it
      // needs: the short corridor is still shorter than the long one.
      expect(graph.metric, isFalse);
      expect(graph.edges.first.distanceM,
          lessThan(graph.edges.last.distanceM));
      await bloc.close();
    });
  });

  group('tracing corridors', () {
    test('each new point joins the one before it', () async {
      final bloc = await tracing();

      place(bloc, 'entrance', 0, 0);
      place(bloc, 'junction', 0, 0.2);
      place(bloc, '204', 0.2, 0.2);
      await pump();

      // Tap, tap, tap draws a corridor — not three loose points needing to be
      // joined up afterwards.
      expect(bloc.state.points, hasLength(3));
      expect(bloc.state.links, hasLength(2));
      await bloc.close();
    });

    test('tapping two placed points joins them, and again unjoins them',
        () async {
      final bloc = await tracing();
      place(bloc, 'a', 0, 0);
      await pump();
      // Placing with nothing selected leaves the two points unjoined, so this
      // exercises the join rather than the auto-join.
      bloc.add(const PlanSelectionCleared());
      await pump();
      place(bloc, 'b', 0.5, 0);
      bloc.add(const PlanSelectionCleared());
      await pump();
      final a = bloc.state.points.first.ref;
      final b = bloc.state.points.last.ref;
      expect(bloc.state.linked(a, b), isFalse);

      // First tap selects, second joins.
      bloc.add(PlanNodeTapped(a));
      bloc.add(PlanNodeTapped(b));
      await pump();
      expect(bloc.state.linked(a, b), isTrue);

      // The same gesture undoes it: a mis-drawn corridor comes out the way it
      // went in.
      bloc.add(PlanNodeTapped(a));
      await pump();
      expect(bloc.state.linked(a, b), isFalse);
      await bloc.close();
    });

    test('removing a point takes its corridors with it', () async {
      final bloc = await tracing();
      place(bloc, 'a', 0, 0);
      place(bloc, 'b', 0.5, 0);
      place(bloc, 'c', 1, 0);
      await pump();
      final b = bloc.state.points[1].ref;

      bloc.add(PlanNodeRemoved(b));
      await pump();

      // A leftover edge would name a node that is not there — the unroutable
      // node FloorGraph.fromPlan has to defend against.
      expect(bloc.state.points, hasLength(2));
      expect(bloc.state.links, isEmpty);
      await bloc.close();
    });

    test('a tap near a placed point hits it rather than asking for a new one',
        () async {
      final bloc = await tracing();
      place(bloc, 'a', 0.5, 0.5);
      await pump();

      expect(bloc.pointAt(0.51, 0.51)?.displayName, 'a');
      expect(bloc.pointAt(0.9, 0.9), isNull);
      await bloc.close();
    });
  });

  group('what gets saved', () {
    test('an edge is as long as the gap it was drawn across', () async {
      final bloc = await tracing();
      place(bloc, 'a', 0, 0);
      place(bloc, 'b', 0.3, 0);
      await pump();

      final graph = FloorGraph.fromPlan(bloc.toPlan());

      expect(graph.edges.single.distanceM, closeTo(0.3, 0.001));
      await bloc.close();
    });

    test('the plan is not saved mirrored', () async {
      final bloc = await tracing();
      place(bloc, 'top', 0, 0);
      place(bloc, 'below', 0, 0.5);
      await pump();

      final plan = bloc.toPlan();

      // Screen v grows downwards and map y grows north. Without the flip every
      // traced building would come out mirrored, and a route drawn correctly
      // would be spoken as its own mirror image.
      expect(plan.nodes.first.y, closeTo(0, 0.001));
      expect(plan.nodes.last.y, closeTo(-0.5, 0.001));
      await bloc.close();
    });

    test('nodes are filed under the building\'s real floor id', () async {
      final bloc = await tracing();

      // Defaulted from the building's floors, not invented by the screen: the
      // server casts this to a uuid, so a made-up label would be rejected only
      // after the whole floor had been traced.
      expect(bloc.state.floorId, 'floor-uuid-g');

      bloc.add(const PlanFloorChanged('floor-uuid-2'));
      await pump();
      place(bloc, 'landing', 0.1, 0.1);
      await pump();

      expect(bloc.toPlan().nodes.single.floorId, 'floor-uuid-2');
      await bloc.close();
    });

    test('saving an untraced plan is refused', () async {
      final bloc = await tracing();

      bloc.add(const PlanTraceSaved());
      await pump();

      expect(bloc.state.error, isNotNull);
      verifyNever(() => routes.saveTracedPlan(any()));
      await bloc.close();
    });

    test('a traced plan reaches the repository', () async {
      final bloc = await tracing();
      place(bloc, 'entrance', 0, 0);
      place(bloc, '204', 0, 0.3);
      await pump();

      bloc.add(const PlanTraceSaved());
      await pump();

      expect(bloc.state.stage, PlanTraceStage.saved);
      final saved = verify(() => routes.saveTracedPlan(captureAny()))
          .captured
          .single as TracedPlan;
      expect(saved.buildingId, 'b1');
      expect(saved.nodes, hasLength(2));
      expect(saved.edges, hasLength(1));
      await bloc.close();
    });

    test('a failed save says so and leaves the trace intact', () async {
      when(() => routes.saveTracedPlan(any()))
          .thenThrow(const OperationFailure('Could not connect.'));
      final bloc = await tracing();
      place(bloc, 'a', 0, 0);
      await pump();

      bloc.add(const PlanTraceSaved());
      await pump();

      // Losing an hour of tracing to a dropped connection would be its own bug.
      expect(bloc.state.stage, PlanTraceStage.trace);
      expect(bloc.state.error, 'Could not connect.');
      expect(bloc.state.points, hasLength(1));
      await bloc.close();
    });
  });
}
