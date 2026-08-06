import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:echo_locate/core/theme/app_theme.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/routing/bloc/floor_plan_bloc.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/mapping/plan_viewport.dart';
import 'package:echo_locate/ui/widgets/floor_plan_painter.dart';

Future<FloorPlanState> seededState({String? destinationRoomId}) async {
  final bloc = FloorPlanBloc(MockRouteRepository(), MockBuildingRepository())
    ..add(
      FloorPlanStarted('knust-library', destinationRoomId: destinationRoomId),
    );
  final state = await bloc.stream.firstWhere(
    (s) => s.status == FloorPlanStatus.success,
  );
  await bloc.close();
  return state;
}

Widget wrap(Widget child, ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(body: SizedBox(width: 360, height: 640, child: child)),
    );

void main() {
  // Loaded once, outside any test: `testWidgets` runs in a fake-async zone
  // where the repository's latency never elapses, so awaiting the bloc inside
  // one hangs until the suite times out.
  late FloorPlanState groundFloor;
  late FloorPlanState routed;

  setUpAll(() async {
    // AppTheme's type scale comes from `google_fonts`, which otherwise tries
    // to fetch over HTTP. The painter cares about colours, not glyphs.
    GoogleFonts.config.allowRuntimeFetching = false;
    groundFloor = await seededState();
    routed = await seededState(destinationRoomId: 'reading-hall');
  });

  testWidgets('renders the seeded plan in light and dark', (tester) async {
    final state = routed;

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        wrap(
          FloorPlanView(
            nodes: state.visibleNodes,
            edges: state.visibleEdges,
            landmarks: state.landmarks,
            route: state.route,
            currentLandmarkId: state.currentLandmarkId,
          ),
          theme,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FloorPlanView), findsOne);
    }
  });

  testWidgets('paints an empty floor without throwing', (tester) async {
    // First frame of a building with no routes, and the case a floor id that
    // carries no landmarks would produce.
    await tester.pumpWidget(
      wrap(
        const FloorPlanView(nodes: [], edges: [], landmarks: {}),
        AppTheme.light,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a canvas with no room to draw in', (tester) async {
    final state = groundFloor;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 4,
            height: 4,
            child: FloorPlanView(
              nodes: state.visibleNodes,
              edges: state.visibleEdges,
              landmarks: state.landmarks,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('landmark hit testing', () {
    testWidgets('a tap on a node reports it', (tester) async {
      String? tapped;
      final state = groundFloor;

      await tester.pumpWidget(
        wrap(
          FloorPlanView(
            nodes: state.visibleNodes,
            edges: state.visibleEdges,
            landmarks: state.landmarks,
            onLandmarkTap: (id) => tapped = id,
          ),
          AppTheme.light,
        ),
      );
      await tester.pumpAndSettle();

      final view = tester.widget<FloorPlanView>(find.byType(FloorPlanView));
      final box = tester.renderObject<RenderBox>(find.byType(FloorPlanView));
      final viewport = PlanViewport.fit(
        state.visibleNodes,
        width: box.size.width,
        height: box.size.height,
      );

      final target = state.visibleNodes.firstWhere(
        (n) => n.landmarkId == 'lm-stairs-g',
      );
      await tester.tapAt(
        box.localToGlobal(
          Offset(viewport.toCanvasX(target.x), viewport.toCanvasY(target.y)),
        ),
      );
      await tester.pump();

      expect(tapped, 'lm-stairs-g');
      expect(view.onLandmarkTap, isNotNull);
    });

    test('picks the nearest node and ignores far taps', () async {
      final state = groundFloor;
      const viewport = PlanViewport(scale: 4, originX: 100, originY: 300);

      final view = FloorPlanView(
        nodes: state.visibleNodes,
        edges: state.visibleEdges,
        landmarks: state.landmarks,
      );

      final desk = state.visibleNodes.firstWhere(
        (n) => n.landmarkId == 'lm-desk',
      );
      final at = Offset(
        viewport.toCanvasX(desk.x),
        viewport.toCanvasY(desk.y),
      );

      expect(view.nearestTo(at, viewport), 'lm-desk');
      // Just inside the generous finger-sized radius.
      expect(view.nearestTo(at + const Offset(20, 0), viewport), 'lm-desk');
      // Well outside it: a tap on empty corridor selects nothing rather than
      // silently teleporting the user to the closest sign.
      expect(view.nearestTo(at + const Offset(400, 400), viewport), isNull);
    });
  });

  testWidgets('draws a route whose legs leave the floor', (tester) async {
    // The entrance-to-Reading-Hall route spans two floors; drawing it on the
    // ground plane means silently skipping the legs that are not there.
    final state = routed;

    await tester.pumpWidget(
      wrap(
        FloorPlanView(
          nodes: state.visibleNodes,
          edges: state.visibleEdges,
          landmarks: state.landmarks,
          route: state.route,
        ),
        AppTheme.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(state.route!.landmarkIds.length, greaterThan(state.visibleNodes.length));
    expect(tester.takeException(), isNull);
  });

  group('semantics', () {
    testWidgets('publishes every landmark, named and placed', (tester) async {
      final handle = tester.ensureSemantics();
      final state = routed;

      await tester.pumpWidget(
        wrap(
          FloorPlanView(
            nodes: state.visibleNodes,
            edges: state.visibleEdges,
            landmarks: state.landmarks,
            route: state.route,
            currentLandmarkId: state.currentLandmarkId,
            onLandmarkTap: (_) {},
          ),
          AppTheme.light,
        ),
      );
      await tester.pumpAndSettle();

      // A CustomPaint is one opaque box to a screen reader unless the painter
      // says otherwise. Each landmark has to be findable on its own.
      expect(
        find.semantics.byLabel('Main entrance, entrance, you are here'),
        findsOne,
      );
      expect(find.semantics.byLabel('Help desk, junction, on your route'), findsOne);
      expect(
        find.semantics
            .byLabel('Ground floor stairwell, stairs, on your route'),
        findsOne,
      );

      handle.dispose();
    });

    testWidgets('a landmark can be activated without sight', (tester) async {
      final handle = tester.ensureSemantics();
      final state = routed;
      String? tapped;

      await tester.pumpWidget(
        wrap(
          FloorPlanView(
            nodes: state.visibleNodes,
            edges: state.visibleEdges,
            landmarks: state.landmarks,
            route: state.route,
            currentLandmarkId: state.currentLandmarkId,
            onLandmarkTap: (id) => tapped = id,
          ),
          AppTheme.light,
        ),
      );
      await tester.pumpAndSettle();

      // "I am here" is the only input this screen has. If it needs a sighted
      // aim at a 6px dot, the app's own audience cannot give it.
      tester.semantics.tap(
        find.semantics.byLabel('Help desk, junction, on your route'),
      );
      await tester.pump();

      expect(tapped, 'lm-desk');
      handle.dispose();
    });

    testWidgets('an unreachable plan is still legible', (tester) async {
      final handle = tester.ensureSemantics();
      final state = groundFloor;

      await tester.pumpWidget(
        wrap(
          FloorPlanView(
            nodes: state.visibleNodes,
            edges: state.visibleEdges,
            landmarks: state.landmarks,
          ),
          AppTheme.dark,
        ),
      );
      await tester.pumpAndSettle();

      // No route, no tap handler — the landmarks are still announced, just not
      // as buttons.
      expect(find.semantics.byLabel('Help desk, junction'), findsOne);
      handle.dispose();
    });
  });
}
