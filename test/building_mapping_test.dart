import 'package:echo_locate/core/models/building.dart'
    show Building, BuildingFloor;
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/features/building_mapping/bloc/building_mapping_cubit.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/mapping/floor_mapping_status.dart';
import 'package:echo_locate/ui/pages/building_mapping/building_mapping_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockBuildings extends Mock implements BuildingRepository {}

Room rect(String id, {double left = 0, double right = 4}) => Room(
  id: id,
  floorId: 'gf',
  code: id.toUpperCase(),
  category: RoomCategory.office,
  polygon: [
    RoomCorner(x: left, y: 0),
    RoomCorner(x: right, y: 0),
    RoomCorner(x: right, y: 3),
    RoomCorner(x: left, y: 3),
  ],
);

RoomPlan roomsOnly(String floorId) => RoomPlan(
  buildingId: 'knust-cs',
  floorId: floorId,
  codePrefix: 'GF',
  metresPerUnit: 1,
  storedRooms: [rect('a'), rect('b', left: 4, right: 8)],
);

RoomPlan finished(String floorId) => RoomPlan(
  buildingId: 'knust-cs',
  floorId: floorId,
  codePrefix: 'GF',
  metresPerUnit: 1,
  storedRooms: [rect('a'), rect('b', left: 4, right: 8)],
  storedOpenings: const [
    Opening(id: 'd1', roomAId: 'a', roomBId: 'b', at: RoomCorner(x: 4, y: 1)),
  ],
);

