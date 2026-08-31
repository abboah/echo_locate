import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/core/theme/app_theme.dart';
import 'package:echo_locate/ui/widgets/room_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Choosing a room to walk to.
///
/// This replaced a `DropdownButtonFormField`, which on a floor with forty
/// rooms opened a floating menu nearly the height of the screen — unsearchable,
/// every name clipped to half a row's width, and close to unusable with a
/// screen reader, which is the audience this screen is for.
Room room(String id, String name, RoomCategory category) => Room(
  id: id,
  floorId: 'gf',
  code: id.toUpperCase(),
  category: category,
  label: name,
  polygon: const [
    RoomCorner(x: 0, y: 0),
    RoomCorner(x: 2, y: 0),
    RoomCorner(x: 2, y: 2),
    RoomCorner(x: 0, y: 2),
  ],
);

void main() {
  final rooms = [
    room('a1', 'Dean of Students', RoomCategory.office),
    room('a2', 'Digital Forensics Lab', RoomCategory.laboratory),
    room('a3', 'Lecture Hall 1', RoomCategory.lectureHall),
    room('a4', 'Lecture Hall 2', RoomCategory.lectureHall),
    room('a5', 'Reading Room', RoomCategory.library),
  ];

  Future<String?> open(
    WidgetTester tester, {
    List<Room>? only,
    String? selectedId,
  }) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await RoomPickerSheet.show(
                  context,
                  title: 'Go to',
                  rooms: only ?? rooms,
                  selectedId: selectedId,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('groups rooms by what they are', (tester) async {
    await open(tester);

    // "The lecture halls" is how somebody asks — not "entry seventeen".
    expect(find.text('LECTURE HALL'), findsOneWidget);
    expect(find.text('OFFICE'), findsOneWidget);
    expect(find.text('Lecture Hall 1'), findsOneWidget);
    expect(find.text('Dean of Students'), findsOneWidget);
  });

  testWidgets('choosing a room returns it', (tester) async {
    await open(tester);

    await tester.tap(find.text('Reading Room'));
    await tester.pumpAndSettle();

    // The sheet is closed and the id came back.
    expect(find.text('Reading Room'), findsNothing);
  });

  testWidgets('a long floor can be searched', (tester) async {
    final many = [
      for (var i = 0; i < 20; i++) room('r$i', 'Room $i', RoomCategory.office),
      room('lab', 'Digital Forensics Lab', RoomCategory.laboratory),
    ];

    await open(tester, only: many);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'forensics');
    await tester.pumpAndSettle();

    expect(find.text('Digital Forensics Lab'), findsOneWidget);
    expect(find.text('Room 0'), findsNothing);
  });

  testWidgets('a short floor is not given a search box it does not need', (
    tester,
  ) async {
    await open(tester, only: rooms.take(3).toList());

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a search matching nothing says so', (tester) async {
    final many = [
      for (var i = 0; i < 20; i++) room('r$i', 'Room $i', RoomCategory.office),
    ];

    await open(tester, only: many);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('No room matches'), findsOneWidget);
  });

  testWidgets('the current choice is marked', (tester) async {
    await open(tester, selectedId: 'a3');
    await tester.pumpAndSettle();

    // Exactly one row carries the tick, and it is the chosen one. A dropdown
    // could not show this at all — the current value was only visible once the
    // menu was closed.
    final ticks = find.descendant(
      of: find.byType(RoomPickerSheet),
      matching: find.byIcon(PhosphorIconsFill.checkCircle),
    );
    expect(ticks, findsOneWidget);
    expect(find.ancestor(of: ticks, matching: find.byType(Row)), findsWidgets);
    expect(find.text('Lecture Hall 1'), findsOneWidget);
  });

  testWidgets('renders in dark mode at a large system font', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    RoomPickerSheet.show(context, title: 'Go to', rooms: rooms),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
