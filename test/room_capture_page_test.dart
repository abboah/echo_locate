import 'dart:async';

import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/room_capture/bloc/room_capture_cubit.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/vision/arcore_capture_service.dart';
import 'package:echo_locate/services/vision/depth_frame.dart'
    show ArCoreAvailability;
import 'package:echo_locate/ui/pages/room_capture/room_capture_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockBuildings extends Mock implements BuildingRepository {}

class _FakeCapture implements ArCoreCaptureService {
  ArCoreAvailability availability = ArCoreAvailability.supported;
  final _controller = StreamController<CaptureFrame>.broadcast();
  final List<CapturedCorner?> hits = [];
  int _index = 0;

  void emit(CaptureFrame frame) => _controller.add(frame);

  @override
  bool get isRunning => true;

  @override
  Future<ArCoreAvailability> checkAvailability() async => availability;

  @override
  Future<String?> start({
    required int viewWidth,
    required int viewHeight,
    int displayRotation = 0,
  }) async => null;

  @override
  Future<void> setViewport({
    required int viewWidth,
    required int viewHeight,
    int displayRotation = 0,
  }) async {}

  @override
  Future<void> stop() async {
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  Future<CapturedCorner?> hitTest(double u, double v) async =>
      _index >= hits.length ? null : hits[_index++];

  @override
  Future<List<CapturedCorner>> resolveCorners(
    List<CapturedCorner> corners,
  ) async => corners;

  @override
  Future<void> releaseCorners(List<CapturedCorner> corners) async {}

  @override
  Future<void> resetPlaneLock() async {}

  @override
  Stream<CaptureFrame> get frames => _controller.stream;
}

void main() {
  late _FakeCapture capture;
  late _MockPlans plans;
  late _MockBuildings buildings;

  setUpAll(() => registerFallbackValue(RoomPlan.empty));

  setUp(() {
    capture = _FakeCapture();
    plans = _MockPlans();
    buildings = _MockBuildings();
    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'floor-uuid-g', label: 'G', rooms: []),
      ],
    );
    when(() => plans.save(any())).thenAnswer((_) async {});
  });

  Widget host({Brightness brightness = Brightness.light}) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: BlocProvider(
      create: (_) =>
          RoomCaptureCubit(capture, plans, buildings)
            ..start(buildingId: 'knust-cs', viewWidth: 1080, viewHeight: 2400),
      child: const RoomCaptureView(buildingId: 'knust-cs'),
    ),
  );

  testWidgets('an uncertified phone is offered photo tracing, not an error', (
    tester,
  ) async {
    capture.availability = ArCoreAvailability.unsupported;

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // What most phones will see. The fallback is not a lesser path — it makes
    // the same plan and it is the one that has actually been proven.
    expect(find.text('This phone cannot scan in AR'), findsOneWidget);
    expect(find.text('Trace from a photo instead'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a certified phone shows the capture view', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    capture.emit(
      const CaptureFrame(
        tracking: CaptureTracking.tracking,
        issue: CaptureTrackingIssue.none,
        planeLocked: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RoomCaptureView.captureSurfaceKey), findsOneWidget);
    expect(find.textContaining('Tap the floor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tells the user what to do when tracking is lost', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    capture.emit(
      const CaptureFrame(
        tracking: CaptureTracking.paused,
        issue: CaptureTrackingIssue.insufficientLight,
        planeLocked: false,
      ),
    );
    await tester.pumpAndSettle();

    // An instruction, not a diagnosis.
    expect(find.textContaining('More light'), findsOneWidget);
  });

  testWidgets('tapping the floor places corners and enables closing', (
    tester,
  ) async {
    capture.hits.addAll([
      const CapturedCorner(position: Offset(0, 0), confidence: 1),
      const CapturedCorner(position: Offset(4, 0), confidence: 1),
      const CapturedCorner(position: Offset(4, 3), confidence: 1),
    ]);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    capture.emit(
      const CaptureFrame(
        tracking: CaptureTracking.tracking,
        issue: CaptureTrackingIssue.none,
        planeLocked: true,
      ),
    );
    await tester.pumpAndSettle();

    final closeButton = find.widgetWithText(FilledButton, 'Close room');
    expect(tester.widget<FilledButton>(closeButton).onPressed, isNull);

    final surface = tester.getRect(
      find.byKey(RoomCaptureView.captureSurfaceKey),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(surface.center);
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('3 corners placed'), findsOneWidget);
    expect(tester.widget<FilledButton>(closeButton).onPressed, isNotNull);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(host(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
