import 'package:echo_locate/core/models/building.dart';
import 'package:echo_locate/core/theme/app_theme.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/maps/bloc/maps_bloc.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/ui/pages/maps/maps_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'room_directions_test.dart' show buildWing;

class _MockBuildings extends Mock implements BuildingRepository {}

class _MockPlans extends Mock implements RoomPlanRepository {}

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

  setUp(() {
    buildings = _MockBuildings();
    plans = _MockPlans();
    when(() => buildings.byId(any())).thenAnswer((_) async => knust);
    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [BuildingFloor(id: 'gf', label: 'G', rooms: [])],
    );
    when(() => plans.allPlans()).thenAnswer((_) async => [buildWing()]);
  });

  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: BlocProvider(
            create: (_) => MapsBloc(buildings, plans)..add(const MapsStarted()),
            child: const MapsView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the traced floor under its building', (tester) async {
    await pump(tester);

    expect(find.text('College of Science'), findsOneWidget);
    expect(find.text('Ground floor'), findsOneWidget);
    // The count line is the evidence that the tab has something in it.
    expect(find.textContaining('1 floor in 1 building'), findsOneWidget);
  });

  testWidgets('an empty tab explains what a plan is and how to get one', (
    tester,
  ) async {
    when(() => plans.allPlans()).thenAnswer((_) async => []);

    await pump(tester);

    expect(find.text('No floor plans yet'), findsOneWidget);
    // Not a bare "nothing here": on a fresh install this is the first place
    // somebody wonders what the tab is for.
    expect(find.text('Map a building'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await pump(tester, theme: AppTheme.dark);

    expect(find.text('Ground floor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives the system font turned all the way up', (tester) async {
    // The setting this app's users are the most likely of anybody to have on.
    // Nothing in `lib/` handled text scaling at all before this pass.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pump(tester, textScaler: const TextScaler.linear(2));

    expect(tester.takeException(), isNull);
    expect(find.text('Ground floor'), findsOneWidget);
  });

  testWidgets('a floor that cannot be walked is listed and says why', (
    tester,
  ) async {
    when(
      () => plans.allPlans(),
    ).thenAnswer((_) async => [buildWing().copyWith(storedOpenings: const [])]);

    await pump(tester);

    expect(find.text('Ground floor'), findsOneWidget);
    expect(find.textContaining('not walkable yet'), findsOneWidget);
    expect(find.text('Needs doors'), findsOneWidget);
  });

  testWidgets('a floor can be deleted, and asks first', (tester) async {
    when(() => plans.delete(any(), any())).thenAnswer((_) async {});

    await pump(tester);

    await tester.tap(find.byTooltip('Delete Ground floor'));
    await tester.pumpAndSettle();

    // Twenty minutes of somebody's work — it confirms rather than acting on
    // the tap, and says what deleting a *published* floor does not do.
    expect(find.text('Delete Ground floor?'), findsOneWidget);
    expect(find.textContaining('other people keep their copy'), findsOneWidget);

    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    verifyNever(() => plans.delete(any(), any()));

    await tester.tap(find.byTooltip('Delete Ground floor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    verify(() => plans.delete('knust-cs', 'gf')).called(1);
  });
}
