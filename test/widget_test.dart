import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/app.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const App());

    // Verify that app loads with EchoLocate title
    expect(find.text('EchoLocate'), findsOneWidget);
  });
}
