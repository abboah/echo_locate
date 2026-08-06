import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:echo_locate/core/models/building.dart';
import 'package:echo_locate/core/theme/app_theme.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/routing/bloc/floor_plan_bloc.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/injection_container.dart';
import 'package:echo_locate/services/mapping/plan_viewport.dart';
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
      home: NavigationPage(building: _library, destinationRoomId: room),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    getIt.registerFactory<FloorPlanBloc>(
      () => FloorPlanBloc(MockRouteRepository(), MockBuildingRepository()),
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

  testWidgets('opening from a room tile shows that route', (tester) async {
    await tester.pumpWidget(page(AppTheme.light, room: 'reading-hall'));
    await settle(tester);

    // The contributor's own first sentence, spoken verbatim because the user
    // is walking the leg the way it was recorded.
    expect(
      find.text('Straight ahead, past the entrance desk'),
      findsOneWidget,
    );
    expect(find.text('Leg 1 of 5'), findsOneWidget);
    expect(find.textContaining('to go'), findsOneWidget);
  });

  testWidgets('no destination means no instruction card', (tester) async {
    await tester.pumpWidget(page(AppTheme.light));
    await settle(tester);

    expect(find.textContaining('Leg 1 of'), findsNothing);
    expect(find.byType(FloorPlanView), findsOneWidget);
  });

  testWidgets('the floor switcher lists only walked floors', (tester) async {
    await tester.pumpWidget(page(AppTheme.light));
    await settle(tester);

    // Two of the library's four storeys carry landmarks.
    expect(find.text('G'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('tapping a floor redraws that plane', (tester) async {
    await tester.pumpWidget(page(AppTheme.light));
    await settle(tester);
    expect(find.textContaining('Ground floor'), findsOneWidget);

    await tester.tap(find.text('2'));
    await settle(tester);

    expect(find.textContaining('Floor 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recorded route is not badged as estimated', (tester) async {
    await tester.pumpWidget(page(AppTheme.light, room: 'reading-hall'));
    await settle(tester);

    // Somebody walked this one end to end. Calling it an estimate would
    // undersell the only evidence the app has.
    expect(find.textContaining('Estimated route'), findsNothing);
  });

  testWidgets('the demo moment: a room-to-room route nobody walked',
      (tester) async {
    await tester.pumpWidget(page(AppTheme.light, room: 'reading-hall'));
    await settle(tester);

    // Walk it: end up standing at the Reading Hall door on floor 2.
    await tester.tap(find.text('2'));
    await settle(tester);

    final box = tester.renderObject<RenderBox>(find.byType(FloorPlanView));
    final view = tester.widget<FloorPlanView>(find.byType(FloorPlanView));
    final viewport = PlanViewport.fit(
      view.nodes,
      width: box.size.width,
      height: box.size.height,
    );
    final door = view.nodes.firstWhere(
      (n) => n.landmarkId == 'lm-reading-hall',
    );
    await tester.tapAt(
      box.localToGlobal(
        Offset(viewport.toCanvasX(door.x), viewport.toCanvasY(door.y)),
      ),
    );
    await settle(tester);

    // Now ask for Study Room 2B. Nobody has ever walked door to door.
    await tester.tap(find.bySemanticsLabel('Change destination'));
    await settle(tester);

    // The room list is lazily built, so anything below the fold has to be
    // scrolled to before it exists.
    await tester.dragUntilVisible(
      find.text('Study Room 2B'),
      find.byType(ListView),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study Room 2B'));
    await settle(tester);

    // Two legs across floor 2, assembled from the tail of one recording and
    // the reversed tail of another — and honestly badged as an estimate.
    expect(find.text('Leg 1 of 2'), findsOneWidget);
    expect(find.textContaining('Estimated route'), findsOneWidget);
    // Leg 1 leaves the Reading Hall backwards along the corridor, so the
    // recording's "the Reading Hall is the second door on your right" is
    // replaced by a sentence built for the way round being walked. (The
    // recomputed turn at the board is leg 2's, and is asserted in
    // route_planner_test.)
    expect(find.textContaining('directory board'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing the route keeps the plan on screen', (tester) async {
    await tester.pumpWidget(page(AppTheme.light, room: 'reading-hall'));
    await settle(tester);
    expect(find.text('Leg 1 of 5'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Clear route'));
    await settle(tester);

    expect(find.textContaining('Leg 1 of'), findsNothing);
    expect(find.byType(FloorPlanView), findsOneWidget);
  });

  testWidgets('a building with no map says so', (tester) async {
    await getIt.reset();
    getIt.registerFactory<FloorPlanBloc>(
      () => FloorPlanBloc(MockRouteRepository(), MockBuildingRepository()),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: NavigationPage(
          building: Building(
            id: 'great-hall',
            name: 'Great Hall',
            area: 'Campus',
            floorsCount: 2,
            mappers: 0,
            mappedPercent: 0,
            distanceKm: 1.2,
            category: 'campus',
          ),
        ),
      ),
    );
    await settle(tester);

    // Unmapped, not broken — and the copy invites the user to fix it.
    expect(find.textContaining('Nobody has walked'), findsOneWidget);
    expect(find.byType(FloorPlanView), findsNothing);
  });

  group('voice', () {
    testWidgets('is on by default and mutes in one tap', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(page(AppTheme.light, room: 'reading-hall'));
      await settle(tester);

      // On by default: most of this app's audience cannot find a control they
      // have to look for, so guidance starts talking.
      expect(find.semantics.byLabel('Mute spoken directions'), findsOne);

      // Driven through the semantics tree rather than by coordinate, which is
      // the only route a screen-reader user has to it.
      tester.semantics.tap(find.semantics.byLabel('Mute spoken directions'));
      await tester.pump();

      expect(find.semantics.byLabel('Speak directions aloud'), findsOne);
      handle.dispose();
    });

    testWidgets('the instruction card reads as one labelled sentence',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(page(AppTheme.light, room: 'reading-hall'));
      await settle(tester);

      // Same words the voice says, so the two can never drift apart — and one
      // node, not four fragments to swipe through.
      expect(
        find.semantics.byLabel(
          'Straight ahead, past the entrance desk. 12 metres.',
        ),
        findsOne,
      );

      handle.dispose();
    });
  });

  testWidgets('every control on the screen clears the 48dp target minimum',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(page(AppTheme.light, room: 'reading-hall'));
    await settle(tester);

    // WCAG 2.5.5 and Material both put the floor at 48. An app whose users
    // aim by touch alone has the least room of anyone to be under it.
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    // And the labels have to be legible against what is behind them.
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    handle.dispose();
  });
}