void main() {
  late _MockPlans plans;
  late _MockBuildings buildings;

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

  setUp(() {
    plans = _MockPlans();
    buildings = _MockBuildings();

    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'gf', label: 'G', rooms: []),
        BuildingFloor(id: 'f1', label: '1', rooms: []),
      ],
    );
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);
    when(() => buildings.byId(any())).thenAnswer((_) async => knust);
    when(() => buildings.isSaved(any())).thenAnswer((_) async => false);
    when(() => buildings.setSaved(any(), any())).thenAnswer((_) async => true);
  });

  BuildingMappingCubit build() => BuildingMappingCubit(buildings, plans);

  group('loading a building', () {
    test('lists every floor with its state', () async {
      when(
        () => plans.planFor(any(), 'gf'),
      ).thenAnswer((_) async => finished('gf'));

      final cubit = build();
      await cubit.load('knust-cs');

      expect(cubit.state.status, BuildingMappingStatus.ready);
      expect(cubit.state.floors, hasLength(2));
      expect(cubit.state.floors.first.stage, FloorMappingStage.ready);
      expect(cubit.state.floors.last.stage, FloorMappingStage.notStarted);
      await cubit.close();
    });

    test('points at the floor to do next', () async {
      when(
        () => plans.planFor(any(), 'gf'),
      ).thenAnswer((_) async => roomsOnly('gf'));

      final cubit = build();
      await cubit.load('knust-cs');

      // Half-finished beats untouched — that is the one that gets forgotten.
      expect(cubit.state.nextFloor!.floor.id, 'gf');
      expect(cubit.state.nextFloor!.nextActionLabel, 'Add doors');
      await cubit.close();
    });

    test('a floor whose plan will not load counts as unmapped', () async {
      when(() => plans.planFor(any(), 'f1')).thenThrow(Exception('offline'));

      final cubit = build();
      await cubit.load('knust-cs');

      // The rest of the building is still worth showing, and the fix is to
      // map it anyway.
      expect(cubit.state.status, BuildingMappingStatus.ready);
      expect(cubit.state.floors.last.stage, FloorMappingStage.notStarted);
      await cubit.close();
    });

    test('a building that will not load reports rather than hangs', () async {
      when(() => buildings.floorsOf(any())).thenThrow(Exception('offline'));

      final cubit = build();
      await cubit.load('knust-cs');

      expect(cubit.state.status, BuildingMappingStatus.failed);
      expect(cubit.state.error, isNotNull);
      await cubit.close();
    });

    test('a finished building says so', () async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (invocation) async =>
            finished(invocation.positionalArguments[1] as String),
      );

      final cubit = build();
      await cubit.load('knust-cs');

      expect(cubit.state.isComplete, isTrue);
      expect(cubit.state.nextFloor, isNull);
      await cubit.close();
    });
  });

  group('the hub screen', () {
    Widget host({Brightness brightness = Brightness.light}) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: BlocProvider(
        create: (_) => build()..load('knust-cs'),
        child: const BuildingMappingView(buildingName: 'CS Block'),
      ),
    );

    testWidgets('names the building and every floor', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // The **loaded** name wins over the one the route passed in ('CS
      // Block'). That is what makes a rename take effect immediately: the
      // route argument still holds whatever the building was called when the
      // screen was opened, and the header must not keep showing the name the
      // user has just corrected.
      expect(find.text('College of Science'), findsOneWidget);
      expect(find.text('CS Block'), findsNothing);
      expect(find.text('Ground floor'), findsOneWidget);
      expect(find.text('Floor 1'), findsOneWidget);
    });

    testWidgets('falls back to the passed-in name when the index is '
        'unreachable', (tester) async {
      // The floors are on the device and the name is not. Titling the screen
      // 'Building' — or nothing — because a lookup failed would make an
      // offline building look broken rather than merely unnamed.
      when(() => buildings.byId(any())).thenThrow(Exception('offline'));

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('CS Block'), findsOneWidget);
      expect(find.text('Ground floor'), findsOneWidget);
    });

    testWidgets('an unmapped floor offers tracing', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, 'Trace a photo'),
        findsNWidgets(2),
      );
    });

    testWidgets('a half-finished floor gets one primary action', (
      tester,
    ) async {
      when(
        () => plans.planFor(any(), 'gf'),
      ).thenAnswer((_) async => roomsOnly('gf'));

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // Not a menu — a person in a corridor with a phone wants the next step.
      expect(find.widgetWithText(FilledButton, 'Add doors'), findsOneWidget);
      expect(find.text('Needs doors'), findsOneWidget);
      expect(find.textContaining('cannot be walked to'), findsOneWidget);
    });

    testWidgets('says what is left across the whole building', (tester) async {
      when(
        () => plans.planFor(any(), 'gf'),
      ).thenAnswer((_) async => finished('gf'));

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.textContaining('1 of 2 floors ready'), findsOneWidget);
    });

    testWidgets('a finished building says it is done', (tester) async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (invocation) async =>
            finished(invocation.positionalArguments[1] as String),
      );

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.textContaining('ready to navigate'), findsWidgets);
      expect(find.textContaining('Walk a few routes'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(host(brightness: Brightness.dark));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('the building screen', () {
    test('names itself from the index', () async {
      final cubit = build();
      await cubit.load('knust-cs');

      expect(cubit.state.building?.name, 'College of Science');
      await cubit.close();
    });

    test('an index that cannot be read still lists the floors', () async {
      // The floors are on the device. A building screen that refuses to open
      // because the *name* could not be fetched is worse than one titled by
      // whatever it was opened with.
      when(() => buildings.byId(any())).thenThrow(Exception('offline'));

      final cubit = build();
      await cubit.load('knust-cs');

      expect(cubit.state.status, BuildingMappingStatus.ready);
      expect(cubit.state.floors, hasLength(2));
      expect(cubit.state.building, isNull);
      await cubit.close();
    });

    test('the bookmark flips at once and reverts if the write fails', () async {
      when(
        () => buildings.setSaved(any(), any()),
      ).thenThrow(Exception('offline'));

      final cubit = build();
      await cubit.load('knust-cs');
      expect(cubit.state.saved, isFalse);

      await cubit.toggleSaved();

      expect(cubit.state.saved, isFalse, reason: 'reverted after the failure');
      await cubit.close();
    });
  });

  group('renaming', () {
    test('a building can be corrected', () async {
      // The index is crowdsourced: the name is whatever the first contributor
      // typed, which is often a working title.
      when(
        () => buildings.rename(
          any(),
          name: any(named: 'name'),
          area: any(named: 'area'),
        ),
      ).thenAnswer(
        (_) async => knust.copyWith(name: 'College of Science, KNUST'),
      );

      final cubit = build();
      await cubit.load('knust-cs');
      final ok = await cubit.rename(name: 'College of Science, KNUST');

      expect(ok, isTrue);
      expect(cubit.state.building?.name, 'College of Science, KNUST');
      await cubit.close();
    });

    test('an empty name is refused without a round trip', () async {
      final cubit = build();
      await cubit.load('knust-cs');

      final ok = await cubit.rename(name: '   ');

      expect(ok, isFalse);
      expect(cubit.state.error, isNotNull);
      verifyNever(
        () => buildings.rename(
          any(),
          name: any(named: 'name'),
          area: any(named: 'area'),
        ),
      );
      await cubit.close();
    });

    test('a failed rename leaves the old name in place', () async {
      when(
        () => buildings.rename(
          any(),
          name: any(named: 'name'),
          area: any(named: 'area'),
        ),
      ).thenThrow(Exception('denied'));

      final cubit = build();
      await cubit.load('knust-cs');
      final ok = await cubit.rename(name: 'Something else');

      expect(ok, isFalse);
      expect(cubit.state.building?.name, 'College of Science');
      await cubit.close();
    });
  });
}
