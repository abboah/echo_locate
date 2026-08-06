import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/route_draft.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/data/repository_mixin.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/routing/bloc/floor_plan_bloc.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';

/// A route repository that fails, to exercise the offline path.
class _FailingRouteRepository implements RouteRepository {
  @override
  Future<List<Landmark>> landmarksOf(String buildingId) async =>
      throw const OperationFailure('You appear to be offline');

  @override
  Future<List<WalkRoute>> routesOf(String buildingId) async =>
      throw const OperationFailure('You appear to be offline');

  @override
  Future<WalkRoute?> routeTo(String buildingId, String roomId) async => null;

  @override
  Future<String> saveRoute(RouteDraft draft) async => '';
}

/// A building nobody has walked yet — the normal state of a crowdsourced map.
class _UnmappedRouteRepository implements RouteRepository {
  @override
  Future<List<Landmark>> landmarksOf(String buildingId) async => const [];

  @override
  Future<List<WalkRoute>> routesOf(String buildingId) async => const [];

  @override
  Future<WalkRoute?> routeTo(String buildingId, String roomId) async => null;

  @override
  Future<String> saveRoute(RouteDraft draft) async => '';
}

FloorPlanBloc blocWith(RouteRepository routes) =>
    FloorPlanBloc(routes, MockBuildingRepository());

