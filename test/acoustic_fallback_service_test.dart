import 'package:echo_locate/services/acoustic/acoustic_fallback_service.dart';
import 'package:echo_locate/services/acoustic/acoustic_range.dart';
import 'package:echo_locate/services/audio/sonar_audio_service.dart';
import 'package:echo_locate/services/dsp/tof_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSonarAudioService extends Mock implements SonarAudioService {}

void main() {
  late _MockSonarAudioService audio;
  late DateTime now;

  DateTime clock() => now;

  setUp(() {
    now = DateTime(2026, 8, 3, 12);
    audio = _MockSonarAudioService();
    when(() => audio.isReady).thenReturn(true);
    when(() => audio.isBusy).thenReturn(false);
    when(() => audio.hasClutterProfile).thenReturn(false);
    when(() => audio.lastCaptureYielded).thenReturn(false);
  });

  AcousticFallbackService service({
    Duration cooldown = const Duration(seconds: 4),
    double floor = 0.6,
  }) =>
      AcousticFallbackService(
        audio,
        cooldown: cooldown,
        uncalibratedFloorMeters: floor,
        clock: clock,
      );

  void whenMeasured(ToFResult? result) {
    when(() => audio.measure(sweeps: any(named: 'sweeps')))
        .thenAnswer((_) async => result);
  }

  ToFResult tof({
    double distance = 2.0,
    double ratio = 19.0,
    DateTime? at,
  }) =>
      ToFResult(
        distanceMeters: distance,
        peakToNoiseRatio: ratio,
        capturedAt: at ?? DateTime(2026, 8, 3, 11, 59, 58),
      );

  group('a measured range', () {
    test('carries distance, confidence and its emission time', () async {
      final emittedAt = DateTime(2026, 8, 3, 11, 59, 55);
      whenMeasured(tof(distance: 2.4, ratio: 19.0, at: emittedAt));

      final result = await service().rangeAhead();

      expect(result.succeeded, isTrue);
      expect(result.range!.distanceMeters, 2.4);
      // Emission time, not "now": a measurement takes seconds, and this is
      // what pairs the range with the depth frame it stands in for.
      expect(result.range!.capturedAt, emittedAt);
      expect(result.range!.confidence, closeTo(0.5, 0.01));
      expect(result.range!.calibrated, isFalse);
    });

    test('confidence spans the gate to saturation, and cannot leave 0..1',
        () async {
      whenMeasured(tof(ratio: 8.0)); // the acceptance gate itself
      expect((await service().rangeAhead()).range!.confidence, 0.0);

      whenMeasured(tof(ratio: 200.0)); // far past saturation
      now = now.add(const Duration(minutes: 1));
      expect((await service().rangeAhead()).range!.confidence, 1.0);
    });

    test('reports calibration state, since it sets the usable near range',
        () async {
      when(() => audio.hasClutterProfile).thenReturn(true);
      whenMeasured(tof(distance: 0.2));

      final result = await service().rangeAhead();

      expect(result.range!.calibrated, isTrue);
      expect(result.range!.distanceMeters, 0.2,
          reason: 'a clutter profile is what makes the near field readable');
    });
  });

  group('refusals', () {
    test('a near reading without calibration is refused as ringing', () async {
      // The phone hearing its own speaker. Reporting it would hand the fusion
      // layer a confident wall 20cm ahead that is really the handset.
      whenMeasured(tof(distance: 0.2));

      final result = await service().rangeAhead();

      expect(result.refusal, RangeRefusal.belowUncalibratedFloor);
    });

    test('silence is reported as no echo — evidence about the scene',
        () async {
      whenMeasured(null);

      expect(
        (await service().rangeAhead()).refusal,
        RangeRefusal.noEcho,
      );
    });

    test('audio taken by speech is NOT reported as no echo', () async {
      // The distinction the whole refusal vocabulary exists for. "Nothing came
      // back" would tell the caller empty air was confirmed, when in truth the
      // measurement never happened.
      whenMeasured(null);
      when(() => audio.lastCaptureYielded).thenReturn(true);

      expect(
        (await service().rangeAhead()).refusal,
        RangeRefusal.audioBusy,
      );
    });

    test('an unstarted audio service refuses rather than pretending', () async {
      when(() => audio.isReady).thenReturn(false);

      expect(
        (await service().rangeAhead()).refusal,
        RangeRefusal.audioUnavailable,
      );
      verifyNever(() => audio.measure(sweeps: any(named: 'sweeps')));
    });

    test('a capture already in flight is refused', () async {
      when(() => audio.isBusy).thenReturn(true);

      expect(
        (await service().rangeAhead()).refusal,
        RangeRefusal.audioBusy,
      );
      verifyNever(() => audio.measure(sweeps: any(named: 'sweeps')));
    });
  });

  group('throttle', () {
    test('a camera failing every frame does not chirp every frame', () async {
      // The reason this service owns a rate limit: depth fails for a duration,
      // so the trigger fires ~30x a second against a measurement taking
      // seconds. Thirty queued sweeps would hold the speaker continuously.
      whenMeasured(tof());
      final fallback = service(cooldown: const Duration(seconds: 4));

      expect((await fallback.rangeAhead()).succeeded, isTrue);
      for (var i = 0; i < 30; i++) {
        expect((await fallback.rangeAhead()).refusal, RangeRefusal.throttled);
      }

      verify(() => audio.measure(sweeps: any(named: 'sweeps'))).called(1);
    });

    test('lifts once the cooldown has passed', () async {
      whenMeasured(tof());
      final fallback = service(cooldown: const Duration(seconds: 4));

      await fallback.rangeAhead();
      now = now.add(const Duration(seconds: 5));

      expect(fallback.isThrottled, isFalse);
      expect((await fallback.rangeAhead()).succeeded, isTrue);
    });

    test('is announced, so a caller can skip the call it would refuse',
        () async {
      whenMeasured(tof());
      final fallback = service();

      expect(fallback.isThrottled, isFalse);
      await fallback.rangeAhead();
      expect(fallback.isThrottled, isTrue);
    });

    test('counts from the START of a measurement, not its end', () async {
      // Measuring takes seconds. Stamping on completion would let the next
      // request through the instant this one returned, which is the burst the
      // cooldown exists to prevent.
      whenMeasured(tof());
      final fallback = service(cooldown: const Duration(seconds: 4));

      when(() => audio.measure(sweeps: any(named: 'sweeps')))
          .thenAnswer((_) async {
        now = now.add(const Duration(seconds: 5)); // the sweep's own duration
        return tof();
      });

      await fallback.rangeAhead();

      expect(fallback.isThrottled, isFalse,
          reason: 'the measurement itself outlasted the cooldown');
      // And a second measurement that returns instantly must then re-arm it.
      whenMeasured(tof());
      await fallback.rangeAhead();
      expect(fallback.isThrottled, isTrue);
    });

    test('a refused measurement still counts, so failures cannot loop',
        () async {
      // A room that returns no echo returns no echo every time. Without this,
      // a silent scene would chirp continuously.
      whenMeasured(null);
      final fallback = service();

      expect((await fallback.rangeAhead()).refusal, RangeRefusal.noEcho);
      expect((await fallback.rangeAhead()).refusal, RangeRefusal.throttled);
    });
  });
}
