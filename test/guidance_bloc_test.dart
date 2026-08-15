import 'dart:async';

import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/core/models/walk_route.dart';
import 'package:echo_locate/features/guidance/bloc/guidance_bloc.dart';
import 'package:echo_locate/features/guidance/guidance_session.dart';
import 'package:echo_locate/services/audio/audio_arbiter.dart';
import 'package:echo_locate/services/haptics/haptic_service.dart';
import 'package:echo_locate/services/mapping/floor_graph.dart';
import 'package:echo_locate/services/mapping/route_planner.dart';
import 'package:echo_locate/services/motion/step_service.dart';
import 'package:echo_locate/services/motion/stride_profile.dart';
import 'package:echo_locate/services/sensing/detected_obstacle.dart';
import 'package:echo_locate/services/sensing/detection_service.dart';
import 'package:echo_locate/services/sensing/text_recognition_service.dart';
import 'package:echo_locate/services/speech/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDetection extends Mock implements DetectionService {}

class _MockTextRecognition extends Mock implements TextRecognitionService {}

class _MockSteps extends Mock implements StepService {}

class _MockSpeech extends Mock implements SpeechService {}

class _MockHaptics extends Mock implements HapticService {}

/// Everything guidance says, in order, with the priority it claimed.
class _Spoken {
  _Spoken(this.text, this.use);
  final String text;
  final AudioUse? use;
}

