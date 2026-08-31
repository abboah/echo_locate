import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
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
  });

  BuildingMappingCubit build() =>
      BuildingMappingCubit(buildings, plans);

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

      expect(find.text('CS Block'), findsOneWidget);
      expect(find.text('Ground floor'), findsOneWidget);
      expect(find.text('Floor 1'), findsOneWidget);
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
}
