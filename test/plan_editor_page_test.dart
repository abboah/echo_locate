import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/plan_editor/bloc/plan_editor_cubit.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/ui/pages/plan_editor/plan_editor_page.dart';
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
}
