import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/room_trace/bloc/room_trace_bloc.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/mapping/plan_photo_service.dart';
import 'package:echo_locate/ui/pages/room_trace/room_trace_page.dart';
import 'package:echo_locate/ui/widgets/room_trace_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockPhotos extends Mock implements PlanPhotoService {}

class _MockBuildings extends Mock implements BuildingRepository {}

void main() {
  late _MockPlans plans;
  late _MockPhotos photos;
  late _MockBuildings buildings;

  setUpAll(() => registerFallbackValue(RoomPlan.empty));

  setUp(() {
    plans = _MockPlans();
    photos = _MockPhotos();
    buildings = _MockBuildings();

    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'floor-uuid-g', label: 'G', rooms: []),
      ],
    );
    // No camera in a test environment, which is also the real case on a device
    // where permission was refused — the screen must still be usable.
    when(() => photos.start()).thenAnswer((_) async => false);
    when(() => photos.stop()).thenAnswer((_) async {});
    when(
      () => photos.storedPhotos(any()),
    ).thenAnswer((_) async => const <String, String>{});
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);
    when(() => plans.save(any())).thenAnswer((_) async {});
  });

  /// The page's own body, given a bloc — bypasses the router and GetIt so the
  /// screen is testable in isolation.
  Widget host({Brightness brightness = Brightness.light}) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: BlocProvider(
      create: (_) =>
          RoomTraceBloc(plans, photos, buildings)
            ..add(const RoomTraceStarted(buildingId: 'knust-cs')),
      child: const RoomTraceView(),
    ),
  );

  testWidgets('offers tracing without a photo when there is no camera', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Trace without a photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping corners draws them and enables closing', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trace without a photo'));
    await tester.pumpAndSettle();

    // Close room is disabled until three corners are down.
    final closeButton = find.widgetWithText(FilledButton, 'Close room');
    expect(tester.widget<FilledButton>(closeButton).onPressed, isNull);

    final box = tester.getRect(find.byKey(traceSurfaceKey));
    for (final offset in [
      const Offset(40, 40),
      const Offset(140, 40),
      const Offset(140, 140),
    ]) {
      await tester.tapAt(box.topLeft + offset);
      await tester.pump();
    }

    expect(find.textContaining('3 placed'), findsOneWidget);
    expect(tester.widget<FilledButton>(closeButton).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the trace step in dark mode', (tester) async {
    await tester.pumpWidget(host(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trace without a photo'));
    await tester.pumpAndSettle();

    expect(find.text('Rooms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to door mode changes the instruction', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trace without a photo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tap the corners'), findsOneWidget);

    await tester.tap(find.text('Doors'));
    await tester.pumpAndSettle();

    expect(find.textContaining('opens onto the corridor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the room sheet asks for a category before adding', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trace without a photo'));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byKey(traceSurfaceKey));
    for (final offset in [
      const Offset(40, 40),
      const Offset(140, 40),
      const Offset(140, 140),
    ]) {
      await tester.tapAt(box.topLeft + offset);
      await tester.pump();
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Close room'));
    await tester.pumpAndSettle();

    expect(find.text('What is this room?'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Office'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Laboratory'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add room'));
    await tester.pumpAndSettle();

    // Back on the trace step with the room kept.
    expect(find.textContaining('Tap the corners'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('the tracing surface stays put', () {
    testWidgets('switching tools does not move the plan under what is drawn', (
      tester,
    ) async {
      // The bug this pins. Taps are stored as fractions of the surface's width
      // and drawn back the same way, so if the surface moves or resizes, every
      // room already traced slides off the photograph it was traced from.
      //
      // It did move: the surface filled whatever space was left between the
      // mode bar and the controls, and the controls are a different height for
      // every tool. Going from Rooms to Doors resized the surface, and the
      // photograph — letter-boxed and centred inside it — slid out from under
      // rooms that stayed where they were put.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      final rects = <String, Rect>{};
      for (final tool in ['Rooms', 'Halls', 'Doors', 'Stairs']) {
        await tester.tap(find.text(tool));
        await tester.pumpAndSettle();
        rects[tool] = tester.getRect(find.byKey(traceSurfaceKey));
      }

      expect(
        rects.values.toSet(),
        hasLength(1),
        reason: 'the surface moved between tools: $rects',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the surface has the shape of the photo it is drawing', (
      tester,
    ) async {
      // Not merely constant — the right shape. A surface that keeps its size
      // but is not the photo's shape letter-boxes the photo inside it again,
      // which puts a fixed offset between the picture and the overlay instead
      // of a changing one.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byKey(traceSurfaceKey));
      expect(
        rect.width / rect.height,
        closeTo(RoomTraceState.defaultAspect, 0.01),
      );
    });
  });

  group('zooming into the plan', () {
    /// The plan coordinates of every corner tapped so far.
    List<Offset> draftOf(WidgetTester tester) => BlocProvider.of<RoomTraceBloc>(
      tester.element(find.byType(RoomTraceView)),
    ).state.draft;

    /// Pinches outwards about [focus] until the plan is [scale] times larger.
    Future<void> pinch(WidgetTester tester, Offset focus, double scale) async {
      const reach = 40.0;
      final one = await tester.startGesture(focus - const Offset(reach, 0));
      final two = await tester.startGesture(focus + const Offset(reach, 0));
      await tester.pump();

      final grown = reach * scale;
      await one.moveTo(focus - Offset(grown, 0));
      await two.moveTo(focus + Offset(grown, 0));
      await tester.pump();

      await one.up();
      await two.up();
      await tester.pumpAndSettle();
    }

    testWidgets('zooming in makes the same finger movement finer', (
      tester,
    ) async {
      // The claim the whole feature rests on, stated as what it is for: after
      // zooming, a given wobble of the finger covers less of the plan, which is
      // exactly what "the corners are easier to hit" means.
      //
      // It is also the check that taps are being transformed at all.
      // `InteractiveViewer` hit-tests *through* its transform, so the gesture
      // detector underneath still receives box coordinates and nothing below it
      // knows a zoom happened. Nothing about that is obvious, and if it ever
      // stopped being true every corner would land somewhere else on the plan,
      // with no error and nothing on screen to say so.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byKey(traceSurfaceKey));
      const apart = Offset(100, 0);

      Future<double> spanOfTwoTaps() async {
        await tester.tapAt(box.center);
        await tester.pump();
        await tester.tapAt(box.center + apart);
        await tester.pump();
        final drawn = draftOf(tester);
        return (drawn.last - drawn[drawn.length - 2]).distance;
      }

      final atRest = await spanOfTwoTaps();
      expect(atRest, greaterThan(0));

      await pinch(tester, box.center, 3);
      final zoomed = await spanOfTwoTaps();

      // Finer, and by a clear margin. Not a fixed factor: how much scale a
      // two-pointer gesture actually delivers depends on when the recogniser
      // accepts it, and pinning that would be testing `InteractiveViewer`
      // rather than anything this screen decides.
      expect(zoomed, lessThan(atRest * 0.9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('markers shrink so they do not swallow what is under them', (
      tester,
    ) async {
      // A corner marker is 7 pixels. Inside the zoom it is 7 *plan* pixels, so
      // at 8× it is a coral disc wide enough to cover several rooms — the
      // marker ends up hiding the corner it was placed on, which is the
      // opposite of what zooming in is for. The painter divides its fixed sizes
      // by this, so it has to actually arrive.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      RoomTracePainter painterNow() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<RoomTracePainter>()
          .first;

      expect(painterNow().zoom, 1);

      await pinch(
        tester,
        tester.getRect(find.byKey(traceSurfaceKey)).center,
        3,
      );

      expect(painterNow().zoom, greaterThan(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers a way back to the whole floor once zoomed', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      // Nothing to reset while the whole floor is already in view.
      expect(find.text('Fit'), findsNothing);

      await pinch(
        tester,
        tester.getRect(find.byKey(traceSurfaceKey)).center,
        3,
      );
      expect(find.text('Fit'), findsOneWidget);

      await tester.tap(find.text('Fit'));
      await tester.pumpAndSettle();
      expect(find.text('Fit'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the new drawing tools', () {
    testWidgets('all four are reachable on a narrow phone', (tester) async {
      // The regression this exists for: four labelled segments plus icons used
      // to overflow, and "Doors" was entirely off-screen — so door placement,
      // without which a floor is a picture rather than a map, could not be
      // reached at all.
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      for (final label in ['Rooms', 'Halls', 'Doors', 'Stairs']) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('drawing a hall asks for its name, not its corners', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Halls'));
      await tester.pumpAndSettle();
      expect(find.textContaining('middle of a hallway'), findsOneWidget);

      final box = tester.getRect(find.byKey(traceSurfaceKey));
      // Two taps, where a room would need three.
      await tester.tapAt(box.topLeft + const Offset(40, 100));
      await tester.tapAt(box.topLeft + const Offset(200, 100));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Finish hall'));
      await tester.pumpAndSettle();

      expect(find.text('Name this hallway'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add hallway'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('stairs mode counts what it has marked', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stairs'));
      await tester.pumpAndSettle();
      expect(find.text('No stairs marked yet'), findsOneWidget);

      final box = tester.getRect(find.byKey(traceSurfaceKey));
      await tester.tapAt(box.topLeft + const Offset(60, 60));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 marked so far'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('board and scale are still reachable from the setup menu', (
      tester,
    ) async {
      // They lost their segments to the drawing tools. Losing the *steps*
      // would mean every room on the floor keeping the photograph's skew.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace without a photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Set the board up'));
      await tester.pumpAndSettle();

      expect(find.text('Square the board up'), findsOneWidget);
      expect(find.text('Set the scale'), findsOneWidget);

      await tester.tap(find.text('Square the board up'));
      await tester.pumpAndSettle();

      expect(find.textContaining('four corners of the plan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
