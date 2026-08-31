import 'package:echo_locate/core/models/building.dart';
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/maps/bloc/maps_bloc.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'room_directions_test.dart' show buildWing;

class _MockBuildings extends Mock implements BuildingRepository {}

class _MockPlans extends Mock implements RoomPlanRepository {}

/// The Maps tab lists what is on the phone, so these all turn on what
/// [RoomPlanRepository.allPlans] returns — and on the tab surviving a building
/// index that cannot be reached, which is the state it exists to be useful in.
void main() {
  late _MockBuildings buildings;
  late _MockPlans plans;

  const knust = Building(
    id: 'knust-cs',
    name: 'College of Science',
    area: 'KNUST, Kumasi',
    floorsCount: 2,
    mappers: 3,
    mappedPercent: 40,
    distanceKm: 0.4,
    category: 'campus',
  );

  RoomPlan planOn(String floorId, {String building = 'knust-cs'}) =>
      buildWing().copyWith(buildingId: building, floorId: floorId);

  setUp(() {
    buildings = _MockBuildings();
    plans = _MockPlans();
    when(() => buildings.byId(any())).thenAnswer((_) async => knust);
    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'gf', label: 'G', rooms: []),
        BuildingFloor(id: 'f1', label: '1', rooms: []),
      ],
    );
  });

  Future<MapsState> loaded() async {
    final bloc = MapsBloc(buildings, plans)..add(const MapsStarted());
    final state = await bloc.stream.firstWhere(
      (state) => state.status != MapsStatus.loading,
    );
    await bloc.close();
    return state;
  }

  test('groups traced floors under the building they belong to', () async {
    when(
      () => plans.allPlans(),
    ).thenAnswer((_) async => [planOn('gf'), planOn('f1')]);

    final state = await loaded();

    expect(state.status, MapsStatus.success);
    expect(state.buildings, hasLength(1));
    expect(state.buildings.single.name, 'College of Science');
    expect(state.buildings.single.floors, hasLength(2));
    expect(state.floorCount, 2);
  });

  test('names floors from the index, and reads the label off the id '
      'when the index cannot be reached', () async {
    when(() => plans.allPlans()).thenAnswer((_) async => [planOn('gf')]);

    final named = await loaded();
    expect(named.buildings.single.floors.single.title, 'Ground floor');

    // The case the tab is for: a phone with the plans and no connection.
    when(() => buildings.floorsOf(any())).thenThrow(Exception('offline'));
    when(() => buildings.byId(any())).thenThrow(Exception('offline'));

    final offline = await loaded();
    expect(offline.status, MapsStatus.success);
    // `gf` is still recognisably the ground floor without the index to say
    // so — it read as "Floor GF" before, which is not a floor anybody has.
    expect(offline.buildings.single.floors.single.label, 'G');
    expect(offline.buildings.single.floors.single.title, 'Ground floor');
    // Falls back to the id rather than showing nothing at all.
    expect(offline.buildings.single.name, 'knust-cs');
  });

  test('a floor record with nothing traced into it is not a map', () async {
    when(() => plans.allPlans()).thenAnswer(
      (_) async => [
        planOn('gf'),
        const RoomPlan(buildingId: 'knust-cs', floorId: 'f1', codePrefix: 'F1'),
      ],
    );

    final state = await loaded();

    expect(state.buildings.single.floors, hasLength(1));
    expect(state.buildings.single.floors.single.plan.floorId, 'gf');
  });

  test('the building with the most traced floors leads the list', () async {
    when(() => buildings.byId('knust-cs')).thenAnswer((_) async => knust);
    when(
      () => buildings.byId('annexe'),
    ).thenAnswer((_) async => knust.copyWith(id: 'annexe', name: 'Annexe'));
    when(() => plans.allPlans()).thenAnswer(
      (_) async => [
        planOn('gf', building: 'annexe'),
        planOn('gf'),
        planOn('f1'),
      ],
    );

    final state = await loaded();

    expect(state.buildings.first.id, 'knust-cs');
    expect(state.buildings.last.id, 'annexe');
  });

  test(
    'nothing traced is a success with an empty list, not a failure',
    () async {
      when(() => plans.allPlans()).thenAnswer((_) async => []);

      final state = await loaded();

      expect(state.status, MapsStatus.success);
      expect(state.buildings, isEmpty);
    },
  );

  test('a store that cannot be read is reported, not thrown', () async {
    when(() => plans.allPlans()).thenThrow(Exception('hive is unhappy'));

    final state = await loaded();

    expect(state.status, MapsStatus.failure);
    expect(state.error, isNotNull);
  });

  test(
    'a floor with rooms and no doors is listed and not offered as a walk',
    () async {
      // Doors are what make a floor routable, and placing them comes after the
      // satisfying part — so this is the most common half-finished state, and it
      // has to be visible rather than silently dropped.
      when(() => plans.allPlans()).thenAnswer(
        (_) async => [planOn('gf').copyWith(storedOpenings: const [])],
      );

      final state = await loaded();

      final floor = state.buildings.single.floors.single;
      expect(floor.isWalkable, isFalse);
      expect(floor.roomCount, greaterThan(0));
    },
  );

  group('deleting a floor', () {
    test('removes it and reloads what is left', () async {
      var deleted = false;
      when(() => plans.delete('knust-cs', 'gf')).thenAnswer((_) async {
        deleted = true;
      });
      when(() => plans.allPlans()).thenAnswer(
        (_) async => deleted ? [planOn('f1')] : [planOn('gf'), planOn('f1')],
      );

      final bloc = MapsBloc(buildings, plans)..add(const MapsStarted());
      await bloc.stream.firstWhere((s) => s.status == MapsStatus.success);

      bloc.add(const MapsFloorDeleted(buildingId: 'knust-cs', floorId: 'gf'));
      final state = await bloc.stream.firstWhere(
        (s) => s.status == MapsStatus.success,
      );

      expect(state.floorCount, 1);
      expect(state.buildings.single.floors.single.plan.floorId, 'f1');
      await bloc.close();
    });

    test('a building whose last floor went disappears with it', () async {
      var deleted = false;
      when(() => plans.delete(any(), any())).thenAnswer((_) async {
        deleted = true;
      });
      when(
        () => plans.allPlans(),
      ).thenAnswer((_) async => deleted ? [] : [planOn('gf')]);

      final bloc = MapsBloc(buildings, plans)..add(const MapsStarted());
      await bloc.stream.firstWhere((s) => s.status == MapsStatus.success);

      bloc.add(const MapsFloorDeleted(buildingId: 'knust-cs', floorId: 'gf'));
      final state = await bloc.stream.firstWhere(
        (s) => s.status == MapsStatus.success,
      );

      // Not an empty building heading with nothing under it.
      expect(state.buildings, isEmpty);
      await bloc.close();
    });

    test('a delete that fails says so and keeps the floor', () async {
      when(() => plans.delete(any(), any())).thenThrow(Exception('locked'));
      when(() => plans.allPlans()).thenAnswer((_) async => [planOn('gf')]);

      final bloc = MapsBloc(buildings, plans)..add(const MapsStarted());
      await bloc.stream.firstWhere((s) => s.status == MapsStatus.success);

      bloc.add(const MapsFloorDeleted(buildingId: 'knust-cs', floorId: 'gf'));
      final state = await bloc.stream.firstWhere((s) => s.error != null);

      // A list that silently does not change reads as a dead button.
      expect(state.error, isNotNull);
      expect(state.floorCount, 1);
      await bloc.close();
    });
  });
}
