import 'package:echo_locate/ui/pages/room_plan/room_plan_probe_page.dart';
import 'package:echo_locate/ui/widgets/room_plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host({Brightness brightness = Brightness.light}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: const RoomPlanProbePage(),
);

void main() {
  testWidgets('renders the sample floor and its generated directions', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(RoomPlanView), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The default route runs the length of the corridor, so it must produce a
    // door-counted instruction — the thing the probe exists to make visible.
    expect(find.textContaining('door on your'), findsOneWidget);
    expect(
      find.textContaining('Corridor door count checks out'),
      findsOneWidget,
    );
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(host(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the destination regenerates the directions', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final before = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lobby').last);
    await tester.pumpAndSettle();

    final after = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    expect(after, isNot(equals(before)));
    expect(tester.takeException(), isNull);
  });
}