void main() {
  group('FloorPlanStarted', () {
    test('merges the seeded routes into a plan', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));

      final state = await bloc.stream.firstWhere(
        (s) => s.status == FloorPlanStatus.success,
      );

      expect(state.graph.nodes, hasLength(7));
      expect(state.landmarks, hasLength(7));
      expect(state.emptyReason, FloorPlanEmptyReason.none);
      await bloc.close();
    });

    test('offers only floors that have actually been walked', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));

      final state = await bloc.stream.firstWhere(
        (s) => s.status == FloorPlanStatus.success,
      );

      // The library declares four storeys; two carry landmarks. Offering four
      // tabs would read as a broken map rather than an incomplete one.
      expect(state.floors.map((f) => f.id), ['floor-g', 'floor-2']);
      expect(state.floors.map((f) => f.label), ['G', '2']);
      await bloc.close();
    });

    test('opens on the ground floor when no destination is given', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));

      final state = await bloc.stream.firstWhere(
        (s) => s.status == FloorPlanStatus.success,
      );

      expect(state.activeFloorId, 'floor-g');
      expect(state.visibleNodes.map((n) => n.landmarkId), [
        'lm-entrance',
        'lm-desk',
        'lm-stairs-g',
      ]);
      await bloc.close();
    });

    test('plans a route when opened straight from a room tile', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(
          const FloorPlanStarted(
            'knust-library',
            destinationRoomId: 'reading-hall',
          ),
        );

      final state = await bloc.stream.firstWhere(
        (s) => s.status == FloorPlanStatus.success,
      );

      expect(state.hasRoute, isTrue);
      expect(state.route!.steps, hasLength(5));
      expect(state.currentLandmarkId, 'lm-entrance');
      await bloc.close();
    });

    test('a building nobody has walked is empty, not broken', () async {
      final bloc = blocWith(_UnmappedRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));

      final state = await bloc.stream.firstWhere(
        (s) => s.status != FloorPlanStatus.loading,
      );

      expect(state.status, FloorPlanStatus.success);
      expect(state.emptyReason, FloorPlanEmptyReason.noRoutes);
      expect(state.graph.isEmpty, isTrue);
      await bloc.close();
    });

    test('a repository failure surfaces its message', () async {
      final bloc = blocWith(_FailingRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));

      final state = await bloc.stream.firstWhere(
        (s) => s.status == FloorPlanStatus.failure,
      );

      expect(state.error, 'You appear to be offline');
      // Distinct from "nobody has mapped this": the user can fix one of these.
      expect(state.emptyReason, FloorPlanEmptyReason.none);
      await bloc.close();
    });

    test('reports the worst merge disagreement for the report', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));

      final state = await bloc.stream.firstWhere(
        (s) => s.status == FloorPlanStatus.success,
      );

      // The two seeded routes agree exactly; a real capture will not.
      expect(state.worstSpreadM, closeTo(0, 0.01));
      await bloc.close();
    });
  });

  group('FloorPlanFloorSelected', () {
    test('switches which plane is drawn', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));
      await bloc.stream.firstWhere((s) => s.status == FloorPlanStatus.success);

      bloc.add(const FloorPlanFloorSelected('floor-2'));
      final state = await bloc.stream.firstWhere(
        (s) => s.activeFloorId == 'floor-2',
      );

      expect(state.visibleNodes.map((n) => n.landmarkId), [
        'lm-landing-2',
        'lm-corridor-2',
        'lm-reading-hall',
        'lm-study-2b',
      ]);
      // The stairs leg belongs to neither plane, so floor 2 shows only the
      // three corridors that are actually on it.
      expect(state.visibleEdges, hasLength(3));
      await bloc.close();
    });
  });

  group('FloorPlanDestinationSelected', () {
    test('plans from the entrance and shows the floor it starts on', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));
      await bloc.stream.firstWhere((s) => s.status == FloorPlanStatus.success);

      bloc.add(const FloorPlanDestinationSelected('study-2b'));
      final state = await bloc.stream.firstWhere((s) => s.hasRoute);

      expect(state.route!.startLandmarkId, 'lm-entrance');
      expect(state.activeFloorId, 'floor-g');
      expect(state.currentStep!.instruction, contains('entrance desk'));
      await bloc.close();
    });

    test('replans from where the user is, not the entrance', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(
          const FloorPlanStarted(
            'knust-library',
            destinationRoomId: 'reading-hall',
          ),
        );
      await bloc.stream.firstWhere((s) => s.hasRoute);

      // They walked it: guidance confirmed the Reading Hall door by OCR.
      bloc.add(const FloorPlanPositionChanged('lm-reading-hall'));
      await bloc.stream.firstWhere(
        (s) => s.currentLandmarkId == 'lm-reading-hall',
      );

      // Standing at the Reading Hall door, ask for Study Room 2B: the answer
      // is two legs across floor 2, not a walk back to the front door.
      bloc.add(const FloorPlanDestinationSelected('study-2b'));
      final state = await bloc.stream.firstWhere(
        (s) => s.route?.destinationRoomId == 'study-2b',
      );

      expect(state.route!.steps, hasLength(2));
      expect(state.route!.isPlanned, isTrue);
      expect(state.activeFloorId, 'floor-2');
      await bloc.close();
    });

    test('says so when no walk reaches the room', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));
      await bloc.stream.firstWhere((s) => s.status == FloorPlanStatus.success);

      // Nobody has recorded a landmark at the help desk door.
      bloc.add(const FloorPlanDestinationSelected('help-desk'));
      final state = await bloc.stream.firstWhere(
        (s) => s.emptyReason == FloorPlanEmptyReason.unreachableDestination,
      );

      expect(state.hasRoute, isFalse);
      await bloc.close();
    });
  });

  group('FloorPlanPositionChanged', () {
    test('follows the user onto the floor they climbed to', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));
      await bloc.stream.firstWhere((s) => s.status == FloorPlanStatus.success);
      expect(bloc.state.activeFloorId, 'floor-g');

      bloc.add(const FloorPlanPositionChanged('lm-landing-2'));
      final state = await bloc.stream.firstWhere(
        (s) => s.currentLandmarkId == 'lm-landing-2',
      );

      // Showing the ground floor while they stand on floor 2 is worse than
      // showing nothing.
      expect(state.activeFloorId, 'floor-2');
      await bloc.close();
    });

    test('an unknown landmark does not throw away the current floor', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(const FloorPlanStarted('knust-library'));
      await bloc.stream.firstWhere((s) => s.status == FloorPlanStatus.success);

      bloc.add(const FloorPlanPositionChanged('lm-not-in-this-building'));
      final state = await bloc.stream.first;

      expect(state.activeFloorId, 'floor-g');
      await bloc.close();
    });

    test('walking off the route replans from where the user stands', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(
          const FloorPlanStarted(
            'knust-library',
            destinationRoomId: 'study-2b',
          ),
        );
      await bloc.stream.firstWhere((s) => s.hasRoute);
      expect(bloc.state.route!.steps, hasLength(5));

      // The Reading Hall door is not on the walk to Study Room 2B. Somebody
      // standing there is two legs away, not at the start of a five-leg walk
      // from the front door.
      bloc.add(const FloorPlanPositionChanged('lm-reading-hall'));
      final state = await bloc.stream.firstWhere(
        (s) => s.currentLandmarkId == 'lm-reading-hall',
      );

      expect(state.route!.steps, hasLength(2));
      expect(state.route!.startLandmarkId, 'lm-reading-hall');
      expect(state.route!.destinationRoomId, 'study-2b');
      expect(state.route!.isPlanned, isTrue);
      expect(state.currentStep!.fromLandmarkId, 'lm-reading-hall');
      await bloc.close();
    });

    test('arriving at a landmark on the route keeps the recording', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(
          const FloorPlanStarted(
            'knust-library',
            destinationRoomId: 'study-2b',
          ),
        );
      await bloc.stream.firstWhere((s) => s.hasRoute);

      // Progress along the walk, not a deviation from it: the contributor's
      // recording must survive, verification count and all.
      bloc.add(const FloorPlanPositionChanged('lm-landing-2'));
      final state = await bloc.stream.firstWhere(
        (s) => s.currentLandmarkId == 'lm-landing-2',
      );

      expect(state.route!.id, 'route-study-2b');
      expect(state.route!.isPlanned, isFalse);
      expect(state.route!.steps, hasLength(5));
      expect(state.currentStep!.seq, 4);
      await bloc.close();
    });

    test('says so when nothing connects the new position to the room',
        () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(
          const FloorPlanStarted(
            'knust-library',
            destinationRoomId: 'study-2b',
          ),
        );
      await bloc.stream.firstWhere((s) => s.hasRoute);

      bloc.add(const FloorPlanPositionChanged('lm-not-in-this-building'));
      final state = await bloc.stream.firstWhere(
        (s) => s.emptyReason == FloorPlanEmptyReason.unreachableDestination,
      );

      // Leaving the old route drawn would claim it starts where they are.
      expect(state.hasRoute, isFalse);
      await bloc.close();
    });
  });

  group('FloorPlanRouteCleared', () {
    test('drops the route but keeps the plan on screen', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(
          const FloorPlanStarted(
            'knust-library',
            destinationRoomId: 'reading-hall',
          ),
        );
      await bloc.stream.firstWhere((s) => s.hasRoute);

      bloc.add(const FloorPlanRouteCleared());
      final state = await bloc.stream.firstWhere((s) => !s.hasRoute);

      expect(state.route, isNull);
      expect(state.graph.isEmpty, isFalse);
      await bloc.close();
    });
  });

  group('currentStep', () {
    test('follows the user along the route', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(
          const FloorPlanStarted(
            'knust-library',
            destinationRoomId: 'reading-hall',
          ),
        );
      final state = await bloc.stream.firstWhere((s) => s.hasRoute);

      expect(state.currentStep!.seq, 1);

      final midway = state.copyWith(currentLandmarkId: 'lm-landing-2');
      expect(midway.currentStep!.seq, 4);
      expect(midway.currentStep!.toLandmarkId, 'lm-corridor-2');
      expect(midway.hasArrived, isFalse);
      await bloc.close();
    });

    test('at the destination it reports the last leg, not the first', () async {
      final bloc = blocWith(MockRouteRepository())
        ..add(
          const FloorPlanStarted(
            'knust-library',
            destinationRoomId: 'reading-hall',
          ),
        );
      final state = await bloc.stream.firstWhere((s) => s.hasRoute);

      // No leg *leaves* the final door, so a naive lookup falls back to leg 1
      // and tells somebody who has arrived to start walking again.
      final atDoor = state.copyWith(currentLandmarkId: 'lm-reading-hall');
      expect(atDoor.hasArrived, isTrue);
      expect(atDoor.currentStep!.seq, 5);
      expect(atDoor.currentStep!.toLandmarkId, 'lm-reading-hall');
      await bloc.close();
    });
  });
}
