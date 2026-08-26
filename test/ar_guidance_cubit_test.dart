import 'dart:async';

import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/features/guidance/bloc/ar_guidance_cubit.dart';
import 'package:echo_locate/features/guidance/bloc/guidance_bloc.dart';
import 'package:echo_locate/features/guidance/guidance_session.dart';
import 'package:echo_locate/services/audio/audio_arbiter.dart';
import 'package:echo_locate/services/haptics/haptic_service.dart';
import 'package:echo_locate/services/mapping/room_plan_bridge.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';
import 'package:echo_locate/services/motion/step_service.dart';
import 'package:echo_locate/services/motion/stride_profile.dart';
import 'package:echo_locate/services/sensing/analysis_frame.dart';
import 'package:echo_locate/services/sensing/detected_obstacle.dart';
import 'package:echo_locate/services/sensing/detection_service.dart';
import 'package:echo_locate/services/sensing/text_recognition_service.dart';
import 'package:echo_locate/services/speech/speech_service.dart';
import 'package:echo_locate/services/vision/ar_guidance_service.dart';
import 'package:echo_locate/services/vision/depth_frame.dart'
    show ArCoreAvailability;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDetection extends Mock implements DetectionService {}

class _MockTextRecognition extends Mock implements TextRecognitionService {}

class _MockSteps extends Mock implements StepService {}

class _MockSpeech extends Mock implements SpeechService {}

class _MockHaptics extends Mock implements HapticService {}

/// An AR session with no phone behind it.
///
/// Records what the cubit asked the world to draw, which is the whole of its
/// job: everything else about the arrows happens natively, where a test cannot
/// reach and where nothing but a device can answer.
class _FakeAr implements ArGuidanceService {
  ArCoreAvailability availability = ArCoreAvailability.supported;
  String? startFailure;

  final _states = StreamController<ArGuidanceFrame>.broadcast();

  /// Every leg anchored, in order: the turn to make and how far it runs.
  final List<(int, double)> legs = [];

  /// Every route registered, in order, as flattened (x, z) world coordinates.
  final List<List<double>> routes = [];
  int routesCleared = 0;
  int cleared = 0;
  bool analysing = false;
  bool stopped = false;
  (int, int)? viewport;

  /// Every viewport reported, so the chatty-layout case can be checked.
  int viewportCalls = 0;

  /// Held open until completed, to test what happens *during* a slow start.
  Completer<void>? startGate;

  bool _running = false;

  void emit(ArGuidanceFrame frame) => _states.add(frame);

  @override
  bool get isRunning => _running;

  @override
  bool get isStreaming => _running && analysing;

  @override
  bool get holdsCamera => _running;

  @override
  int? get textureId => _running ? 11 : null;

  @override
  Future<ArCoreAvailability> checkAvailability() async => availability;

  @override
  Future<String?> start({
    required int viewWidth,
    required int viewHeight,
  }) async {
    viewport = (viewWidth, viewHeight);
    viewportCalls++;
    await startGate?.future;
    if (startFailure != null) return startFailure;
    _running = true;
    return null;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    _running = false;
  }

  @override
  Future<void> setViewport({
    required int viewWidth,
    required int viewHeight,
  }) async {
    viewport = (viewWidth, viewHeight);
    viewportCalls++;
  }

  @override
  Future<void> setLeg({
    required int turnDeg,
    required double distanceM,
  }) async => legs.add((turnDeg, distanceM));

  @override
  Future<void> clearLeg() async => cleared++;

  @override
  Future<void> setRoute(List<double> points) async => routes.add(points);

  @override
  Future<void> clearRoute() async => routesCleared++;

  @override
  Future<void> setAnalysis({required bool enabled}) async => analysing = enabled;

  @override
  Stream<ArGuidanceFrame> get states => _states.stream;

  @override
  Stream<AnalysisFrame> get analysisFrames => const Stream.empty();

  @override
  void frameHandled() => framesHandled++;

  int framesHandled = 0;
}

