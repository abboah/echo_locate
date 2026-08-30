import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/plan_editor/bloc/plan_editor_cubit.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/ui/pages/plan_editor/plan_editor_page.dart';
import 'package:echo_locate/ui/widgets/room_plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'plan_editor_cubit_test.dart' show twoWings;

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockBuildings extends Mock implements BuildingRepository {}

void main() {
  late _MockPlans plans;
  late _MockBuildings buildings;

  setUpAll(() => registerFallbackValue(RoomPlan.empty));

  setUp(() {
    plans = _MockPlans();
    buildings = _MockBuildings();
    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'gf', label: 'G', rooms: []),
        BuildingFloor(id: 'first', label: '1', rooms: []),
      ],
    );
    when(() => plans.save(any())).thenAnswer((_) async {});
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => twoWings());
  });

  Widget host({Brightness brightness = Brightness.light}) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: BlocProvider(
      create: (_) =>
          PlanEditorCubit(plans, buildings)
            ..load(buildingId: 'knust-cs', floorId: 'gf'),
      child: const PlanEditorView(),
    ),
  );

  testWidgets('shows a wing picker and the move controls', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Wing 1'), findsOneWidget);
    expect(find.text('Wing 2'), findsOneWidget);
    expect(find.textContaining('Move Wing 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nudging moves the wing and enables saving', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Save is off until something changes.
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('West'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('offers Square up only when the wing is nearly aligned', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final squareUp = find.widgetWithText(FilledButton, 'Square up');
    // The fixture's second wing is 3 degrees out — within tolerance.
    expect(tester.widget<FilledButton>(squareUp).onPressed, isNotNull);

    // Thirty degrees out is a decision, not a slip.
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byTooltip('Rotate left'));
    }
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(squareUp).onPressed, isNull);
  });

  testWidgets('says lining wings up is not the same as joining them', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // The fixture's two wings have no door between them.
    expect(find.textContaining('cannot be walked to'), findsOneWidget);
    expect(find.textContaining('they need a door'), findsOneWidget);
  });

  testWidgets('an untraced floor says so instead of erroring', (tester) async {
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing has been captured'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(host(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('setting the scale', () {
    /// The state every traced floor is in until somebody measures it.
    void planWithNoScale() {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => twoWings().copyWith(metresPerUnit: null),
      );
    }

    testWidgets('an unscaled floor is called out as a problem', (tester) async {
      planWithNoScale();

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // Nothing else on this screen would reveal it: the plan draws and routes
      // perfectly without a scale.
      expect(find.textContaining('no scale'), findsOneWidget);
      expect(find.text('Set scale'), findsOneWidget);
    });

    testWidgets('a scaled floor says nothing about it', (tester) async {
      await tester.pumpWidget(host()); // twoWings() is metric.
      await tester.pumpAndSettle();

      expect(find.textContaining('no scale'), findsNothing);
    });

    testWidgets('the measure mode opens and takes over the plan', (
      tester,
    ) async {
      planWithNoScale();

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set scale'));
      await tester.pumpAndSettle();

      expect(find.textContaining('the ends of a corridor'), findsOneWidget);
      // The floor actions stand down while a tap means something else.
      expect(find.text('Square up floor'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('two taps on the plan mark a span', (tester) async {
      planWithNoScale();

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set scale'));
      await tester.pumpAndSettle();

      final plan = find.byType(RoomPlanView);
      final box = tester.getRect(plan);
      await tester.tapAt(box.centerLeft + const Offset(20, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('One end placed'), findsOneWidget);

      await tester.tapAt(box.centerRight - const Offset(20, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Both ends placed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the whole flow sets a scale and saves it', (tester) async {
      planWithNoScale();

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set scale'));
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(RoomPlanView));
      await tester.tapAt(box.centerLeft + const Offset(20, 0));
      await tester.pumpAndSettle();
      await tester.tapAt(box.centerRight - const Offset(20, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set distance'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '30');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set scale').last);
      await tester.pumpAndSettle();

      // The warning is gone because the floor now has one, and the mode has
      // closed itself. Save is left enabled rather than pressed: the scale is
      // an edit like any other and rides out with the rest of them, which
      // `plan_editor_cubit_test` checks against the repository.
      expect(find.textContaining('no scale'), findsNothing);
      expect(find.textContaining('the ends of a corridor'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the scale menu is in the app bar in both themes', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(host(brightness: brightness));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Scale'));
        await tester.pumpAndSettle();

        expect(find.textContaining('the scale'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.tapAt(const Offset(5, 5)); // Dismiss.
        await tester.pumpAndSettle();
      }
    });
  });
}
