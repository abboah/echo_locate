import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/services/dsp/chirp_generator.dart';
import 'package:echo_locate/services/dsp/chirp_params.dart';

void main() {
  const generator = ChirpGenerator();

  test('sample count matches duration * sample rate', () {
    const params = ChirpParams(
      duration: Duration(milliseconds: 40),
      sampleRate: 44100,
    );
    final samples = generator.generate(params);
    expect(samples.length, params.sampleCount);
    expect(samples.length, closeTo(1764, 1));
  });

  test('train places each pulse at an exact multiple of the spacing', () {
    const params = ChirpParams();
    const gapSamples = 6615; // 150ms at 44.1kHz
    final pulse = generator.generate(params);
    final train = generator.generateTrain(
      params,
      pulseCount: 4,
      gapSamples: gapSamples,
    );

    final spacing = pulse.length + gapSamples;
    // 4 pulses, 3 gaps — no trailing silence.
    expect(train.length, 4 * spacing - gapSamples);

    for (var p = 0; p < 4; p++) {
      final offset = p * spacing;
      expect(
        train.sublist(offset, offset + pulse.length),
        pulse,
        reason: 'pulse $p',
      );
      if (p < 3) {
        final gap = train.sublist(offset + pulse.length, offset + spacing);
        expect(gap.every((s) => s == 0), isTrue, reason: 'gap after pulse $p');
      }
    }
  });

  test('a single-pulse train is just the chirp', () {
    const params = ChirpParams();
    expect(
      generator.generateTrain(params, pulseCount: 1, gapSamples: 1000),
      generator.generate(params),
    );
  });

  test('Hann window tapers the sweep to silence at both edges', () {
    final samples = generator.generate();
    expect(samples.first.abs(), lessThan(1e-9));
    expect(samples.last.abs(), lessThan(1e-9));
  });

  test('stays within [-1, 1]', () {
    final samples = generator.generate();
    for (final s in samples) {
      expect(s, inInclusiveRange(-1.0, 1.0));
    }
  });

  test('PCM16 round-trips amplitude within quantisation error', () {
    final samples = generator.generate();
    final bytes = generator.toPcm16Bytes(samples);
    expect(bytes.length, samples.length * 2);

    // Spot-check a mid-sweep sample survives the int16 conversion.
    final mid = samples.length ~/ 2;
    final expected = (samples[mid].clamp(-1.0, 1.0) * 32767).round();
    final lo = bytes[mid * 2];
    final hi = bytes[mid * 2 + 1];
    final actual = (hi << 8 | lo).toSigned(16);
    expect(actual, expected);
  });
}
