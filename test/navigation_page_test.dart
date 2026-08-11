import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:echo_locate/core/models/building.dart';
import 'package:echo_locate/core/theme/app_theme.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/routing/bloc/floor_map_bloc.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/injection_container.dart';
import 'package:echo_locate/ui/pages/navigate/navigation_page.dart';
import 'package:echo_locate/ui/widgets/floor_plan_painter.dart';

const _library = Building(
  id: 'knust-library',
  name: 'KNUST Library',
  area: 'Campus',
  floorsCount: 4,
  mappers: 3,
  mappedPercent: 40,
  distanceKm: 0.4,
  category: 'campus',
);

/// Long enough for the mock repositories' latency to elapse on the fake clock.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
}

Widget page(ThemeData theme, {String? room}) => MaterialApp(
      theme: theme,
      home: NavigationPage(
        buildingId: _library.id,
        building: _library,
        destinationRoomId: room,
      ),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    getIt.registerFactory<FloorMapBloc>(
      () => FloorMapBloc(
        MockRouteRepository(),
        buildings: MockBuildingRepository(),
      ),
    );
  });

  tearDownAll(() => getIt.reset());

  testWidgets('shows a spinner, then the plan', (tester) async {
    await tester.pumpWidget(page(AppTheme.light));

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FloorPlanView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in light and dark', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(page(theme, room: 'reading-hall'));
      await settle(tester);

      expect(find.byType(FloorPlanView), findsOneWidget);
      expect(find.text('KNUST Library'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the floor switcher names only the floors that were walked',
      (tester) async {
    await tester.pumpWidget(page(AppTheme.light));
    await settle(tester);

    // Two of the library's four storeys carry landmarks. The other two have
    // nothing to draw, and offering an empty plane reads as a bug.
    expect(find.text('G'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('tapping a floor redraws that plane', (tester) async {
    await tester.pumpWidget(page(AppTheme.light));
    await settle(tester);

    final ground = tester.widget<FloorPlanView>(find.byType(FloorPlanView));
    expect(
      ground.nodes.map((n) => n.landmarkId),
      contains('lm-entrance'),
    );

    await tester.tap(find.text('2'));
    await settle(tester);

    final upstairs = tester.widget<FloorPlanView>(find.byType(FloorPlanView));
    expect(
      upstairs.nodes.map((n) => n.landmarkId),
      contains('lm-reading-hall'),
    );
    expect(
      upstairs.nodes.map((n) => n.landmarkId),
      isNot(contains('lm-entrance')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening from a room tile plans a route to it', (tester) async {
    await tester.pumpWidget(page(AppTheme.light, room: 'reading-hall'));
    await settle(tester);

    final view = tester.widget<FloorPlanView>(find.byType(FloorPlanView));
    final plan = view.route;

    // Arriving by tapping "Reading Hall" should not make the user pick
    // "Reading Hall" again.
    expect(plan, isNotNull);
    expect(plan!.landmarkIds.first, 'lm-entrance');
    expect(plan.landmarkIds.last, 'lm-reading-hall');
  });

  testWidgets('opening cold plans nothing until both ends are picked',
      (tester) async {
    await tester.pumpWidget(page(AppTheme.light));
    await settle(tester);

    final view = tester.widget<FloorPlanView>(find.byType(FloorPlanView));
    expect(view.route, isNull);
    expect(find.byType(FloorPlanView), findsOneWidget);
  });
}
