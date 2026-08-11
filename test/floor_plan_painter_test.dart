import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:echo_locate/services/mapping/plan_viewport.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';
import 'package:echo_locate/ui/widgets/floor_plan_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seeded KNUST Library walk: entrance → desk → stairs → landing → hall.
WalkRoute seededRoute() => const WalkRoute(
      id: 'route-reading-hall',
      buildingId: 'knust-library',
      startLandmarkId: 'lm-entrance',
      destinationRoomId: 'reading-hall',
      steps: [
        RouteStep(
          seq: 1,
          fromLandmarkId: 'lm-entrance',
          toLandmarkId: 'lm-desk',
          instruction: 'Straight ahead, past the entrance desk',
          distanceM: 12,
        ),
        RouteStep(
          seq: 2,
          fromLandmarkId: 'lm-desk',
          toLandmarkId: 'lm-stairs-g',
          instruction: 'Turn right; the stairwell is at the end',
          distanceM: 18,
          turnDeg: 90,
        ),
        RouteStep(
          seq: 3,
          fromLandmarkId: 'lm-stairs-g',
          toLandmarkId: 'lm-landing-2',
          instruction: 'Take the stairs up two flights',
          distanceM: 8,
        ),
        RouteStep(
          seq: 4,
          fromLandmarkId: 'lm-landing-2',
          toLandmarkId: 'lm-reading-hall',
          instruction: 'Turn left; third door on your right',
          distanceM: 15,
          turnDeg: -90,
        ),
      ],
    );

Map<String, Landmark> seededLandmarks() => {
      for (final entry in {
        'lm-entrance': ('Main entrance', LandmarkKind.entrance, 'floor-g'),
        'lm-desk': ('Help desk', LandmarkKind.junction, 'floor-g'),
        'lm-stairs-g': (
          'Ground floor stairwell',
          LandmarkKind.stairs,
          'floor-g',
        ),
        'lm-landing-2': ('Floor 2 landing', LandmarkKind.stairs, 'floor-2'),
        'lm-reading-hall': ('Reading Hall door', LandmarkKind.door, 'floor-2'),
      }.entries)
        entry.key: Landmark(
          id: entry.key,
          buildingId: 'knust-library',
          floorId: entry.value.$3,
          kind: entry.value.$2,
          labelText: entry.value.$1.toUpperCase(),
          displayName: entry.value.$1,
        ),
    };

Widget harness(Widget child, Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SizedBox(width: 360, height: 500, child: child),
      ),
    );

/// The view over one floor of [graph], the way the map screen builds it.
FloorPlanView viewOf(
  FloorGraph graph, {
  String floorId = 'floor-g',
  PlannedRoute? route,
  ValueChanged<String>? onLandmarkTap,
  String? currentLandmarkId,
}) =>
    FloorPlanView(
      nodes: graph.nodesOn(floorId).toList(),
      edges: graph.edgesOn(floorId).toList(),
      landmarks: seededLandmarks(),
      route: route,
      onLandmarkTap: onLandmarkTap,
      currentLandmarkId: currentLandmarkId,
    );

/// Every label in the live semantics tree.
///
/// The plan's landmarks are published by the painter as `CustomPainterSemantics`
/// rather than as widgets, so they hang off the render object and `find` never
/// sees them — the tree has to be walked directly.
List<String> semanticsLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(FloorPlanView)));
  return labels;
}