void main() {
  late _MockDetection detection;
  late _MockTextRecognition ocr;
  late _MockSteps steps;
  late _MockSpeech speech;
  late _MockHaptics haptics;
  late _FakeAr ar;
  late StreamController<List<DetectedObstacle>> obstacleStream;
  late StreamController<List<String>> readStream;
  late StreamController<int> stepStream;

  setUpAll(() => registerFallbackValue(AudioUse.speech));

  setUp(() {
    detection = _MockDetection();
    ocr = _MockTextRecognition();
    steps = _MockSteps();
    speech = _MockSpeech();
    haptics = _MockHaptics();
    ar = _FakeAr();
    obstacleStream = StreamController<List<DetectedObstacle>>.broadcast();
    readStream = StreamController<List<String>>.broadcast();
    stepStream = StreamController<int>.broadcast();

    when(() => detection.start()).thenAnswer((_) async => true);
    when(() => detection.stop()).thenAnswer((_) async {});
    when(() => detection.obstacles).thenAnswer((_) => obstacleStream.stream);
    when(() => ocr.reads).thenAnswer((_) => readStream.stream);
    when(() => ocr.start()).thenAnswer((_) {});
    when(() => ocr.stop()).thenAnswer((_) async {});
    when(() => steps.start()).thenAnswer((_) async => true);
    when(() => steps.stop()).thenAnswer((_) async {});
    when(() => steps.reset()).thenAnswer((_) {});
    when(() => steps.steps).thenAnswer((_) => stepStream.stream);
    when(() => speech.stop()).thenAnswer((_) async {});
    when(() => speech.speak(any(), interrupt: any(named: 'interrupt'),
        use: any(named: 'use'))).thenAnswer((_) async {});
    when(() => haptics.alert()).thenAnswer((_) async {});
    when(() => haptics.confirm()).thenAnswer((_) async {});
  });

  Landmark landmark(String id) => Landmark(
    id: id,
    buildingId: 'b1',
    floorId: 'f1',
    kind: LandmarkKind.sign,
    labelText: id.toUpperCase(),
    displayName: id,
  );

  /// Entrance → desk (straight on, 20 m) → hall (right 90°, 12 m).
  GuidanceSession sessionOf({bool metric = true}) => GuidanceSession(
    plan: PlannedRoute.fromRecorded(
      const WalkRoute(
        id: 'r1',
        buildingId: 'b1',
        startLandmarkId: 'entrance',
        destinationRoomId: 'room',
        steps: [
          RouteStep(
            seq: 1,
            fromLandmarkId: 'entrance',
            toLandmarkId: 'desk',
            instruction: 'straight on',
            distanceM: 20,
          ),
          RouteStep(
            seq: 2,
            fromLandmarkId: 'desk',
            toLandmarkId: 'hall',
            instruction: 'turn right',
            distanceM: 12,
            turnDeg: 90,
          ),
        ],
      ),
    ),
    landmarks: [landmark('entrance'), landmark('desk'), landmark('hall')],
    destinationName: 'Reading Hall',
    stride: const StrideProfile(metres: 0.5, source: StrideSource.calibrated),
    metric: metric,
  );

  Future<void> pump() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  GuidanceBloc guidanceOf() => GuidanceBloc(
    detection: detection,
    textRecognition: ocr,
    steps: steps,
    speech: speech,
    haptics: haptics,
  );

  /// A walk under way with the AR layer running over it.
  Future<(GuidanceBloc, ArGuidanceCubit)> walking({bool metric = true}) async {
    final guidance = guidanceOf();
    final cubit = ArGuidanceCubit(ar, guidance);
    await cubit.checkAvailability();
    guidance.add(GuidanceStarted(sessionOf(metric: metric)));
    await pump();
    await cubit.start(viewWidth: 1080, viewHeight: 1920);
    await pump();
    return (guidance, cubit);
  }

  group('anchoring the arrows to the route', () {
    test('the leg already being walked is anchored on start', () async {
      final (guidance, cubit) = await walking();

      // Not waited for: guidance starts before the AR session does, so a leg
      // is already under way, and deferring to the next landmark would leave a
      // corridor with no arrows in it.
      expect(ar.legs, [(0, 20.0)]);
      await cubit.close();
      await guidance.close();
    });

    test('reaching a landmark re-anchors on the new leg and its turn', () async {
      final (guidance, cubit) = await walking();

      guidance.add(const GuidanceLandmarkConfirmed());
      await pump();

      // The turn is the leg's own, applied to how the walker was moving — which
      // is what native does with it.
      expect(ar.legs, [(0, 20.0), (90, 12.0)]);
      await cubit.close();
      await guidance.close();
    });

    test('an unrelated change does not re-anchor a leg being walked', () async {
      final (guidance, cubit) = await walking();

      // Steps, obstacles and the voice toggle all emit guidance states. Each
      // one re-anchoring would reset the arrows off the walker's *current*
      // direction — mid-corridor, that is a fresh turn applied to a heading
      // that has already turned.
      guidance.add(const GuidanceVoiceToggled());
      stepStream.add(4);
      await pump();

      expect(ar.legs, hasLength(1));
      await cubit.close();
      await guidance.close();
    });

    test('getting lost takes the arrows away', () async {
      final (guidance, cubit) = await walking();

      guidance.add(const GuidanceLostReported());
      await pump();

      // A sweep to find a sign is exactly when the last leg's direction is
      // least trustworthy. Arrows left on screen would say "keep walking" to
      // somebody who has already left the route.
      expect(ar.cleared, 1);
      expect(cubit.state.hasLeg, isFalse);
      await cubit.close();
      await guidance.close();
    });

    test('arriving takes them away too', () async {
      final (guidance, cubit) = await walking();

      guidance.add(const GuidanceLandmarkConfirmed());
      await pump();
      guidance.add(const GuidanceLandmarkConfirmed());
      await pump();

      expect(guidance.state.status, GuidanceStatus.arrived);
      expect(ar.cleared, greaterThanOrEqualTo(1));
      await cubit.close();
      await guidance.close();
    });

    test('a route with no real scale gets a nominal length, not a made-up '
        'one', () async {
      final (guidance, cubit) = await walking(metric: false);

      // A plan traced off a photograph measures in fractions of that image, so
      // its "20" is not twenty metres. The direction is still right — ninety
      // degrees is ninety degrees at any scale — so the arrows are laid along a
      // nominal corridor and the countdown is withheld.
      expect(ar.legs, [(0, ArGuidanceCubit.nominalLegMetres)]);
      expect(cubit.state.distanceKnown, isFalse);
      expect(cubit.state.remainingLabel, isNull);
      await cubit.close();
      await guidance.close();
    });
  });

  group('when the world moves under the arrows', () {
    test('losing and regaining the arrows does not re-issue the leg', () async {
      final (guidance, cubit) = await walking();
      expect(ar.legs, hasLength(1));

      // ARCore lost the room and found it again, and native rebuilt the anchor
      // by itself. It must: it is the side that knows how much of the leg has
      // been walked, and therefore that the walker made this leg's turn twenty
      // metres ago. Re-issuing the leg from here would apply that turn a second
      // time, halfway down a corridor, and send the arrows round a corner that
      // is not there.
      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.paused,
          issue: ArGuidanceIssue.insufficientFeatures,
        ),
      );
      await pump();
      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          anchoredFromCamera: true,
        ),
      );
      await pump();

      expect(ar.legs, hasLength(1));
      // The rebuilt anchor is a guess until there is motion to measure, and the
      // screen says so rather than pretending otherwise.
      expect(cubit.state.hint, contains('few steps'));
      await cubit.close();
      await guidance.close();
    });

    test('a session that ends by itself lets the texture go', () async {
      final (guidance, cubit) = await walking();
      expect(cubit.state.textureId, 11);

      // The camera went to another app, or a call came in, and native stopped
      // without being asked. A `Texture` left pointing at a released id draws
      // its last frame forever — which reads as a working camera that has
      // simply stopped moving, over a corridor the walker has left.
      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.stopped,
          issue: ArGuidanceIssue.none,
          sessionEnded: true,
        ),
      );
      await pump();

      expect(cubit.state.running, isFalse);
      expect(cubit.state.textureId, isNull);
      expect(ar.stopped, isTrue);
      await cubit.close();
      await guidance.close();
    });

    test('walking well past the landmark is said out loud, not counted down',
        () async {
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          headingReady: true,
          overshootM: 6,
        ),
      );
      await pump();

      expect(cubit.state.hasOvershot, isTrue);
      expect(cubit.state.hint, contains('passed it'));
      // "Almost there" under "you may have passed it" is the screen arguing
      // with itself.
      expect(cubit.state.remainingLabel, isNull);
      await cubit.close();
      await guidance.close();
    });

    test('a metre or two over is normal and stays quiet', () async {
      final (guidance, cubit) = await walking();

      // Leg lengths come from whoever recorded the route. Saying something
      // every time one runs short would train the walker to ignore the line.
      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          headingReady: true,
          overshootM: 2,
        ),
      );
      await pump();

      expect(cubit.state.hasOvershot, isFalse);
      expect(cubit.state.hint, isNull);
      await cubit.close();
      await guidance.close();
    });
  });

  group('the distance that flows back to the walk', () {
    test('is what paces the spoken checkpoints', () async {
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          headingReady: true,
          walkedM: 6,
        ),
      );
      await pump();

      expect(guidance.state.walkedM, 6);
      await cubit.close();
      await guidance.close();
    });

    test('is not sent while tracking is lost', () async {
      // A paused session keeps reporting the last distance it knew. Handed on,
      // that is a walker who has stopped where they were told to — and the
      // walk would go on counting down a corridor nobody is walking.
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.paused,
          issue: ArGuidanceIssue.excessiveMotion,
          hasLeg: true,
          headingReady: true,
          walkedM: 6,
        ),
      );
      await pump();

      expect(guidance.state.walkedM, 0);
      await cubit.close();
      await guidance.close();
    });

    test('is not sent before a leg is anchored', () async {
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          headingReady: true,
          walkedM: 6,
        ),
      );
      await pump();

      expect(guidance.state.walkedM, 0);
      await cubit.close();
      await guidance.close();
    });

    test('is sent even when the route is not in metres', () async {
      // These metres are real whatever the plan is drawn in — ARCore measures
      // the corridor, not the image. On a traced route they are the only real
      // distance in the system: what paces the walk before the scale is known,
      // and what the scale is then learned from.
      final (guidance, cubit) = await walking(metric: false);

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          headingReady: true,
          walkedM: 6,
        ),
      );
      await pump();

      expect(guidance.state.walkedM, 6);
      // But no countdown is quoted from it: the leg length is still unknown.
      expect(cubit.state.distanceKnown, isFalse);
      await cubit.close();
      await guidance.close();
    });
  });

  group('the session', () {
    test('turns on the frame feed, because that is what keeps sign reading '
        'alive', () async {
      final (guidance, cubit) = await walking();

      // ARCore holds the camera exclusively. Without this the AR view would
      // silently cost a blind user both obstacle callouts and every automatic
      // landmark confirmation on the route.
      expect(ar.analysing, isTrue);
      expect(ar.isStreaming, isTrue);
      await cubit.close();
      await guidance.close();
    });

    test('an uncertified phone leaves the screen alone', () async {
      ar.availability = ArCoreAvailability.unsupported;
      final guidance = guidanceOf();
      final cubit = ArGuidanceCubit(ar, guidance);

      final supported = await cubit.checkAvailability();

      expect(supported, isFalse);
      expect(cubit.state.isSupported, isFalse);
      expect(ar.legs, isEmpty);
      await cubit.close();
      await guidance.close();
    });

    test('a session that fails to start is a warning, not a dead screen',
        () async {
      ar.startFailure = 'The camera is not available right now.';
      final guidance = guidanceOf();
      final cubit = ArGuidanceCubit(ar, guidance);
      await cubit.checkAvailability();

      await cubit.start(viewWidth: 1080, viewHeight: 1920);

      expect(cubit.state.running, isFalse);
      expect(cubit.state.error, isNotNull);
      await cubit.close();
      await guidance.close();
    });

    test('a second start while the first is still coming up is ignored',
        () async {
      final guidance = guidanceOf();
      final cubit = ArGuidanceCubit(ar, guidance);
      ar.startGate = Completer<void>();

      // The page boots and a lifecycle resume lands on top of it — an ordinary
      // sequence when a permission dialog closes. Two sessions would fight over
      // a camera only one of them can have.
      final first = cubit.start(viewWidth: 1080, viewHeight: 1920);
      final second = cubit.start(viewWidth: 1080, viewHeight: 1920);
      ar.startGate!.complete();
      await first;
      await second;

      expect(ar.viewportCalls, 1);
      expect(cubit.state.running, isTrue);
      await cubit.close();
      await guidance.close();
    });

    test('backgrounding during startup still releases the camera', () async {
      final guidance = guidanceOf();
      final cubit = ArGuidanceCubit(ar, guidance);
      ar.startGate = Completer<void>();

      final starting = cubit.start(viewWidth: 1080, viewHeight: 1920);
      // Away before it ever drew a frame. Returning early here would leave
      // ARCore holding the camera through a backgrounded app.
      await cubit.stop();
      ar.startGate!.complete();
      await starting;
      await pump();

      expect(ar.stopped, isTrue);
      expect(cubit.state.running, isFalse);
      await cubit.close();
      await guidance.close();
    });

    test('an unchanged viewport is not reported on every rebuild', () async {
      final (guidance, cubit) = await walking();
      final before = ar.viewportCalls;

      // The layout callback fires on every rebuild, and the arrows rebuild this
      // screen several times a second. (It is offered again on a slow timer, so
      // that a phone turned end over end — same width, same height, different
      // display rotation — is still noticed. Only native can see that.)
      await cubit.setViewport(viewWidth: 1080, viewHeight: 1600);
      await cubit.setViewport(viewWidth: 1080, viewHeight: 1600);
      await cubit.setViewport(viewWidth: 1080, viewHeight: 1600);

      expect(ar.viewportCalls - before, 1);
      await cubit.close();
      await guidance.close();
    });

    test('a resized viewport is reported at once', () async {
      final (guidance, cubit) = await walking();
      final before = ar.viewportCalls;

      await cubit.setViewport(viewWidth: 1080, viewHeight: 1600);
      await cubit.setViewport(viewWidth: 1600, viewHeight: 1080);

      expect(ar.viewportCalls - before, 2);
      expect(ar.viewport, (1600, 1080));
      await cubit.close();
      await guidance.close();
    });

    test('stopping releases the texture with the session', () async {
      final (guidance, cubit) = await walking();
      expect(cubit.state.textureId, 11);

      await cubit.stop();

      // A `Texture` widget still pointing at a released id draws a blank
      // rectangle, with no crash and nothing in the log.
      expect(cubit.state.textureId, isNull);
      expect(ar.stopped, isTrue);
      await cubit.close();
      await guidance.close();
    });
  });

  group('what the overlay says', () {
    test('asks for a few steps when the leg was anchored off the camera',
        () async {
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          anchoredFromCamera: true,
        ),
      );
      await pump();

      // The one case where the arrows can be confidently wrong.
      expect(cubit.state.hint, contains('few steps'));
      await cubit.close();
      await guidance.close();
    });

    test('says where the route is when it is not straight ahead', () async {
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          headingReady: true,
          bearingDeg: 70,
        ),
      );
      await pump();

      expect(cubit.state.turnHint, ArTurnHint.right);
      expect(cubit.state.hint, 'The way is to your right.');
      await cubit.close();
      await guidance.close();
    });

    test('says turn around rather than picking a side, when it is behind you',
        () async {
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          headingReady: true,
          bearingDeg: -170,
        ),
      );
      await pump();

      expect(cubit.state.turnHint, ArTurnHint.around);
      await cubit.close();
      await guidance.close();
    });

    test('lost tracking is phrased as something to do', () async {
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.paused,
          issue: ArGuidanceIssue.insufficientFeatures,
          hasLeg: true,
        ),
      );
      await pump();

      expect(cubit.state.hint, contains('corridor'));
      await cubit.close();
      await guidance.close();
    });

    test('the countdown rounds to metres and gives up near the end', () async {
      final (guidance, cubit) = await walking();

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          headingReady: true,
          remainingM: 7.4,
        ),
      );
      await pump();
      expect(cubit.state.remainingLabel, '7 m');

      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          headingReady: true,
          remainingM: 0.75,
        ),
      );
      await pump();
      // "1 m" is a promise the anchoring cannot keep; "almost there" is true
      // whatever the last metre of drift did.
      expect(cubit.state.remainingLabel, 'Almost there');
      await cubit.close();
      await guidance.close();
    });
  });

  group('registering the plan into the room', () {
    /// A route that leaves the start heading plan-north for 20 m, then turns
    /// east for 12 m — the same walk `sessionOf` describes, with geometry.
    RoutePath pathOf() => const RoutePath(
      pointsM: [Offset(0, 0), Offset(0, 20), Offset(12, 20)],
      legEndsM: [20, 32],
    );

    Future<(GuidanceBloc, ArGuidanceCubit)> walkingWithGeometry() async {
      final guidance = guidanceOf();
      final cubit = ArGuidanceCubit(ar, guidance);
      await cubit.checkAvailability();
      final base = sessionOf();
      guidance.add(
        GuidanceStarted(
          GuidanceSession(
            plan: base.plan,
            landmarks: base.landmarks,
            destinationName: base.destinationName,
            stride: base.stride,
            routePath: pathOf(),
          ),
        ),
      );
      await pump();
      await cubit.start(viewWidth: 1080, viewHeight: 1920);
      await pump();
      return (guidance, cubit);
    }

    /// A frame carrying everything a registration needs.
    ArGuidanceFrame walked({
      required double x,
      required double z,
      required double headingDeg,
      double offRoute = 0,
      bool hasRoute = false,
    }) => ArGuidanceFrame(
      tracking: CaptureTrackingLike.tracking,
      issue: ArGuidanceIssue.none,
      hasLeg: true,
      headingReady: true,
      cameraX: x,
      cameraZ: z,
      travelHeadingDeg: headingDeg,
      hasRoute: hasRoute,
      offRouteM: offRoute,
    );

    test('nothing is registered until the walker has moved', () async {
      final (guidance, cubit) = await walkingWithGeometry();

      // Standing still: ARCore has a position but no direction of travel, and
      // a rotation cannot be solved from a position alone.
      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          cameraX: 0,
          cameraZ: 0,
        ),
      );
      await pump();

      expect(ar.routes, isEmpty);
      expect(cubit.state.registered, isFalse);
      await cubit.close();
      await guidance.close();
    });

    /// The walker standing at the start, before they have moved. Registration
    /// cannot happen on this frame — there is no heading in it — but it is the
    /// frame that fixes *where the start is*.
    ArGuidanceFrame standingAt(double x, double z) => ArGuidanceFrame(
      tracking: CaptureTrackingLike.tracking,
      issue: ArGuidanceIssue.none,
      hasLeg: true,
      cameraX: x,
      cameraZ: z,
    );

    test('THE POINT: the whole route is laid into the room, once', () async {
      final (guidance, cubit) = await walkingWithGeometry();

      // Standing at the start, then two metres of walking straight ahead in
      // ARCore's frame. The route leaves plan-north, so plan-north *is*
      // straight ahead: the transform comes out unrotated, along −z.
      ar.emit(standingAt(0, 0));
      await pump();
      ar.emit(walked(x: 0, z: -2, headingDeg: 0));
      await pump();

      expect(cubit.state.registered, isTrue);
      expect(ar.routes, hasLength(1));

      final world = ar.routes.single;
      expect(world, hasLength(6));
      // Anchored where they *set off*, not where they had got to by the time
      // the heading existed — otherwise the whole route slides two metres on.
      expect(world[0], closeTo(0, 1e-6));
      expect(world[1], closeTo(0, 1e-6));
      // 20 m of plan-north from there is 20 m along −z.
      expect(world[2], closeTo(0, 1e-6));
      expect(world[3], closeTo(-20, 1e-6));
      // Then 12 m of plan-east, which is 12 m to the walker's right.
      expect(world[4], closeTo(12, 1e-6));
      expect(world[5], closeTo(-20, 1e-6));

      await cubit.close();
      await guidance.close();
    });

    test('a walker who set off turned has the plan turned to match', () async {
      final (guidance, cubit) = await walkingWithGeometry();

      // Same two metres, but ARCore says they walked off to their right — the
      // phone's world happens to be rotated 90° from the plan's. The route has
      // to come out rotated the same way, or the arrow sends them into a wall.
      ar.emit(standingAt(0, 0));
      await pump();
      ar.emit(walked(x: 2, z: 0, headingDeg: 90));
      await pump();

      final world = ar.routes.single;
      // The far end of the first leg: 20 m along what is now +x.
      expect(world[2], closeTo(20, 1e-6));
      expect(world[3], closeTo(0, 1e-6));
      // And the second leg's 12 m of plan-east is now 12 m of world +z.
      expect(world[4], closeTo(20, 1e-6));
      expect(world[5], closeTo(12, 1e-6));

      await cubit.close();
      await guidance.close();
    });

    test('a walker holding the line is not re-registered', () async {
      final (guidance, cubit) = await walkingWithGeometry();

      ar.emit(standingAt(0, 0));
      await pump();
      ar.emit(walked(x: 0, z: -2, headingDeg: 0));
      await pump();
      for (var i = 0; i < 5; i++) {
        ar.emit(walked(x: 0, z: -3.0 - i, headingDeg: 0, hasRoute: true));
        await pump();
      }

      // Re-solving under somebody who is following the line would move the
      // route out from under them for no reason.
      expect(ar.routes, hasLength(1));
      await cubit.close();
      await guidance.close();
    });

    test('walking a leg off the end of it advances guidance', () async {
      final (guidance, cubit) = await walkingWithGeometry();

      ar.emit(standingAt(0, 0));
      await pump();
      ar.emit(walked(x: 0, z: -2, headingDeg: 0));
      await pump();
      expect(guidance.state.legIndex, 0);

      // The end of the first leg, with no sign read and nobody tapping. Before
      // this advanced by itself, guidance carried on counting the first
      // corridor down the second one and then called an overshoot.
      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          hasRoute: true,
          walkedM: 20,
          cameraX: 0,
          cameraZ: -20,
          travelHeadingDeg: 0,
        ),
      );
      await pump();

      expect(guidance.state.legIndex, 1);
      await cubit.close();
      await guidance.close();
    });

    test('a walker who is nowhere near the line is not advanced', () async {
      final (guidance, cubit) = await walkingWithGeometry();

      ar.emit(standingAt(0, 0));
      await pump();
      ar.emit(walked(x: 0, z: -2, headingDeg: 0));
      await pump();

      // Twenty metres of progress, but eight metres off the corridor it was
      // supposedly made in. Position is exactly the evidence that cannot be
      // trusted here, so the leg waits for a sign.
      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          hasRoute: true,
          walkedM: 20,
          offRouteM: 8,
          cameraX: 8,
          cameraZ: -20,
          travelHeadingDeg: 0,
        ),
      );
      await pump();

      expect(guidance.state.legIndex, 0);
      expect(cubit.state.registrationSuspect, isTrue);
      await cubit.close();
      await guidance.close();
    });

    test('a session with no geometry still gets its leg arrows', () async {
      final (guidance, cubit) = await walking();

      ar.emit(walked(x: 0, z: -2, headingDeg: 0));
      await pump();

      // A recorded-walk route has turns and lengths but no coordinates. There
      // is nothing to register, and the fallback is what the screen always did.
      expect(ar.routes, isEmpty);
      expect(cubit.state.registered, isFalse);
      expect(ar.legs, isNotEmpty);
      await cubit.close();
      await guidance.close();
    });

    test('progress is reported per leg, not along the whole path', () async {
      final (guidance, cubit) = await walkingWithGeometry();

      ar.emit(walked(x: 0, z: -2, headingDeg: 0));
      await pump();

      // 24 m along a path whose first leg ended at 20 m: the walker is 4 m
      // into their second corridor, and guidance has to hear 4, not 24. The
      // leg advances on its own here — the position is measured against a line
      // they are demonstrably on, and waiting for a sign that may not exist
      // would leave the countdown a corridor behind.
      ar.emit(
        const ArGuidanceFrame(
          tracking: CaptureTrackingLike.tracking,
          issue: ArGuidanceIssue.none,
          hasLeg: true,
          hasRoute: true,
          walkedM: 24,
          cameraX: 0,
          cameraZ: -24,
          travelHeadingDeg: 0,
        ),
      );
      await pump();

      expect(guidance.state.legIndex, 1);
      expect(guidance.state.walkedM, closeTo(4, 1e-6));
      await cubit.close();
      await guidance.close();
    });
  });
}
