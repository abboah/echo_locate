import 'dart:typed_data';

/// Generates FMCW (Frequency Modulated Continuous Wave) chirp signals
/// for acoustic distance measurement
class ChirpGenerator {
  /// Generates a linear FMCW chirp signal
  ///
  /// [sampleRate] - Audio sample rate in Hz
  /// [startFreq] - Starting frequency in Hz
  /// [endFreq] - Ending frequency in Hz
  /// [durationMs] - Duration of the chirp in milliseconds
  ///
  /// Returns a Float32List containing the chirp samples
  ///
  /// The FMCW chirp formula used:
  /// f(t) = f_start + (f_end - f_start) * t / duration
  /// signal(t) = sin(2 * PI * integral(f(t) dt))
  Float32List generateChirp({
    required int sampleRate,
    required double startFreq,
    required double endFreq,
    required int durationMs,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final chirp = Float32List(numSamples);

    final frequencySweep = endFreq - startFreq;
    final phaseIncrement = 2 * 3.14159265358979323846 / sampleRate;

    double currentPhase = 0;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Linear frequency modulation: f(t) = f_start + (f_end - f_start) * t / duration
      final currentFreq = startFreq + frequencySweep * t / (durationMs / 1000);
      // Integrate frequency to get phase: phase(t) = 2*PI * integral(f(t) dt)
      currentPhase += currentFreq * phaseIncrement;
      // Generate the chirp signal
      chirp[i] = (currentPhase).clamp(-1.0, 1.0).toDouble();
    }

    // Normalize the output to -1.0 to 1.0 range
    double maxVal = 0;
    for (int i = 0; i < numSamples; i++) {
      if (chirp[i].abs() > maxVal) {
        maxVal = chirp[i].abs();
      }
    }
    if (maxVal > 0) {
      for (int i = 0; i < numSamples; i++) {
        chirp[i] = chirp[i] / maxVal;
      }
    }

    return chirp;
  }

  /// Alternative simple sine wave generation for testing
  Float32List generateSimpleTone({
    required int sampleRate,
    required double frequency,
    required int durationMs,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final tone = Float32List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      tone[i] = (2 * 3.14159265358979323846 * frequency * t)
          .clamp(-1.0, 1.0)
          .toDouble();
    }

    return tone;
  }
}
