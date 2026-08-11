import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:echo_locate/ui/widgets/floor_plan_painter.dart';
import 'package:flutter/material.dart';
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
        'lm-entrance': ('Main entrance', LandmarkKind.entrance),
        'lm-desk': ('Help desk', LandmarkKind.junction),
        'lm-stairs-g': ('Ground floor stairwell', LandmarkKind.stairs),
        'lm-landing-2': ('Floor 2 landing', LandmarkKind.stairs),
        'lm-reading-hall': ('Reading Hall door', LandmarkKind.door),
      }.entries)
        entry.key: Landmark(
          id: entry.key,
          buildingId: 'knust-library',
          floorId: 'floor-g',
          kind: entry.value.$2,
          labelText: entry.value.$1.toUpperCase(),
          displayName: entry.value.$1,
        ),
    };

Widget harness(FloorPlanPainter painter, Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 500,
          child: CustomPaint(size: const Size(360, 500), painter: painter),
        ),
      ),
    );

FloorPlanPainter painterFor(
  FloorGraph graph,
  Brightness brightness, {
  List<String> highlighted = const [],
}) =>
    FloorPlanPainter(
      graph: graph,
      landmarks: seededLandmarks(),
      highlighted: highlighted,
      brightness: brightness,
      hairline: const Color(0xFFE7E5E1),
      onSurface: const Color(0xFF1C1B1A),
      muted: const Color(0xFF6B6966),
    );

void main() {
  testWidgets('the seeded route draws in light and dark', (tester) async {
    final graph = FloorGraph.merge([seededRoute()]);

    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        harness(
          painterFor(
            graph,
            brightness,
            highlighted: seededRoute().landmarkIds,
          ),
          brightness,
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an empty building paints nothing rather than crashing',
      (tester) async {
    await tester.pumpWidget(
      harness(painterFor(FloorGraph.empty, Brightness.light), Brightness.light),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a single-corridor building with no width still fits',
      (tester) async {
    // Every landmark on one straight line: the vertical span is zero, which is
    // where a fit-to-canvas scale divides by nothing.
    final graph = FloorGraph.merge([
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
    ]);

    await tester.pumpWidget(
      harness(painterFor(graph, Brightness.light), Brightness.light),
    );

    expect(tester.takeException(), isNull);
  });
}
