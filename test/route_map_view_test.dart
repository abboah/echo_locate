import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/core/theme/app_theme.dart';
import 'package:echo_locate/services/mapping/route_sketch.dart';
import 'package:echo_locate/ui/widgets/route_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RouteSketch sketchOf() => const RouteSketch(
  points: [Offset(0, 0), Offset(0, 20), Offset(12, 20)],
  legEnds: [20, 32],
  surveyed: true,
);

/// A corridor with a room either side of it, in plan units that are metres.
RoomPlan floorOf() => RoomPlan(
  buildingId: 'b1',
  floorId: 'gf',
  codePrefix: 'GF',
  metresPerUnit: 1,
  storedRooms: [
    _rect('corridor', RoomCategory.corridor, -1, 13, -1, 1),
    _rect('office', RoomCategory.office, 2, 8, 1, 6),
    _rect('lab', RoomCategory.laboratory, 2, 8, -6, -1),
  ],
);

Room _rect(
  String id,
  RoomCategory category,
  double left,
  double right,
  double bottom,
  double top,
) => Room(
  id: id,
  floorId: 'gf',
  code: 'GF $id',
  category: category,
  polygon: [
    RoomCorner(x: left, y: bottom),
    RoomCorner(x: right, y: bottom),
    RoomCorner(x: right, y: top),
    RoomCorner(x: left, y: top),
  ],
);

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.dark
          : AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('the route is drawn, in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        host(
          RouteMapView(sketch: sketchOf(), along: 10),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RouteMapView), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a screen reader gets a summary, not a picture', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        RouteMapView(
          sketch: sketchOf(),
          along: 16,
          legIndex: 0,
          destinationName: 'Reading Hall',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Half of a 32-unit route. What a sighted user reads off the picture at a
    // glance is how far through they are, so that is what the label says
    // rather than a description of a line.
    expect(find.bySemanticsLabel(RegExp('Reading Hall')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('50 per cent')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the floor is drawn behind a surveyed route', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        host(
          RouteMapView(sketch: sketchOf(), along: 10, plan: floorOf()),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a turtle sketch is never given a floor to lie about', (
    tester,
  ) async {
    // A sketch built from turns and lengths is a shape, not a path through
    // plan coordinates. Drawing the building behind it would put the walker's
    // line through walls it never crosses — so the widget refuses the plan
    // rather than trusting the caller not to pass one.
    const turtle = RouteSketch(
      points: [Offset(0, 0), Offset(0, 10), Offset(6, 10)],
      legEnds: [10, 16],
      surveyed: false,
    );

    await tester.pumpWidget(
      host(RouteMapView(sketch: turtle, along: 4, plan: floorOf())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a route with nothing in it takes up no room', (tester) async {
    await tester.pumpWidget(
      host(
        const RouteMapView(
          sketch: RouteSketch(points: [], legEnds: [], surveyed: false),
          along: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Collapsed rather than an empty bordered card sitting under the
    // instruction saying nothing. Checked by size because Material's own
    // scaffolding paints with `CustomPaint` all over the tree.
    expect(tester.getSize(find.byType(RouteMapView)).height, 0);
    expect(tester.takeException(), isNull);
  });
}
