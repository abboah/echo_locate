import 'package:echo_locate/features/acoustic/bloc/acoustic_bloc.dart';
import 'package:echo_locate/services/acoustic/reverb_features.dart';
import 'package:echo_locate/services/acoustic/reverb_measurement.dart';
import 'package:echo_locate/services/acoustic/room_classification.dart';
import 'package:echo_locate/services/audio/sonar_audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSonarAudioService extends Mock implements SonarAudioService {}

void main() {
  late _MockSonarAudioService audio;

  setUp(() {
    audio = _MockSonarAudioService();
    when(() => audio.start()).thenAnswer((_) async => true);
  });

  ReverbFeatures features({
    required double rt60,
    double? edt,
    double fitQuality = 0.99,
    double decayRangeDb = 20.0,
  }) => ReverbFeatures(
    rt60Seconds: rt60,
    earlyDecayTimeSeconds: edt ?? rt60,
    fitQuality: fitQuality,
    decayRangeDb: decayRangeDb,
  );

  /// Drives one measurement to completion and returns the resulting bloc.
  Future<AcousticBloc> measured() async {
    final bloc = AcousticBloc(audio);
    bloc.add(const AcousticStarted());
    await Future<void>.delayed(Duration.zero);
    bloc.add(const AcousticMeasureRequested());
    await Future<void>.delayed(Duration.zero);
    return bloc;
  }

  test('unavailable mic leaves the feature disabled', () async {
    when(() => audio.start()).thenAnswer((_) async => false);
    final bloc = AcousticBloc(audio);

    bloc.add(const AcousticStarted());
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.status, AcousticStatus.unavailable);
    await bloc.close();
  });

  test('a measured decay is classified and held', () async {
    when(
      () => audio.measureReverb(),
    ).thenAnswer((_) async => ReverbMeasurement.measured(features(rt60: 1.8)));

    final bloc = await measured();

    expect(bloc.state.status, AcousticStatus.idle);
    expect(bloc.state.lastClassification?.type, RoomType.hall);
    expect(bloc.state.error, isNull);
    await bloc.close();
  });

  test(
    'an unmeasurable room reports why, and keeps no false verdict',
    () async {
      when(() => audio.measureReverb()).thenAnswer(
        (_) async =>
            const ReverbMeasurement.failed(ReverbFailure.noMeasurableDecay),
      );

      final bloc = await measured();

      expect(bloc.state.lastClassification?.type, RoomType.unknown);
      expect(bloc.state.error, isNotNull);
      await bloc.close();
    },
  );

  test('a measurement lost to a spoken callout says so, and does not blame '
      'the room', () async {
    // The joint camera+audio failure mode. Reporting this as "no measurable
    // reverberation" would send a tester looking for an acoustics problem
    // when the fix is to stop talking and press the button again.
    when(() => audio.measureReverb()).thenAnswer(
      (_) async => const ReverbMeasurement.failed(ReverbFailure.interrupted),
    );

    final bloc = await measured();

    expect(bloc.state.error, contains('interrupted'));
    expect(bloc.state.lastClassification?.type, RoomType.unknown);
    expect(
      bloc.state.features,
      isNull,
      reason: 'an abandoned capture yields no acoustics to show',
    );
    await bloc.close();
  });

  test('a busy microphone is reported as busy, not as a dead room', () async {
    when(() => audio.measureReverb()).thenAnswer(
      (_) async => const ReverbMeasurement.failed(ReverbFailure.audioBusy),
    );

    final bloc = await measured();

    expect(bloc.state.error, contains('busy'));
    await bloc.close();
  });

  test('the evidence survives an unknown verdict', () async {
    // An ambiguous but genuine measurement: the numbers explain the refusal,
    // so the screen can show them rather than a bare "unknown".
    when(
      () => audio.measureReverb(),
    ).thenAnswer((_) async => ReverbMeasurement.measured(features(rt60: 0.9)));

    final bloc = await measured();

    expect(bloc.state.lastClassification?.type, RoomType.unknown);
    expect(bloc.state.features, isNotNull);
    expect(bloc.state.features!.rt60Seconds, 0.9);
    await bloc.close();
  });

  test('a second measurement is refused while one is running', () async {
    var calls = 0;
    when(() => audio.measureReverb()).thenAnswer((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return ReverbMeasurement.measured(features(rt60: 0.4));
    });
    final bloc = AcousticBloc(audio);

    bloc.add(const AcousticStarted());
    await Future<void>.delayed(Duration.zero);
    bloc.add(const AcousticMeasureRequested());
    bloc.add(const AcousticMeasureRequested());
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // The speaker and mic can only serve one capture at a time; the second
    // request is dropped rather than queued behind the first.
    expect(calls, 1);
    await bloc.close();
  });
}