void main() {
  test('the merge splits the walk across the floors its landmarks are on', () {
    final graph = FloorGraph.merge([seededRoute()], seededLandmarks());

    expect(graph.floorIds, {'floor-g', 'floor-2'});
    expect(
      graph.nodesOn('floor-g').map((n) => n.landmarkId),
      containsAll(['lm-entrance', 'lm-desk', 'lm-stairs-g']),
    );
    expect(
      graph.nodesOn('floor-2').map((n) => n.landmarkId),
      containsAll(['lm-landing-2', 'lm-reading-hall']),
    );

    // The stairs leg has one end on each floor, so it belongs to neither
    // plane — drawing it would imply a corridor that is not there.
    final crossing = graph.edges.where(
      (e) => e.connects('lm-stairs-g', 'lm-landing-2'),
    );
    expect(crossing, hasLength(1));
    expect(graph.edgesOn('floor-g').contains(crossing.first), isFalse);
    expect(graph.edgesOn('floor-2').contains(crossing.first), isFalse);
  });

  testWidgets('the seeded route draws in light and dark', (tester) async {
    final graph = FloorGraph.merge([seededRoute()], seededLandmarks());
    final route = PlannedRoute.fromRecorded(seededRoute());

    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        harness(viewOf(graph, route: route), brightness),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an empty building paints nothing rather than crashing',
      (tester) async {
    await tester.pumpWidget(
      harness(viewOf(FloorGraph.empty), Brightness.light),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a single-corridor building with no width still fits',
      (tester) async {
    // Every landmark on one straight line: the vertical span is zero, which is
    // where a fit-to-canvas scale divides by nothing.
    final graph = FloorGraph.merge(
      [
        const WalkRoute(
          id: 'straight',
          buildingId: 'b1',
          startLandmarkId: 'lm-entrance',
          destinationRoomId: 'r',
          steps: [
            RouteStep(
              seq: 1,
              fromLandmarkId: 'lm-entrance',
              toLandmarkId: 'lm-desk',
              instruction: 'straight on',
              distanceM: 20,
            ),
          ],
        ),
      ],
      seededLandmarks(),
    );

    await tester.pumpWidget(harness(viewOf(graph), Brightness.light));

    expect(tester.takeException(), isNull);
  });

  testWidgets('every landmark is published as a semantics node',
      (tester) async {
    // The whole point of the plan being reachable without sight: a CustomPaint
    // is one unlabelled box unless it says otherwise.
    final handle = tester.ensureSemantics();
    final graph = FloorGraph.merge([seededRoute()], seededLandmarks());

    await tester.pumpWidget(
      harness(
        viewOf(
          graph,
          route: PlannedRoute.fromRecorded(seededRoute()),
          onLandmarkTap: (_) {},
        ),
        Brightness.light,
      ),
    );
    await tester.pumpAndSettle();

    // Name, kind, and role in the current journey — "Help desk" alone does not
    // say whether it is on the way.
    expect(
      semanticsLabels(tester),
      containsAll([
        'Main entrance, entrance, on your route',
        'Help desk, junction, on your route',
        'Ground floor stairwell, stairs, on your route',
      ]),
    );

    // The destination is upstairs, so it is not on this plane at all — the
    // floor switcher is how the user follows the route up to it.
    expect(
      semanticsLabels(tester),
      isNot(contains('Reading Hall door, door, your destination')),
    );

    handle.dispose();
  });

  testWidgets('the destination is announced as such on its own floor',
      (tester) async {
    final handle = tester.ensureSemantics();
    final graph = FloorGraph.merge([seededRoute()], seededLandmarks());

    await tester.pumpWidget(
      harness(
        viewOf(
          graph,
          floorId: 'floor-2',
          route: PlannedRoute.fromRecorded(seededRoute()),
          onLandmarkTap: (_) {},
        ),
        Brightness.light,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      semanticsLabels(tester),
      contains('Reading Hall door, door, your destination'),
    );

    handle.dispose();
  });

  testWidgets('a landmark off the route says so by saying nothing extra',
      (tester) async {
    final handle = tester.ensureSemantics();
    final graph = FloorGraph.merge([seededRoute()], seededLandmarks());

    await tester.pumpWidget(
      harness(viewOf(graph, onLandmarkTap: (_) {}), Brightness.light),
    );
    await tester.pumpAndSettle();

    // No route at all, so nothing is "on your route" — the label is name and
    // kind only, never a role the journey does not have.
    expect(semanticsLabels(tester), contains('Help desk, junction'));

    handle.dispose();
  });

  testWidgets('tapping near a landmark reports it', (tester) async {
    final graph = FloorGraph.merge([seededRoute()], seededLandmarks());
    final tapped = <String>[];

    await tester.pumpWidget(
      harness(viewOf(graph, onLandmarkTap: tapped.add), Brightness.light),
    );
    await tester.pumpAndSettle();

    final view = tester.widget<FloorPlanView>(find.byType(FloorPlanView));
    final box = tester.renderObject<RenderBox>(find.byType(FloorPlanView));
    final viewport = PlanViewport.fit(
      view.nodes,
      width: box.size.width,
      height: box.size.height,
    );
    final desk = view.nodes.firstWhere((n) => n.landmarkId == 'lm-desk');

    await tester.tapAt(
      box.localToGlobal(
        Offset(viewport.toCanvasX(desk.x), viewport.toCanvasY(desk.y)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tapped, ['lm-desk']);
  });

  testWidgets('a tap that lands on nothing reports nothing', (tester) async {
    final graph = FloorGraph.merge([seededRoute()], seededLandmarks());
    final tapped = <String>[];

    await tester.pumpWidget(
      harness(viewOf(graph, onLandmarkTap: tapped.add), Brightness.light),
    );
    await tester.pumpAndSettle();

    final box = tester.renderObject<RenderBox>(find.byType(FloorPlanView));
    await tester.tapAt(box.localToGlobal(const Offset(2, 2)));
    await tester.pumpAndSettle();

    expect(tapped, isEmpty);
  });
}
