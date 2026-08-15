import 'dart:math' as math;
import 'dart:typed_data';

import 'chirp_params.dart';

/// Generates the linear FMCW (up-sweep) chirp used both as the emitted
/// sonar pulse and as the matched-filter template in
/// [CrossCorrelationService].
class ChirpGenerator {
  const ChirpGenerator();

  /// Samples in [-1, 1], Hann-windowed so the sweep starts and ends at zero
  /// amplitude — an un-windowed chirp clicks at its edges, and that click's
  /// broadband energy leaks into every correlation lag and masks the echo.
  Float64List generate([ChirpParams params = const ChirpParams()]) {
    final n = params.sampleCount;
    final samples = Float64List(n);
    final sweepRate =
        (params.endFrequencyHz - params.startFrequencyHz) /
        params.durationSeconds;

    for (var i = 0; i < n; i++) {
      final t = i / params.sampleRate;
      // Instantaneous phase of a linear chirp is the integral of
      // instantaneous frequency f(t) = f0 + sweepRate * t.
      final phase =
          2 * math.pi * (params.startFrequencyHz * t + 0.5 * sweepRate * t * t);
      final window = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      samples[i] = math.sin(phase) * window;
    }
    return samples;
  }

  /// [pulseCount] copies of the chirp separated by [gapSamples] of silence,
  /// as ONE buffer.
  ///
  /// Emitting a train as a single sound is what makes multi-pulse averaging
  /// possible: the spacing is then sample-accurate, so the breakthroughs sit
  /// at exactly known offsets from each other and [ToFCalculator] can derive
  /// them instead of hunting for them. Firing N separate plays does not work
  /// — on-device (Infinix X657C) four `SoLoud.play()` calls in a loop landed
  /// only two audible chirps in the recording, 905ms apart rather than the
  /// requested 340ms, so the "anchors" for the other two were just noise.
  ///
  /// [gapSamples] must exceed the round-trip time at
  /// [ToFCalculator.maxRangeMeters], or one pulse's echoes overlap the next
  /// pulse's breakthrough.
  Float64List generateTrain(
    ChirpParams params, {
    required int pulseCount,
    required int gapSamples,
  }) {
    final pulse = generate(params);
    if (pulseCount <= 1) return pulse;

    final spacing = pulse.length + gapSamples;
    // No trailing gap — the capture window covers the last pulse's echoes.
    final samples = Float64List(pulseCount * spacing - gapSamples);
    for (var p = 0; p < pulseCount; p++) {
      final offset = p * spacing;
      for (var i = 0; i < pulse.length; i++) {
        samples[offset + i] = pulse[i];
      }
    }
    return samples;
  }

  /// 16-bit little-endian PCM bytes, for handing the chirp to an audio
  /// playback engine.
  Uint8List toPcm16Bytes(Float64List samples) {
    final bytes = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      bytes.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
