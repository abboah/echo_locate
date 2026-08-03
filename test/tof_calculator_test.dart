import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/services/dsp/chirp_generator.dart';
import 'package:echo_locate/services/dsp/chirp_params.dart';
import 'package:echo_locate/services/dsp/cross_correlation_service.dart';
import 'package:echo_locate/services/dsp/tof_calculator.dart';

void main() {
  const params = ChirpParams();
  final chirp = const ChirpGenerator().generate(params);
  const correlator = CrossCorrelationService();
  // These fixtures place the echo 2d/c after the breakthrough, i.e. they
  // model a phone whose speaker and mic are co-located. The baseline
  // correction is exercised separately, by the test that builds delays the
  // way real geometry produces them.
  const calculator = ToFCalculator(speakerMicBaselineMeters: 0);
  const speedOfSoundMps = 343.0;

  int delaySamplesFor(double distanceMeters) =>
      (2 * distanceMeters / speedOfSoundMps * params.sampleRate).round();

  /// Builds a recording the way a real capture looks: silence/noise, then the
  /// direct speaker-to-mic breakthrough (a near-full-strength chirp copy) at
  /// [breakthroughOffset] — which in the real pipeline lands hundreds of ms
  /// into the buffer, at a run-to-run varying position — then an attenuated
  /// echo [echoDelaySamples] after it.
  Float64List syntheticCapture({
    required int breakthroughOffset,
    int? echoDelaySamples,
    double breakthroughGain = 0.95,
    double echoGain = 0.3,
    double noiseAmplitude = 0.02,
    int trailingSamples = 2000,
    int seed = 42,
  }) {
    final random = math.Random(seed);
    final length = breakthroughOffset +
        (echoDelaySamples ?? 0) +
        chirp.length +
        trailingSamples;
    final received = Float64List(length);
    for (var i = 0; i < length; i++) {
      received[i] = (random.nextDouble() * 2 - 1) * noiseAmplitude;
    }
    for (var i = 0; i < chirp.length; i++) {
      received[breakthroughOffset + i] += chirp[i] * breakthroughGain;
    }
    if (echoDelaySamples != null) {
      for (var i = 0; i < chirp.length; i++) {
        received[breakthroughOffset + echoDelaySamples + i] +=
            chirp[i] * echoGain;
      }
    }
    return received;
  }

  test('recovers a known distance relative to the breakthrough', () {
    const targetDistanceMeters = 1.0;
    final received = syntheticCapture(
      breakthroughOffset: 5000,
      echoDelaySamples: delaySamplesFor(targetDistanceMeters),
    );

    final correlation = correlator.correlate(received, chirp);
    final result = calculator.calculate(
      correlation: correlation,
      sampleRate: params.sampleRate,
    );

    expect(result, isNotNull);
    expect(result!.distanceMeters, closeTo(targetDistanceMeters, 0.02));
    expect(result.peakToNoiseRatio, greaterThan(calculator.noiseGateRatio));
  });

  test('recovers a longer distance too', () {
    const targetDistanceMeters = 3.5;
    final received = syntheticCapture(
      breakthroughOffset: 5000,
      echoDelaySamples: delaySamplesFor(targetDistanceMeters),
    );

    final correlation = correlator.correlate(received, chirp);
    final result = calculator.calculate(
      correlation: correlation,
      sampleRate: params.sampleRate,
    );

    expect(result, isNotNull);
    expect(result!.distanceMeters, closeTo(targetDistanceMeters, 0.02));
  });

  test('distance is unaffected by where the chirp lands in the buffer', () {
    // Regression test for the real on-device bug that made the feature
    // return "no reading" in every test: the echo search was anchored to
    // the buffer's first sample, but recorder warmup + playback latency put
    // the chirp ~740ms into the recording, so the old search window covered
    // only pre-chirp ambient noise and the real echo was never inside it.
    // Anchoring on the breakthrough peak must make the answer independent
    // of capture timing.
    const targetDistanceMeters = 1.0;
    final delay = delaySamplesFor(targetDistanceMeters);

    for (final offset in [800, 12000, 33000]) {
      final received = syntheticCapture(
        breakthroughOffset: offset,
        echoDelaySamples: delay,
        seed: offset,
      );
      final correlation = correlator.correlate(received, chirp);
      final result = calculator.calculate(
        correlation: correlation,
        sampleRate: params.sampleRate,
      );

      expect(result, isNotNull, reason: 'offset $offset');
      expect(
        result!.distanceMeters,
        closeTo(targetDistanceMeters, 0.02),
        reason: 'offset $offset',
      );
    }
  });

  test('noise gate rejects a capture with no echo (breakthrough only)', () {
    final received = syntheticCapture(
      breakthroughOffset: 5000,
      echoDelaySamples: null,
      trailingSamples: delaySamplesFor(calculator.maxRangeMeters) + 3000,
    );

    final correlation = correlator.correlate(received, chirp);
    final result = calculator.calculate(
      correlation: correlation,
      sampleRate: params.sampleRate,
    );

    expect(result, isNull);
  });

  test('noise gate rejects pure noise (no chirp at all)', () {
    final random = math.Random(7);
    final received = Float64List(20000);
    for (var i = 0; i < received.length; i++) {
      received[i] = (random.nextDouble() * 2 - 1) * 0.02;
    }

    final correlation = correlator.correlate(received, chirp);
    final result = calculator.calculate(
      correlation: correlation,
      sampleRate: params.sampleRate,
    );

    expect(result, isNull);
  });

  test('rejects an echo beyond maxRangeMeters even if it is strong', () {
    final received = syntheticCapture(
      breakthroughOffset: 5000,
      echoDelaySamples: delaySamplesFor(50.0), // no indoor surface is this far
      echoGain: 0.9,
    );

    final correlation = correlator.correlate(received, chirp);
    final result = calculator.calculate(
      correlation: correlation,
      sampleRate: params.sampleRate,
    );

    expect(result, isNull);
  });

  test('prefers an in-range echo over a stronger out-of-range one', () {
    const nearDistanceMeters = 1.2;
    final nearDelay = delaySamplesFor(nearDistanceMeters);
    final farDelay = delaySamplesFor(50.0);

    final random = math.Random(3);
    const breakthroughOffset = 5000;
    final received =
        Float64List(breakthroughOffset + farDelay + chirp.length + 500);
    for (var i = 0; i < received.length; i++) {
      received[i] = (random.nextDouble() * 2 - 1) * 0.02;
    }
    for (var i = 0; i < chirp.length; i++) {
      received[breakthroughOffset + i] += chirp[i] * 0.95;
      received[breakthroughOffset + nearDelay + i] += chirp[i] * 0.4;
      received[breakthroughOffset + farDelay + i] += chirp[i] * 0.9;
    }

    final correlation = correlator.correlate(received, chirp);
    final result = calculator.calculate(
      correlation: correlation,
      sampleRate: params.sampleRate,
    );

    expect(result, isNotNull);
    expect(result!.distanceMeters, closeTo(nearDistanceMeters, 0.02));
  });

  test('multi-pulse averaging recovers an echo too weak for one pulse', () {
    // 4 pulses in one recording, echo weak enough that a single pulse's
    // envelope stays below the noise gate, but averaging the four aligned
    // envelopes lowers the floor enough to lift the echo above it.
    const targetDistanceMeters = 2.0;
    final delay = delaySamplesFor(targetDistanceMeters);
    const pulseCount = 4;
    const pulseSpacing = 15000; // samples between pulses, >> max round trip

    final random = math.Random(9);
    final received = Float64List(5000 + pulseCount * pulseSpacing);
    for (var i = 0; i < received.length; i++) {
      received[i] = (random.nextDouble() * 2 - 1) * 0.05;
    }
    for (var p = 0; p < pulseCount; p++) {
      final offset = 3000 + p * pulseSpacing;
      for (var i = 0; i < chirp.length; i++) {
        received[offset + i] += chirp[i] * 0.95;
        received[offset + delay + i] += chirp[i] * 0.06; // very weak echo
      }
    }

    final correlation = correlator.correlate(received, chirp);
    final result = calculator.calculate(
      correlation: correlation,
      sampleRate: params.sampleRate,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacing,
    );

    expect(result, isNotNull);
    expect(result!.distanceMeters, closeTo(targetDistanceMeters, 0.02));
  });

  test('anchors land on every pulse even when a later one is loudest', () {
    // Anchors are derived from the known train spacing, not searched for.
    // The global maximum may belong to any pulse in the train, so the
    // alignment has to work backwards from it — here the third pulse is the
    // loudest, and all four breakthroughs must still be recovered.
    const pulseCount = 4;
    const pulseSpacing = 15000;
    const firstOffset = 3000;

    final random = math.Random(5);
    final received = Float64List(5000 + pulseCount * pulseSpacing);
    for (var i = 0; i < received.length; i++) {
      received[i] = (random.nextDouble() * 2 - 1) * 0.02;
    }
    for (var p = 0; p < pulseCount; p++) {
      final gain = p == 2 ? 0.95 : 0.5;
      final offset = firstOffset + p * pulseSpacing;
      for (var i = 0; i < chirp.length; i++) {
        received[offset + i] += chirp[i] * gain;
      }
    }

    final correlation = correlator.correlate(received, chirp);
    final anchors = calculator.debugAnchors(
      correlation: correlation,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacing,
    );

    // correlate() puts a match starting at sample d at index
    // d + template.length - 1.
    final expected = [
      for (var p = 0; p < pulseCount; p++)
        firstOffset + p * pulseSpacing + chirp.length - 1,
    ];
    expect(anchors, expected);
  });

  test('rejects a peak pinned to the guard edge', () {
    // Built as a correlation array directly rather than by synthesising a
    // recording: a real chirp's autocorrelation sidelobes put local maxima a
    // few samples out, which is what a decaying tail has to be told apart
    // from. Here the envelope after the breakthrough decays monotonically by
    // construction, so its maximum inside the search window can only be the
    // window's first sample — exactly the artifact the rule exists to
    // reject, and what the device produced as repeated readings pinned to
    // the guard distance.
    const anchor = 5000;
    final maxDelay =
        delaySamplesFor(calculator.maxRangeMeters) + 100; // room past range
    final correlation = Float64List(anchor + maxDelay);
    correlation[anchor] = 1000;
    for (var d = 1; d < maxDelay; d++) {
      correlation[anchor + d] = 1000 * math.exp(-d / 40);
    }

    final result = calculator.calculate(
      correlation: correlation,
      sampleRate: params.sampleRate,
    );

    expect(result, isNull);
  });

  test('clutter subtraction exposes a near-field echo buried in ringing', () {
    // The real on-device blocker: a target at 0.15m produces an echo ~38
    // samples after t=0, while the speaker's ringing stays ~13x the noise
    // floor out to ~154 samples. The ringing wins the peak search outright,
    // so without a clutter profile the 0.15m target is invisible.
    const targetDistanceMeters = 0.15;
    final echoDelay = delaySamplesFor(targetDistanceMeters);
    const breakthroughOffset = 5000;
    final ringingLength = delaySamplesFor(0.6);

    /// Breakthrough plus this device's fixed ringing plateau, with an
    /// optional scene echo on top.
    Float64List capture({required bool withTarget, required int seed}) {
      final random = math.Random(seed);
      final received = Float64List(
        breakthroughOffset + delaySamplesFor(calculator.maxRangeMeters) + 3000,
      );
      for (var i = 0; i < received.length; i++) {
        received[i] = (random.nextDouble() * 2 - 1) * 0.01;
      }
      for (var i = 0; i < chirp.length; i++) {
        received[breakthroughOffset + i] += chirp[i] * 0.95;
      }
      // Flat ringing plateau — matches the measured device signature, which
      // does not decay across its span and sits well above any single echo.
      for (var d = 4; d < ringingLength; d += 4) {
        for (var i = 0; i < chirp.length; i++) {
          received[breakthroughOffset + d + i] += chirp[i] * 0.06;
        }
      }
      if (withTarget) {
        for (var i = 0; i < chirp.length; i++) {
          received[breakthroughOffset + echoDelay + i] += chirp[i] * 0.05;
        }
      }
      return received;
    }

    // Reference sweep with nothing in front, then the same device pointed at
    // a target 0.15m away.
    final profile = calculator.buildClutterProfile(
      correlation: correlator.correlate(
        capture(withTarget: false, seed: 1),
        chirp,
      ),
      sampleRate: params.sampleRate,
    );
    expect(profile, isNotNull);

    final measured =
        correlator.correlate(capture(withTarget: true, seed: 2), chirp);

    // A real target at 0.15m is reported at 0.15m.
    final corrected = calculator.calculate(
      correlation: measured,
      sampleRate: params.sampleRate,
      clutterProfile: profile,
    );
    expect(corrected, isNotNull);
    expect(corrected!.distanceMeters, closeTo(targetDistanceMeters, 0.05));

    // ...and empty space stays empty: with the guard down at 0.10m the
    // ringing now sits inside the search window, so subtracting the profile
    // is what keeps it from being reported as an obstacle.
    final suppressed = calculator.calculate(
      correlation:
          correlator.correlate(capture(withTarget: false, seed: 3), chirp),
      sampleRate: params.sampleRate,
      clutterProfile: profile,
    );
    expect(suppressed, isNull);
  });

  test('clutter profile is scaled to the breakthrough, not absolute', () {
    // Playback level drifts between pings, so a profile captured at one
    // amplitude has to still cancel at another. Same scene at half volume
    // must still subtract cleanly.
    const breakthroughOffset = 4000;
    Float64List capture(double gain) {
      final random = math.Random(4);
      final received = Float64List(
        breakthroughOffset + delaySamplesFor(calculator.maxRangeMeters) + 3000,
      );
      for (var i = 0; i < received.length; i++) {
        received[i] = (random.nextDouble() * 2 - 1) * 0.001;
      }
      for (var i = 0; i < chirp.length; i++) {
        received[breakthroughOffset + i] += chirp[i] * gain;
        received[breakthroughOffset + delaySamplesFor(0.3) + i] +=
            chirp[i] * gain * 0.05;
      }
      return received;
    }

    final profile = calculator.buildClutterProfile(
      correlation: correlator.correlate(capture(0.9), chirp),
      sampleRate: params.sampleRate,
    );

    // Same clutter, half the playback level, nothing else in the scene:
    // subtraction should leave no confident echo behind.
    final result = calculator.calculate(
      correlation: correlator.correlate(capture(0.45), chirp),
      sampleRate: params.sampleRate,
      clutterProfile: profile,
    );

    expect(result, isNull);
  });

  test('speaker-mic baseline is added back at every range', () {
    // The breakthrough used as t=0 already travelled the speaker-to-mic
    // baseline, so an uncorrected reading is short by baseline/2 — the same
    // absolute amount at every distance, not a percentage. Verify the
    // correction restores truth near and far, and that it is a pure offset.
    const baseline = 0.074;
    const corrected = ToFCalculator(speakerMicBaselineMeters: baseline);
    const uncorrected = ToFCalculator(speakerMicBaselineMeters: 0);

    for (final trueDistance in [0.15, 1.0, 3.0]) {
      // An echo from `trueDistance` reaches the mic (2d - baseline) after
      // the chirp left the speaker, and the breakthrough anchor sits at
      // `baseline`, so the delay between them is what the calculator sees.
      final delayAfterBreakthrough =
          ((2 * trueDistance - baseline) / 343.0 * params.sampleRate).round();
      final received = syntheticCapture(
        breakthroughOffset: 5000,
        echoDelaySamples: delayAfterBreakthrough,
      );
      final correlation = correlator.correlate(received, chirp);

      final withCorrection = corrected.calculate(
        correlation: correlation,
        sampleRate: params.sampleRate,
      );
      expect(withCorrection, isNotNull, reason: 'at $trueDistance m');
      expect(
        withCorrection!.distanceMeters,
        closeTo(trueDistance, 0.02),
        reason: 'at $trueDistance m',
      );

      final withoutCorrection = uncorrected.calculate(
        correlation: correlation,
        sampleRate: params.sampleRate,
      );
      expect(
        withoutCorrection!.distanceMeters,
        closeTo(trueDistance - baseline / 2, 0.02),
        reason: 'shortfall should be baseline/2 at $trueDistance m',
      );
    }
  });

  test('refuses to build a clutter profile from a noise-only sweep', () {
    // A sweep that never heard its chirp must not become a profile. Every
    // bin is a fraction of the breakthrough, so when the breakthrough is
    // itself noise the result is large, flat and wrong — and subtracting it
    // corrupts every later reading rather than cleaning it. Observed on an
    // Infinix X6855: a peak=0.034 sweep yielded a "signature" reading 0.28
    // at 0.15m and 0.43 at 1.0m, i.e. rising with distance.
    final random = math.Random(77);
    final noise = Float64List(
      5000 + delaySamplesFor(calculator.maxRangeMeters) + 3000,
    );
    for (var i = 0; i < noise.length; i++) {
      noise[i] = (random.nextDouble() * 2 - 1) * 0.01;
    }

    expect(
      calculator.buildClutterProfile(
        correlation: correlator.correlate(noise, chirp),
        sampleRate: params.sampleRate,
      ),
      isNull,
    );
  });

  test('still builds a profile from a sweep that heard its chirp', () {
    // The guard above must not reject good sweeps: a quiet-but-real capture
    // is exactly what calibration is for.
    final received = syntheticCapture(
      breakthroughOffset: 5000,
      echoDelaySamples: delaySamplesFor(1.0),
      breakthroughGain: 0.05, // quiet, but genuinely present
      echoGain: 0.01,
    );

    final profile = calculator.buildClutterProfile(
      correlation: correlator.correlate(received, chirp),
      sampleRate: params.sampleRate,
    );

    expect(profile, isNotNull);
    // Normalised to the breakthrough by construction.
    expect(profile!.first, closeTo(1.0, 1e-9));
  });

  test('empty correlation returns null instead of throwing', () {
    final result = calculator.calculate(
      correlation: Float64List(0),
      sampleRate: params.sampleRate,
    );
    expect(result, isNull);
  });

  group('capture timestamp', () {
    test('the calculator leaves it unset', () {
      // ToFCalculator sees a correlation array and nothing else — only the
      // audio service knows when the sound left the speaker.
      final correlation = correlator.correlate(
        syntheticCapture(
          breakthroughOffset: 30000,
          echoDelaySamples: delaySamplesFor(1.0),
        ),
        chirp,
      );
      final result = calculator.calculate(
        correlation: correlation,
        sampleRate: params.sampleRate,
      );

      expect(result, isNotNull);
      expect(result!.capturedAt, isNull);
    });

    test('at() stamps the reading without disturbing the measurement', () {
      final correlation = correlator.correlate(
        syntheticCapture(
          breakthroughOffset: 30000,
          echoDelaySamples: delaySamplesFor(1.0),
        ),
        chirp,
      );
      final result = calculator.calculate(
        correlation: correlation,
        sampleRate: params.sampleRate,
      )!;
      final timestamp = DateTime(2026, 7, 31, 12, 30);
      final stamped = result.at(timestamp);

      expect(stamped.capturedAt, timestamp);
      expect(stamped.distanceMeters, result.distanceMeters);
      expect(stamped.peakToNoiseRatio, result.peakToNoiseRatio);
    });

    test('two readings alike but for capture time are not equal', () {
      // Equality feeds Bloc state emission: two sweeps that happen to land on
      // the same distance are still distinct measurements, and collapsing
      // them would drop a frame from the fusion record.
      const a = ToFResult(distanceMeters: 1.0, peakToNoiseRatio: 12.0);
      final b = a.at(DateTime(2026, 7, 31, 12, 30));
      final c = a.at(DateTime(2026, 7, 31, 12, 31));

      expect(b, isNot(equals(a)));
      expect(b, isNot(equals(c)));
      expect(b, equals(a.at(DateTime(2026, 7, 31, 12, 30))));
    });
  });
}
