import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/services/acoustic/reverb_analyzer.dart';

void main() {
  const analyzer = ReverbAnalyzer();
  const sampleRate = 44100;

  /// A synthetic room impulse response with an exactly known RT60.
  ///
  /// A room's response is well modelled as noise inside an exponentially
  /// decaying envelope. For amplitude `exp(-t/tau)` the energy goes as
  /// `exp(-2t/tau)`, so the level in dB is `-20t/(tau*ln10)`, and reaching
  /// -60dB takes `t = 3*tau*ln10 = 6.908*tau`. Inverting that gives the tau
  /// which produces any RT60 asked for — which is what makes this a real
  /// test of the estimator rather than a restatement of it.
  Float64List syntheticDecay({
    required double rt60Seconds,
    double durationSeconds = 2.0,
    double noiseFloor = 0.0,
    int seed = 7,
  }) {
    final random = math.Random(seed);
    final tau = rt60Seconds / (3 * math.ln10);
    final length = (durationSeconds * sampleRate).round();
    final response = Float64List(length);
    for (var i = 0; i < length; i++) {
      final t = i / sampleRate;
      final envelope = math.exp(-t / tau);
      response[i] = (random.nextDouble() * 2 - 1) * envelope +
          (random.nextDouble() * 2 - 1) * noiseFloor;
    }
    return response;
  }

  group('RT60 recovery', () {
    for (final trueRt60 in [0.35, 0.8, 1.6]) {
      test('recovers a known RT60 of ${trueRt60}s', () {
        final features = analyzer.analyze(
          impulseResponse: syntheticDecay(rt60Seconds: trueRt60),
          sampleRate: sampleRate,
        );

        expect(features, isNotNull);
        // 5% is comfortably tighter than the spread between the room classes
        // this feeds (corridor vs small room vs hall).
        expect(
          features!.rt60Seconds,
          closeTo(trueRt60, trueRt60 * 0.05),
          reason: 'estimated ${features.rt60Seconds}',
        );
        expect(features.fitQuality, greaterThan(0.98));
        expect(features.isReliable, isTrue);
      });
    }

    test('is unaffected by overall loudness', () {
      // RT60 is a rate, not a level: the same room measured quietly must give
      // the same answer. Scaling the response tests exactly that.
      final quiet = syntheticDecay(rt60Seconds: 0.8);
      final loud = Float64List.fromList(quiet.map((s) => s * 50).toList());

      final a = analyzer.analyze(impulseResponse: quiet, sampleRate: sampleRate);
      final b = analyzer.analyze(impulseResponse: loud, sampleRate: sampleRate);

      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(b!.rt60Seconds, closeTo(a!.rt60Seconds, 1e-9));
    });

    test('integrates from the direct sound, not the buffer start', () {
      // A real capture has silence before the impulse arrives. Counting that
      // as part of the decay would stretch the estimate.
      const rt60 = 0.8;
      final decay = syntheticDecay(rt60Seconds: rt60);
      final delayed = Float64List(decay.length + sampleRate ~/ 2)
        ..setRange(sampleRate ~/ 2, sampleRate ~/ 2 + decay.length, decay);

      final features =
          analyzer.analyze(impulseResponse: delayed, sampleRate: sampleRate);

      expect(features, isNotNull);
      expect(features!.rt60Seconds, closeTo(rt60, rt60 * 0.05));
    });
  });

  group('refuses to guess', () {
    test('returns null for pure noise', () {
      final random = math.Random(3);
      final noise = Float64List(sampleRate);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = random.nextDouble() * 2 - 1;
      }

      final features =
          analyzer.analyze(impulseResponse: noise, sampleRate: sampleRate);

      // Noise has no sustained decay, so either nothing is fitted or the fit
      // is visibly untrustworthy. Both are acceptable; a confident wrong
      // answer is not.
      expect(features == null || !features.isReliable, isTrue);
    });

    test('returns null for silence', () {
      expect(
        analyzer.analyze(
          impulseResponse: Float64List(sampleRate),
          sampleRate: sampleRate,
        ),
        isNull,
      );
    });

    test('returns null for an empty response', () {
      expect(
        analyzer.analyze(
          impulseResponse: Float64List(0),
          sampleRate: sampleRate,
        ),
        isNull,
      );
    });

    test('returns null when the capture is too short to hold a decay', () {
      // 20ms of a 1.5s reverb never falls far enough to fit.
      final features = analyzer.analyze(
        impulseResponse:
            syntheticDecay(rt60Seconds: 1.5, durationSeconds: 0.02),
        sampleRate: sampleRate,
      );

      expect(features, isNull);
    });
  });

  group('early vs late decay', () {
    test('separates a corridor-like early decay from its late decay', () {
      // A corridor's strong parallel reflections make its early decay much
      // faster than its late decay; a diffuse room decays at one rate. The
      // EDT/RT60 ratio captures that, and is a discriminator neither value
      // provides alone. Built here as a fast decay that crosses over into a
      // slow one.
      const fastRt60 = 0.25;
      const slowRt60 = 1.4;
      final random = math.Random(11);
      const fastTau = fastRt60 / (3 * math.ln10);
      const slowTau = slowRt60 / (3 * math.ln10);
      const length = 2 * sampleRate;
      final response = Float64List(length);
      for (var i = 0; i < length; i++) {
        final t = i / sampleRate;
        // Sum of two decays: the fast one dominates early, the slow one
        // survives to dominate late.
        final envelope =
            math.exp(-t / fastTau) + 0.05 * math.exp(-t / slowTau);
        response[i] = (random.nextDouble() * 2 - 1) * envelope;
      }

      final features =
          analyzer.analyze(impulseResponse: response, sampleRate: sampleRate);

      expect(features, isNotNull);
      expect(
        features!.earlyDecayTimeSeconds,
        lessThan(features.rt60Seconds),
        reason: 'early decay should outrun the late tail: $features',
      );
    });

    test('early and late agree in a uniformly decaying space', () {
      final features = analyzer.analyze(
        impulseResponse: syntheticDecay(rt60Seconds: 0.9),
        sampleRate: sampleRate,
      );

      expect(features, isNotNull);
      expect(
        features!.earlyDecayTimeSeconds,
        closeTo(features.rt60Seconds, features.rt60Seconds * 0.15),
      );
    });
  });
}
