import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/injection_container.dart';
import 'package:echo_locate/ui/pages/evaluation/plan_evaluation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'room_directions_test.dart' show buildWing;

class _MockPlans extends Mock implements RoomPlanRepository {}

void main() {
  late _MockPlans plans;

  setUp(() {
    plans = _MockPlans();
    // The page resolves its repository from GetIt, the way every other screen
    // in the app does.
    if (getIt.isRegistered<RoomPlanRepository>()) {
      getIt.unregister<RoomPlanRepository>();
    }
    getIt.registerSingleton<RoomPlanRepository>(plans);
  });

  tearDown(() => getIt.unregister<RoomPlanRepository>());

  Widget host({Brightness brightness = Brightness.light}) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: const PlanEvaluationPage(buildingId: 'knust-cs', floorId: 'gf'),
  );

  testWidgets('says so when the floor has not been traced', (tester) async {
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.textContaining('No traced plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refuses to show a figure before ground truth is typed in', (
    tester,
  ) async {
    when(
      () => plans.planFor(any(), any()),
    ).thenAnswer((_) async => buildWing());

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // The distinction that matters most on this screen: "not measured" is not
    // the same claim as "measured as zero", and only one is honest to print.
    expect(find.textContaining('Not measured'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('measures once the board has been copied in', (tester) async {
    when(
      () => plans.planFor(any(), any()),
    ).thenAnswer((_) async => buildWing());

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'GF 0, Lobby\n'
      'GF 0, GF 2\n'
      'GF 0, Digital Forensic Office\n'
      'GF 0, GF 4\n'
      'GF 0, GF 5\n'
      'GF 0, GF 6\n',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Measure'));
    await tester.pumpAndSettle();

    expect(find.text('100.0%'), findsNWidgets(3));
    expect(find.textContaining('Not measured'), findsNothing);
  });

  testWidgets('names the door the plan is missing', (tester) async {
    when(
      () => plans.planFor(any(), any()),
    ).thenAnswer((_) async => buildWing());

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'GF 0, Lobby\nGF 0, GF 2\nGF 0, Nowhere Room\n',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Measure'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Missing from the plan'), findsOneWidget);
    expect(find.textContaining('NOWHERE ROOM'), findsOneWidget);
  });

  testWidgets('lists routes to walk with their spoken instructions', (
    tester,
  ) async {
    when(
      () => plans.planFor(any(), any()),
    ).thenAnswer((_) async => buildWing());

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.textContaining('Routes to walk'), findsOneWidget);

    // Expanding a route shows exactly what would be spoken — the sentences
    // being audited.
    await tester.tap(find.textContaining('1. ').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('·'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark mode', (tester) async {
    when(
      () => plans.planFor(any(), any()),
    ).thenAnswer((_) async => buildWing());

    await tester.pumpWidget(host(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