void main() {
  late _MockDetection detection;
  late _MockTextRecognition ocr;
  late _MockSteps steps;
  late _MockSpeech speech;
  late _MockHaptics haptics;
  late StreamController<List<DetectedObstacle>> obstacleStream;
  late StreamController<List<String>> readStream;
  late StreamController<int> stepStream;
  late List<_Spoken> spoken;

  setUpAll(() => registerFallbackValue(AudioUse.speech));

  setUp(() {
    detection = _MockDetection();
    ocr = _MockTextRecognition();
    steps = _MockSteps();
    speech = _MockSpeech();
    haptics = _MockHaptics();
    obstacleStream = StreamController<List<DetectedObstacle>>.broadcast();
    readStream = StreamController<List<String>>.broadcast();
    stepStream = StreamController<int>.broadcast();
    spoken = [];

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
    when(() => haptics.alert()).thenAnswer((_) async {});
    when(() => haptics.confirm()).thenAnswer((_) async {});
    when(
      () => speech.speak(
        any(),
        interrupt: any(named: 'interrupt'),
        use: any(named: 'use'),
      ),
    ).thenAnswer((invocation) async {
      spoken.add(
        _Spoken(
          invocation.positionalArguments.first as String,
          invocation.namedArguments[#use] as AudioUse?,
        ),
      );
    });
  });

  Landmark landmark(
    String id, {
    String? label,
    LandmarkKind kind = LandmarkKind.sign,
    String? name,
  }) => Landmark(
    id: id,
    buildingId: 'b1',
    floorId: 'f1',
    kind: kind,
    labelText: label ?? id.toUpperCase(),
    displayName: name ?? id,
  );

  WalkRoute recorded(List<RouteStep> legs) => WalkRoute(
    id: 'r1',
    buildingId: 'b1',
    startLandmarkId: legs.first.fromLandmarkId,
    destinationRoomId: 'room',
    steps: legs,
  );

  RouteStep leg(
    int seq,
    String from,
    String to, {
    double distanceM = 20,
    String? instruction,
  }) => RouteStep(
    seq: seq,
    fromLandmarkId: from,
    toLandmarkId: to,
    instruction: instruction ?? 'walk to $to',
    distanceM: distanceM,
  );

  /// A two-leg walk: entrance → desk → hall, 20m each.
  GuidanceSession sessionOf({
    List<Landmark>? landmarks,
    FloorGraph? graph,
    bool metric = true,
    StrideProfile stride = const StrideProfile(
      metres: 0.5,
      source: StrideSource.calibrated,
    ),
  }) => GuidanceSession(
    plan: PlannedRoute.fromRecorded(
      recorded([
        leg(1, 'entrance', 'desk', instruction: 'Straight past the desk'),
        leg(2, 'desk', 'hall', instruction: 'Turn right to the hall'),
      ]),
    ),
    landmarks:
        landmarks ??
        [
          landmark('entrance', name: 'Main entrance'),
          landmark('desk', label: 'HELP DESK', name: 'Help desk'),
          landmark('hall', label: 'READING HALL', name: 'Reading Hall'),
        ],
    destinationName: 'Reading Hall',
    stride: stride,
    graph: graph,
    metric: metric,
  );

  GuidanceBloc blocOf() => GuidanceBloc(
    detection: detection,
    textRecognition: ocr,
    steps: steps,
    speech: speech,
    haptics: haptics,
  );

  Future<void> pump() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<GuidanceBloc> started({
    GuidanceSession? session,
    bool stepCounter = true,
    bool camera = true,
  }) async {
    when(() => steps.start()).thenAnswer((_) async => stepCounter);
    when(() => detection.start()).thenAnswer((_) async => camera);
    final bloc = blocOf();
    bloc.add(GuidanceStarted(session ?? sessionOf()));
    await pump();
    return bloc;
  }

  String allSpoken() => spoken.map((s) => s.text).join(' || ');

  group('starting a route', () {
    test(
      'the first leg is spoken with the instruction and a step count',
      () async {
        final bloc = await started();

        expect(bloc.state.status, GuidanceStatus.guiding);
        // 20m at half a metre per step.
        expect(bloc.state.expectedSteps, 40);
        expect(allSpoken(), contains('Straight past the desk'));
        expect(allSpoken(), contains('40 steps'));
        await bloc.close();
      },
    );

    test(
      'without a step counter the route runs on sign reading alone',
      () async {
        final bloc = await started(stepCounter: false);

        expect(bloc.state.status, GuidanceStatus.guiding);
        expect(bloc.state.stepCounting, isFalse);
        // Promising a step count the phone cannot verify is worse than silence.
        expect(allSpoken(), isNot(contains('steps')));
        expect(allSpoken(), contains('Help desk'));
        await bloc.close();
      },
    );

    test(
      'without a camera guidance says so and offers manual confirmation',
      () async {
        final bloc = await started(camera: false);

        expect(bloc.state.signReading, isFalse);
        expect(bloc.state.status, GuidanceStatus.guiding);
        await bloc.close();
      },
    );

    test('a leg nobody recorded is given neutral wording', () async {
      final session = GuidanceSession(
        plan: const PlannedRoute(
          legs: [
            PlannedLeg(
              fromLandmarkId: 'hall',
              toLandmarkId: 'desk',
              distanceM: 10,
            ),
          ],
          synthesised: true,
        ),
        landmarks: [
          landmark('desk', label: 'HELP DESK', name: 'Help desk'),
          landmark('hall', label: 'READING HALL', name: 'Reading Hall'),
        ],
        destinationName: 'Help desk',
      );

      final bloc = await started(session: session);

      expect(allSpoken(), contains('Help desk'));
      await bloc.close();
    });
  });

  group('walking a leg', () {
    test('halfway is announced once', () async {
      final bloc = await started();
      spoken.clear();

      stepStream.add(20);
      await pump();
      stepStream.add(21);
      await pump();

      expect(
        spoken.where((s) => s.text.toLowerCase().contains('halfway')),
        hasLength(1),
      );
      expect(bloc.state.stepsThisLeg, 21);
      await bloc.close();
    });

    test('nearing the landmark prompts a sweep for the sign', () async {
      final bloc = await started();
      spoken.clear();

      stepStream.add(33);
      await pump();

      expect(allSpoken().toLowerCase(), contains('sweep'));
      await bloc.close();
    });

    test('progress updates claim the progress priority', () async {
      final bloc = await started();
      spoken.clear();

      stepStream.add(20);
      await pump();

      expect(spoken.single.use, AudioUse.guidanceProgress);
      await bloc.close();
    });
  });

  group('confirming a landmark', () {
    test(
      'reading the sign advances the leg however few steps were counted',
      () async {
        final bloc = await started();
        stepStream.add(3);
        await pump();
        spoken.clear();

        readStream.add(['HELP DESK']);
        await pump();

        expect(bloc.state.legIndex, 1);
        expect(bloc.state.stepsThisLeg, 0);
        verify(() => steps.reset()).called(greaterThanOrEqualTo(1));
        expect(allSpoken(), contains('Help desk'));
        expect(allSpoken(), contains('Turn right to the hall'));
        await bloc.close();
      },
    );

    test(
      'the confirmation and the next instruction are said in one breath',
      () async {
        // Found on the emulator: said as two utterances, the second was refused
        // by the arbiter ("landmarkReached cannot pre-empt landmarkReached") and
        // the user heard "Help desk." followed by silence — no idea where to
        // walk next. They have to be one utterance, not two.
        final bloc = await started();
        spoken.clear();

        readStream.add(['HELP DESK']);
        await pump();

        expect(
          spoken.where(
            (s) =>
                s.text.contains('Help desk') &&
                s.text.contains('Turn right to the hall'),
          ),
          hasLength(1),
        );
        await bloc.close();
      },
    );

    test('arrival is announced in one breath too', () async {
      final bloc = await started();
      readStream.add(['HELP DESK']);
      await pump();
      spoken.clear();

      readStream.add(['READING HALL']);
      await pump();

      expect(
        spoken.where(
          (s) => s.text.contains('Reading Hall') && s.text.contains('arrived'),
        ),
        hasLength(1),
      );
      await bloc.close();
    });

    test('the confirmation is spoken at landmark priority and felt', () async {
      final bloc = await started();
      spoken.clear();

      readStream.add(['HELP DESK']);
      await pump();

      expect(spoken.first.use, AudioUse.landmarkReached);
      verify(() => haptics.confirm()).called(1);
      await bloc.close();
    });

    test('a sign for somewhere else does not advance the leg', () async {
      final bloc = await started();

      readStream.add(['READING HALL']);
      await pump();

      expect(bloc.state.legIndex, 0);
      await bloc.close();
    });

    test('an OCR misread of the expected sign still counts', () async {
      final bloc = await started(
        session: sessionOf(
          landmarks: [
            landmark('entrance', name: 'Main entrance'),
            landmark('desk', label: '204', name: 'Room 204'),
            landmark('hall', label: 'READING HALL', name: 'Reading Hall'),
          ],
        ),
      );

      // '2O4' — the letter O for zero, the classic plate misread.
      readStream.add(['2O4']);
      await pump();

      expect(bloc.state.legIndex, 1);
      await bloc.close();
    });

    test('the last landmark ends the route', () async {
      final bloc = await started();
      readStream.add(['HELP DESK']);
      await pump();
      spoken.clear();

      readStream.add(['READING HALL']);
      await pump();

      expect(bloc.state.status, GuidanceStatus.arrived);
      expect(allSpoken().toLowerCase(), contains('arrived'));
      await bloc.close();
    });

    test(
      'a landmark can be confirmed by hand when there is no camera',
      () async {
        final bloc = await started(camera: false);

        bloc.add(const GuidanceLandmarkConfirmed());
        await pump();

        expect(bloc.state.legIndex, 1);
        await bloc.close();
      },
    );
  });

  group('stairs', () {
    test(
      'a leg into a stairwell is guided by the sign, not the count',
      () async {
        final session = GuidanceSession(
          plan: PlannedRoute.fromRecorded(
            recorded([leg(1, 'entrance', 'stairs', distanceM: 20)]),
          ),
          landmarks: [
            landmark('entrance', name: 'Main entrance'),
            landmark(
              'stairs',
              kind: LandmarkKind.stairs,
              name: 'Ground floor stairwell',
            ),
          ],
          destinationName: 'Ground floor stairwell',
        );

        final bloc = await started(session: session);
        spoken.clear();

        // A pedometer does not measure climbing, so no count is promised and
        // overshooting one cannot trigger a recovery sweep.
        stepStream.add(60);
        await pump();

        expect(bloc.state.status, GuidanceStatus.guiding);
        expect(spoken, isEmpty);
        await bloc.close();
      },
    );
  });

  group('obstacles', () {
    test('an urgent obstacle interrupts and buzzes', () async {
      final bloc = await started();
      spoken.clear();

      obstacleStream.add([
        const DetectedObstacle(
          label: 'furniture',
          confidence: 0.9,
          heightFraction: 0.8,
          position: ObstaclePosition.center,
        ),
      ]);
      await pump();

      expect(spoken.single.use, AudioUse.urgentSpeech);
      verify(() => haptics.alert()).called(1);
      expect(bloc.state.callout, isNotNull);
      await bloc.close();
    });

    test(
      'a routine obstacle is the lowest-priority thing guidance says',
      () async {
        final bloc = await started();
        spoken.clear();

        obstacleStream.add([
          const DetectedObstacle(
            label: 'furniture',
            confidence: 0.9,
            heightFraction: 0.35,
            position: ObstaclePosition.left,
          ),
        ]);
        await pump();

        expect(spoken.single.use, AudioUse.speech);
        verifyNever(() => haptics.alert());
        await bloc.close();
      },
    );
  });

  group('recovery', () {
    test(
      'walking well past the expected count starts a recovery sweep',
      () async {
        final bloc = await started();
        spoken.clear();

        stepStream.add(49); // 122% of 40
        await pump();

        expect(bloc.state.status, GuidanceStatus.recovering);
        expect(allSpoken().toLowerCase(), contains('sweep'));
        await bloc.close();
      },
    );

    test('a sign further along the route relocalises and re-guides', () async {
      final bloc = await started();
      stepStream.add(49);
      await pump();
      spoken.clear();

      // They walked straight past the help desk and reached the hall door.
      readStream.add(['READING HALL']);
      await pump();

      expect(bloc.state.status, GuidanceStatus.arrived);
      await bloc.close();
    });

    test(
      'a sign off the route replans from where the user actually is',
      () async {
        // The building graph knows a way from the lift to the hall that this
        // user's route never used.
        final graph = FloorGraph.merge([
          recorded([leg(1, 'entrance', 'desk'), leg(2, 'desk', 'hall')]),
          recorded([
            leg(1, 'lift', 'desk', instruction: 'Left out of the lift'),
          ]),
        ]);
        final session = sessionOf(
          graph: graph,
          landmarks: [
            landmark('entrance', name: 'Main entrance'),
            landmark('desk', label: 'HELP DESK', name: 'Help desk'),
            landmark('hall', label: 'READING HALL', name: 'Reading Hall'),
            landmark(
              'lift',
              label: 'LIFT',
              kind: LandmarkKind.lift,
              name: 'Lift',
            ),
          ],
        );
        final bloc = await started(session: session);

        bloc.add(const GuidanceLostReported());
        await pump();
        spoken.clear();
        readStream.add(['LIFT']);
        await pump();

        expect(bloc.state.status, GuidanceStatus.guiding);
        expect(bloc.state.plan.landmarkIds, ['lift', 'desk', 'hall']);
        expect(allSpoken(), contains('Lift'));
        // The re-route and the first instruction of it, said together.
        expect(
          spoken.where(
            (s) => s.text.contains('Lift') && s.text.contains('Left out of'),
          ),
          hasLength(1),
        );
        await bloc.close();
      },
    );

    test(
      'with nowhere to relocalise, guidance asks the user to ask a person',
      () async {
        final bloc = await started();

        bloc.add(const GuidanceLostReported());
        await pump();
        spoken.clear();
        bloc.add(const GuidanceLostReported());
        await pump();

        expect(bloc.state.askForHelp, isTrue);
        expect(allSpoken(), contains('Reading Hall'));
        expect(allSpoken().toLowerCase(), contains('ask'));
        await bloc.close();
      },
    );

    test('a landmark off the route with no graph asks for help', () async {
      final bloc = await started(
        session: sessionOf(
          landmarks: [
            landmark('entrance', name: 'Main entrance'),
            landmark('desk', label: 'HELP DESK', name: 'Help desk'),
            landmark('hall', label: 'READING HALL', name: 'Reading Hall'),
            landmark('cafe', label: 'CAFE', name: 'Cafeteria'),
          ],
        ),
      );

      bloc.add(const GuidanceLostReported());
      await pump();
      readStream.add(['CAFE']);
      await pump();

      expect(bloc.state.askForHelp, isTrue);
      expect(allSpoken(), contains('Cafeteria'));
      await bloc.close();
    });
  });

  group('voice', () {
    test('muting silences guidance', () async {
      final bloc = await started();
      bloc.add(const GuidanceVoiceToggled());
      await pump();
      spoken.clear();

      readStream.add(['HELP DESK']);
      await pump();

      expect(bloc.state.voiceOn, isFalse);
      expect(spoken, isEmpty);
      // The leg still advances — the screen and the haptics still work.
      expect(bloc.state.legIndex, 1);
      await bloc.close();
    });
  });

  test(
    'ending the route releases the camera, the counter and the voice',
    () async {
      final bloc = await started();

      await bloc.close();

      verify(() => detection.stop()).called(1);
      verify(() => ocr.stop()).called(1);
      verify(() => steps.stop()).called(1);
      verify(() => speech.stop()).called(1);
    },
  );

  test(
    'a route over a plan nobody measured is never spoken in steps',
    () async {
      final bloc = blocOf();
      bloc.add(GuidanceStarted(sessionOf(metric: false)));
      await pump();

      // The lengths route correctly — A* only compares them with each other —
      // but they are plan units, not metres. Converting one into "about twenty
      // steps" would put a confidently wrong number in a blind user's ear, so
      // the leg is carried by landmark confirmation instead.
      expect(bloc.state.expectedSteps, 0);
      expect(bloc.state.countsThisLeg, isFalse);
      verifyNever(
        () => speech.speak(
          any(that: contains('steps')),
          interrupt: any(named: 'interrupt'),
          use: any(named: 'use'),
        ),
      );
      await bloc.close();
    },
  );

  group('sentence punctuation', () {
    // Found on a phone: a traced plan's edges carry generated instructions
    // that are already whole sentences, and the leg sentence appends its own
    // punctuation on top — "Continue to the door.. Look for Main corridor."
    test('a recorded instruction is stripped before wording is added on', () {
      expect(
        GuidanceBloc.unpunctuated('Continue to the door.'),
        'Continue to the door',
      );
      expect(GuidanceBloc.unpunctuated('past the lifts'), 'past the lifts');
      expect(GuidanceBloc.unpunctuated('turn right, '), 'turn right');
    });

    test('a string that is nothing but punctuation is left alone', () {
      // Stripping it to empty would leave a leg with no sentence at all,
      // which is worse than an odd-looking one.
      expect(GuidanceBloc.unpunctuated('...'), '...');
      expect(GuidanceBloc.unpunctuated(''), '');
    });
  });
}
