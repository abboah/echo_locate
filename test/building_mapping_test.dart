import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/features/building_mapping/bloc/building_mapping_cubit.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/mapping/floor_mapping_status.dart';
import 'package:echo_locate/services/vision/arcore_capture_service.dart';
import 'package:echo_locate/services/vision/depth_frame.dart'
    show ArCoreAvailability;
import 'package:echo_locate/ui/pages/building_mapping/building_mapping_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockBuildings extends Mock implements BuildingRepository {}

class _FakeCapture implements ArCoreCaptureService {
  ArCoreAvailability availability = ArCoreAvailability.unsupported;

  @override
  Future<ArCoreAvailability> checkAvailability() async => availability;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

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
  late _FakeCapture capture;

  setUp(() {
    plans = _MockPlans();
    buildings = _MockBuildings();
    capture = _FakeCapture();

    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'gf', label: 'G', rooms: []),
        BuildingFloor(id: 'f1', label: '1', rooms: []),
      ],
    );
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);
  });

  BuildingMappingCubit build() =>
      BuildingMappingCubit(buildings, plans, capture);

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

    test('knows up front whether this phone can scan', () async {
      capture.availability = ArCoreAvailability.supported;

      final cubit = build();
      await cubit.load('knust-cs');

      // Asked here rather than after somebody has walked to a corridor and
      // opened the scanner.
      expect(cubit.state.canScan, isTrue);
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

    testWidgets('an unmapped floor offers only tracing on a phone that cannot '
        'scan', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, 'Trace a photo'),
        findsNWidgets(2),
      );
      expect(find.widgetWithText(OutlinedButton, 'Scan in AR'), findsNothing);
      expect(
        find.textContaining('not certified for AR scanning'),
        findsOneWidget,
      );
    });

    testWidgets('offers both methods when the phone can scan', (tester) async {
      capture.availability = ArCoreAvailability.supported;

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(OutlinedButton, 'Scan in AR'),
        findsNWidgets(2),
      );
      expect(find.textContaining('not certified'), findsNothing);
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
