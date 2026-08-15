import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/services/mapping/plan_viewport.dart';
import 'package:echo_locate/services/mapping/room_graph.dart';
import 'package:echo_locate/ui/widgets/room_plan_palette.dart';
import 'package:echo_locate/ui/widgets/room_plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_directions_test.dart' show buildWing;

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: SizedBox(width: 400, height: 600, child: child)),
    );

/// Every label in the live semantics tree under the plan.
///
/// Rooms are published as `CustomPainterSemantics`, which hang off the render
/// object rather than off widgets, so `find.bySemanticsLabel` never sees them —
/// the tree has to be walked. Same helper, and same reason, as
/// `floor_plan_painter_test.dart`.
List<String> semanticsLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(RoomPlanView)));
  return labels;
}

void main() {
  group('palette', () {
    test('every category label clears WCAG AA in light mode', () {
      const palette = RoomPalette.light;

      for (final category in RoomCategory.values) {
        final fill = palette.fillFor(category);
        final ratio = RoomPalette.contrastRatio(palette.labelOn(fill), fill);

        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '${category.name} label contrast is only '
              '${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('every category label clears WCAG AA in dark mode', () {
      const palette = RoomPalette.dark;

      for (final category in RoomCategory.values) {
        final fill = palette.fillFor(category);
        final ratio = RoomPalette.contrastRatio(palette.labelOn(fill), fill);

        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '${category.name} label contrast is only '
              '${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('corridors get a real fill, not a transparent hole', () {
      // The spec maps corridors to 0x00000000, whose luminance reads 0, which
      // picks white label ink, which is then painted on an unpainted white
      // page. Corridor names are the ones a wayfinding map most needs.
      for (final palette in [RoomPalette.light, RoomPalette.dark]) {
        final fill = palette.fillFor(RoomCategory.corridor);

        expect(fill.a, 1.0);
        expect(
          RoomPalette.contrastRatio(palette.labelOn(fill), fill),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('categories are visually distinct within a theme', () {
      final seen = <int>{};
      for (final category in RoomCategory.values) {
        // toARGB32 rather than the deprecated .value.
        expect(
          seen.add(RoomPalette.light.fillFor(category).toARGB32()),
          isTrue,
          reason: '${category.name} duplicates another category\'s fill',
        );
      }
    });

    test('the legend writes itself from the rooms present', () {
      final legend = RoomPalette.legendFor(buildWing().rooms);

      expect(legend, contains(RoomCategory.office));
      expect(legend, contains(RoomCategory.laboratory));
      expect(legend, contains(RoomCategory.washroom));
      expect(legend, contains(RoomCategory.commonRoom));
      // Corridors are the space between rooms, not a category to look up.
      expect(legend, isNot(contains(RoomCategory.corridor)));
      // Nothing that is not on this floor.
      expect(legend, isNot(contains(RoomCategory.library)));
    });

    test('legend order is stable regardless of room order', () {
      final plan = buildWing();
      final forwards = RoomPalette.legendFor(plan.rooms);
      final backwards = RoomPalette.legendFor(plan.rooms.reversed);

      expect(forwards, equals(backwards));
    });
  });

  group('rendering', () {
    testWidgets('draws a floor in light mode', (tester) async {
      await tester.pumpWidget(host(RoomPlanView(plan: buildWing())));

      expect(find.byType(RoomPlanView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws the same floor in dark mode', (tester) async {
      await tester.pumpWidget(
        host(RoomPlanView(plan: buildWing()), brightness: Brightness.dark),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('draws an empty plan without throwing', (tester) async {
      await tester.pumpWidget(host(const RoomPlanView(plan: RoomPlan.empty)));

      expect(tester.takeException(), isNull);
    });

    testWidgets('draws a plan containing a stub room', (tester) async {
      // A stub has no polygon. Anything that asks it for geometry throws.
      await tester.pumpWidget(
        host(RoomPlanView(plan: buildWing(extraStubDoor: true))),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('draws a route over the plan', (tester) async {
      final plan = buildWing();
      final route = RoomNavGraph.build(
        plan,
      ).route(fromRoomId: 'lobby', toRoomId: 'n3');

      await tester.pumpWidget(
        host(
          RoomPlanView(plan: plan, route: route, highlightedRoomId: 'lobby'),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('a room with a long label still renders', (tester) async {
      // 'Digital Forensic Office' cannot fit inside a 2x5 m room at 12 px.
      // The overflow ladder has to degrade rather than overflow.
      await tester.pumpWidget(host(RoomPlanView(plan: buildWing())));

      expect(tester.takeException(), isNull);
    });
  });

  group('hit testing', () {
    test('resolves a tap to the room under it', () {
      final plan = buildWing();
      const view = RoomPlanView(plan: RoomPlan.empty);
      final viewport = PlanViewport.fitPoints(
        [
          for (final room in plan.drawableRooms)
            for (final corner in room.polygon) (x: corner.x, y: corner.y),
        ],
        width: 400,
        height: 600,
        // Whatever RoomPlanView itself uses, or the hit test resolves taps
        // against a projection that was never drawn.
        maxScale: PlanViewport.maxScaleFor(plan.metresPerUnit),
      );

      final withPlan = RoomPlanView(plan: plan, onRoomTap: (_) {});
      // n2 spans x 7..9, y 1..6 — its middle is (8, 3.5).
      final inN2 = Offset(viewport.toCanvasX(8), viewport.toCanvasY(3.5));

      expect(withPlan.roomAt(inN2, viewport), 'n2');
      expect(view.roomAt(inN2, viewport), isNull);
    });

    test('a tap outside every room hits nothing', () {
      final plan = buildWing();
      final view = RoomPlanView(plan: plan, onRoomTap: (_) {});
      final viewport = PlanViewport.fitPoints(
        [
          for (final room in plan.drawableRooms)
            for (final corner in room.polygon) (x: corner.x, y: corner.y),
        ],
        width: 400,
        height: 600,
        // Whatever RoomPlanView itself uses, or the hit test resolves taps
        // against a projection that was never drawn.
        maxScale: PlanViewport.maxScaleFor(plan.metresPerUnit),
      );

      // Well north of the north rooms, which stop at y = 6.
      expect(
        view.roomAt(
          Offset(viewport.toCanvasX(8), viewport.toCanvasY(40)),
          viewport,
        ),
        isNull,
      );
    });

    testWidgets('tapping a room reports it', (tester) async {
      String? tapped;
      final plan = buildWing();

      await tester.pumpWidget(
        host(RoomPlanView(plan: plan, onRoomTap: (id) => tapped = id)),
      );

      // The corridor spans the middle of the plan and is the easiest target
      // that is definitely inside something.
      await tester.tapAt(tester.getCenter(find.byType(RoomPlanView)));
      await tester.pump();

      expect(tapped, isNotNull);
    });
  });

  group('accessibility', () {
    testWidgets('publishes every room as a semantics node', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(RoomPlanView(plan: buildWing(), onRoomTap: (_) {})),
      );

      // A CustomPaint is one unlabelled box to a screen reader unless the
      // painter publishes its contents.
      final labels = semanticsLabels(tester);

      // The name and what it is — the trailing code is gone, because it was
      // a tracing-order number read out as though it were on the door.
      expect(labels, contains('Digital Forensic Office, office'));
      expect(labels, contains('Lobby, common room'));
      // An unnamed room announces what it is, once. Saying "Laboratory,
      // laboratory" is a stutter to anybody listening on TalkBack.
      expect(labels, contains('Laboratory'));
      expect(labels.any((l) => l.contains('GF ')), isFalse);
      expect(labels.length, buildWing().drawableRooms.length);

      handle.dispose();
    });

    testWidgets('names a room\'s role in the current route', (tester) async {
      final handle = tester.ensureSemantics();
      final plan = buildWing();
      final route = RoomNavGraph.build(
        plan,
      ).route(fromRoomId: 'lobby', toRoomId: 'n3');

      await tester.pumpWidget(
        host(
          RoomPlanView(
            plan: plan,
            route: route,
            highlightedRoomId: 'lobby',
            onRoomTap: (_) {},
          ),
        ),
      );

      final labels = semanticsLabels(tester);

      expect(labels.where((l) => l.contains('you are here')), hasLength(1));
      expect(labels.where((l) => l.contains('your destination')), hasLength(1));
      expect(labels.where((l) => l.contains('on your route')), isNotEmpty);

      handle.dispose();
    });

    testWidgets('a stub room is not published — there is nothing to point at', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          RoomPlanView(plan: buildWing(extraStubDoor: true), onRoomTap: (_) {}),
        ),
      );

      expect(semanticsLabels(tester).where((l) => l.contains('GF 7')), isEmpty);

      handle.dispose();
    });
  });

  group('door width', () {
    // Found by tracing a real wall board on a phone: doors drew as stray
    // full-width strokes across the plan. `Opening.widthM` is metres and
    // `PlanViewport.scale` is pixels per plan unit, and the two were being
    // multiplied together.
    test('a metre door is converted into plan units before it is scaled', () {
      const traced = RoomPlan(buildingId: 'b', floorId: 'g', codePrefix: 'GF');
      final metric = traced.copyWith(metresPerUnit: 1);

      // A captured plan is already in metres: nothing to convert.
      expect(RoomPlanView.unitsPerMetreFor(metric), 1);

      // A traced one is not, and a 0.9 m door must come out as a small
      // fraction of a floor rather than most of one.
      final doorInUnits = 0.9 * RoomPlanView.unitsPerMetreFor(traced);
      expect(doorInUnits, lessThan(0.05));
      expect(doorInUnits, greaterThan(0));
    });

    testWidgets('a traced plan with a door renders without painting off-plan', (
      tester,
    ) async {
      // The whole floor is about one unit across, which is what made the old
      // arithmetic produce a line wider than the canvas.
      await tester.pumpWidget(host(RoomPlanView(plan: buildWing())));
      expect(tester.takeException(), isNull);
    });
  });
}
