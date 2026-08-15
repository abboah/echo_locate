import 'dart:async';

import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/route_draft.dart';
import 'package:echo_locate/features/capture/bloc/capture_bloc.dart';
import 'package:echo_locate/features/routing/route_repository.dart';
import 'package:echo_locate/services/motion/step_service.dart';
import 'package:echo_locate/services/motion/stride_profile.dart';
import 'package:echo_locate/services/sensing/detection_service.dart';
import 'package:echo_locate/services/sensing/text_recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDetection extends Mock implements DetectionService {}

class _MockTextRecognition extends Mock implements TextRecognitionService {}

class _MockSteps extends Mock implements StepService {}

class _MockRoutes extends Mock implements RouteRepository {}

class _FakeDraft extends Fake implements RouteDraft {}

void main() {
  late _MockDetection detection;
  late _MockTextRecognition ocr;
  late _MockSteps steps;
  late _MockRoutes routes;
  late StreamController<List<String>> readStream;
  late StreamController<int> stepStream;

  setUpAll(() => registerFallbackValue(_FakeDraft()));

  setUp(() {
    detection = _MockDetection();
    ocr = _MockTextRecognition();
    steps = _MockSteps();
    routes = _MockRoutes();
    readStream = StreamController<List<String>>.broadcast();
    stepStream = StreamController<int>.broadcast();

    when(() => detection.start()).thenAnswer((_) async => true);
    when(() => detection.stop()).thenAnswer((_) async {});
    when(() => ocr.reads).thenAnswer((_) => readStream.stream);
    when(() => ocr.start()).thenAnswer((_) {});
    when(() => ocr.stop()).thenAnswer((_) async {});
    when(() => steps.start()).thenAnswer((_) async => true);
    when(() => steps.stop()).thenAnswer((_) async {});
    when(() => steps.reset()).thenAnswer((_) {});
    when(() => steps.steps).thenAnswer((_) => stepStream.stream);
    when(() => routes.saveRoute(any())).thenAnswer((_) async => 'route-9');
  });

  const stride = StrideProfile(metres: 0.5, source: StrideSource.calibrated);

  Landmark known(String id, String label, String name) => Landmark(
    id: id,
    buildingId: 'knust-library',
    floorId: 'floor-g',
    kind: LandmarkKind.sign,
    labelText: label,
    displayName: name,
  );

  Future<void> pump() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<CaptureBloc> started({
    bool stepCounter = true,
    List<Landmark> knownLandmarks = const [],
  }) async {
    when(() => steps.start()).thenAnswer((_) async => stepCounter);
    final bloc = CaptureBloc(
      detection: detection,
      textRecognition: ocr,
      steps: steps,
      routes: routes,
    );
    bloc.add(
      CaptureStarted(
        buildingId: 'knust-library',
        floorId: 'floor-g',
        stride: stride,
        knownLandmarks: knownLandmarks,
      ),
    );
    await pump();
    return bloc;
  }

  /// Records the opening landmark, then walks [walkedSteps} and sights the
  /// next one — the loop the contributor repeats down a corridor.
  Future<void> walkTo(
    CaptureBloc bloc,
    String name, {
    int walkedSteps = 24,
    LandmarkKind kind = LandmarkKind.sign,
  }) async {
    stepStream.add(walkedSteps);
    await pump();
    bloc.add(
      CaptureLandmarkAccepted(
        labelText: name.toUpperCase(),
        displayName: name,
        kind: kind,
      ),
    );
    await pump();
  }

  group('sighting', () {
    test('what the camera reads becomes a proposal', () async {
      final bloc = await started();

      readStream.add(['Help Desk', 'Opening hours 9-5']);
      await pump();

      expect(
        bloc.state.proposals.map((p) => p.text),
        containsAll(['Help Desk', 'Opening hours 9-5']),
      );
      await bloc.close();
    });

    test('the same sign read twice is proposed once', () async {
      final bloc = await started();

      readStream.add(['Help Desk']);
      await pump();
      readStream.add(['help desk']);
      await pump();

      expect(bloc.state.proposals, hasLength(1));
      await bloc.close();
    });

    test('a read that matches a recorded landmark proposes its name', () async {
      final bloc = await started(
        knownLandmarks: [known('lm-desk', 'HELP DESK', 'Help desk')],
      );

      readStream.add(['HELP DESK']);
      await pump();

      // Matching an existing landmark matters: the upload keys landmarks on
      // display_name, so reusing the recorded spelling merges them instead of
      // creating a second one in the same spot.
      expect(bloc.state.proposals.single.existing?.displayName, 'Help desk');
      await bloc.close();
    });
  });

  group('capturing legs', () {
    test(
      'the opening landmark starts the walk with a zeroed counter',
      () async {
        final bloc = await started();

        bloc.add(
          const CaptureLandmarkAccepted(
            labelText: 'KNUST LIBRARY',
            displayName: 'Main entrance',
            kind: LandmarkKind.entrance,
          ),
        );
        await pump();

        expect(bloc.state.status, CaptureStatus.walking);
        expect(bloc.state.landmarks, hasLength(1));
        expect(bloc.state.landmarks.single.ref, 'L1');
        verify(() => steps.reset()).called(greaterThanOrEqualTo(1));
        await bloc.close();
      },
    );

    test('sighting the next landmark asks how the leg went', () async {
      final bloc = await started();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'KNUST LIBRARY',
          displayName: 'Main entrance',
          kind: LandmarkKind.entrance,
        ),
      );
      await pump();

      await walkTo(bloc, 'Help desk', walkedSteps: 24);

      expect(bloc.state.status, CaptureStatus.describing);
      expect(bloc.state.pendingLandmark?.displayName, 'Help desk');
      // The count is frozen at the sighting: the contributor stands still
      // typing the instruction, and those steps are not part of the leg.
      expect(bloc.state.pendingSteps, 24);
      await bloc.close();
    });

    test(
      'a described leg is stored in metres, with the count as evidence',
      () async {
        final bloc = await started();
        bloc.add(
          const CaptureLandmarkAccepted(
            labelText: 'KNUST LIBRARY',
            displayName: 'Main entrance',
            kind: LandmarkKind.entrance,
          ),
        );
        await pump();
        await walkTo(bloc, 'Help desk', walkedSteps: 24);

        bloc.add(
          const CaptureLegDescribed(
            turnDeg: 0,
            instruction: 'Straight ahead, past the entrance desk',
          ),
        );
        await pump();

        final step = bloc.state.steps.single;
        // 24 steps at half a metre. Metres are canonical (spec §4): a user with
        // a different stride must not inherit this contributor's count.
        expect(step.distanceM, closeTo(12, 0.001));
        expect(step.stepsRecorded, 24);
        expect(step.fromRef, 'L1');
        expect(step.toRef, 'L2');
        expect(bloc.state.status, CaptureStatus.walking);
        await bloc.close();
      },
    );

    test('the turn the contributor tapped is what gets stored', () async {
      final bloc = await started();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'A',
          displayName: 'Start',
          kind: LandmarkKind.entrance,
        ),
      );
      await pump();
      await walkTo(bloc, 'Stairwell', kind: LandmarkKind.stairs);

      bloc.add(
        const CaptureLegDescribed(turnDeg: 90, instruction: 'Turn right'),
      );
      await pump();

      expect(bloc.state.steps.single.turnDeg, 90);
      await bloc.close();
    });

    test(
      'with no step counter the contributor supplies the distance',
      () async {
        final bloc = await started(stepCounter: false);
        bloc.add(
          const CaptureLandmarkAccepted(
            labelText: 'A',
            displayName: 'Start',
            kind: LandmarkKind.entrance,
          ),
        );
        await pump();
        bloc.add(
          const CaptureLandmarkAccepted(
            labelText: 'B',
            displayName: 'Help desk',
            kind: LandmarkKind.sign,
          ),
        );
        await pump();

        bloc.add(
          const CaptureLegDescribed(
            turnDeg: 0,
            instruction: 'Straight on',
            distanceM: 15,
          ),
        );
        await pump();

        expect(bloc.state.stepCounting, isFalse);
        expect(bloc.state.steps.single.distanceM, 15);
        expect(bloc.state.steps.single.stepsRecorded, isNull);
        await bloc.close();
      },
    );

    test('a leg the counter did not measure asks for the distance', () async {
      // Found on the emulator: its step counter never ticks, so the leg was
      // saved as 0 m and the map collapsed to a single point. A counter that
      // reports nothing — phone in a bag, broken sensor, wheelchair — must not
      // silently produce a zero-length corridor.
      final bloc = await started();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'A',
          displayName: 'Start',
          kind: LandmarkKind.entrance,
        ),
      );
      await pump();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'B',
          displayName: 'Help desk',
          kind: LandmarkKind.sign,
        ),
      );
      await pump();

      expect(bloc.state.pendingSteps, 0);
      expect(bloc.state.needsManualDistance, isTrue);
      await bloc.close();
    });

    test('a measured leg does not ask for the distance', () async {
      final bloc = await started();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'A',
          displayName: 'Start',
          kind: LandmarkKind.entrance,
        ),
      );
      await pump();
      await walkTo(bloc, 'Help desk', walkedSteps: 24);

      expect(bloc.state.needsManualDistance, isFalse);
      await bloc.close();
    });

    test('an unmeasured leg cannot be saved as zero metres', () async {
      final bloc = await started();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'A',
          displayName: 'Start',
          kind: LandmarkKind.entrance,
        ),
      );
      await pump();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'B',
          displayName: 'Help desk',
          kind: LandmarkKind.sign,
        ),
      );
      await pump();

      bloc.add(const CaptureLegDescribed(turnDeg: 0, instruction: 'On'));
      await pump();

      // Still describing: the leg was refused, not silently stored at 0 m.
      expect(bloc.state.status, CaptureStatus.describing);
      expect(bloc.state.steps, isEmpty);
      expect(bloc.state.error, isNotNull);

      bloc.add(
        const CaptureLegDescribed(turnDeg: 0, instruction: 'On', distanceM: 15),
      );
      await pump();

      expect(bloc.state.steps.single.distanceM, 15);
      await bloc.close();
    });

    test('legs are numbered in walking order', () async {
      final bloc = await started();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'A',
          displayName: 'Start',
          kind: LandmarkKind.entrance,
        ),
      );
      await pump();

      await walkTo(bloc, 'Help desk');
      bloc.add(const CaptureLegDescribed(turnDeg: 0, instruction: 'One'));
      await pump();
      await walkTo(bloc, 'Reading Hall');
      bloc.add(const CaptureLegDescribed(turnDeg: 90, instruction: 'Two'));
      await pump();

      expect(bloc.state.steps.map((s) => s.seq), [1, 2]);
      expect(bloc.state.steps.map((s) => s.fromRef), ['L1', 'L2']);
      expect(bloc.state.landmarks.map((l) => l.ref), ['L1', 'L2', 'L3']);
      await bloc.close();
    });
  });

  group('uploading', () {
    Future<CaptureBloc> withOneLeg() async {
      final bloc = await started();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'KNUST LIBRARY',
          displayName: 'Main entrance',
          kind: LandmarkKind.entrance,
        ),
      );
      await pump();
      await walkTo(bloc, 'Reading Hall', kind: LandmarkKind.door);
      bloc.add(
        const CaptureLegDescribed(turnDeg: 0, instruction: 'Straight ahead'),
      );
      await pump();
      return bloc;
    }

    test('the whole capture goes up in one call', () async {
      final bloc = await withOneLeg();

      bloc.add(const CaptureFinished(destinationRoomId: 'room-1'));
      await pump();

      final draft =
          verify(() => routes.saveRoute(captureAny())).captured.single
              as RouteDraft;
      expect(draft.buildingId, 'knust-library');
      expect(draft.destinationRoomId, 'room-1');
      expect(draft.landmarks, hasLength(2));
      expect(draft.steps, hasLength(1));
      expect(bloc.state.status, CaptureStatus.saved);
      expect(bloc.state.savedRouteId, 'route-9');
      await bloc.close();
    });

    test(
      'the destination landmark is tied to the room it opens onto',
      () async {
        final bloc = await withOneLeg();

        bloc.add(const CaptureFinished(destinationRoomId: 'room-1'));
        await pump();

        final draft =
            verify(() => routes.saveRoute(captureAny())).captured.single
                as RouteDraft;
        expect(draft.landmarks.last.roomId, 'room-1');
        await bloc.close();
      },
    );

    test('a failed upload keeps the capture so it can be retried', () async {
      when(() => routes.saveRoute(any())).thenThrow(Exception('offline'));
      final bloc = await withOneLeg();

      bloc.add(const CaptureFinished(destinationRoomId: 'room-1'));
      await pump();

      expect(bloc.state.status, CaptureStatus.failed);
      expect(bloc.state.error, isNotNull);
      // Twenty minutes of walking must survive a dropped connection.
      expect(bloc.state.steps, hasLength(1));
      expect(bloc.state.landmarks, hasLength(2));

      when(() => routes.saveRoute(any())).thenAnswer((_) async => 'route-9');
      bloc.add(const CaptureFinished(destinationRoomId: 'room-1'));
      await pump();

      expect(bloc.state.status, CaptureStatus.saved);
      await bloc.close();
    });

    test('a capture with no legs is refused', () async {
      final bloc = await started();
      bloc.add(
        const CaptureLandmarkAccepted(
          labelText: 'A',
          displayName: 'Start',
          kind: LandmarkKind.entrance,
        ),
      );
      await pump();

      bloc.add(const CaptureFinished(destinationRoomId: 'room-1'));
      await pump();

      verifyNever(() => routes.saveRoute(any()));
      expect(bloc.state.error, isNotNull);
      await bloc.close();
    });
  });

  test('closing releases the camera and the counter', () async {
    final bloc = await started();

    await bloc.close();

    verify(() => detection.stop()).called(1);
    verify(() => ocr.stop()).called(1);
    verify(() => steps.stop()).called(1);
  });
}
