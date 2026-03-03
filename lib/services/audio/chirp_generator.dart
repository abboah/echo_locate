import 'dart:math' as math;
import 'dart:typed_data';

/// Generates FMCW (Frequency Modulated Continuous Wave) chirp signals
/// for acoustic distance measurement
class ChirpGenerator {
  static const double _twoPi = 2.0 * math.pi;

  /// Generates a linear FMCW chirp signal with Hanning window
  ///
  /// [sampleRate] - Audio sample rate in Hz
  /// [startFreq] - Starting frequency in Hz
  /// [endFreq] - Ending frequency in Hz
  /// [durationMs] - Duration of the chirp in milliseconds
  ///
  /// Returns a Float32List containing the windowed chirp samples
  Float32List generateChirp({
    required int sampleRate,
    required double startFreq,
    required double endFreq,
    required int durationMs,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final chirp = Float32List(numSamples);
    final duration = durationMs / 1000.0; // Convert to seconds

    // Calculate chirp rate k = (endFreq - startFreq) / duration
    // This represents how fast the frequency changes per second
    final chirpRate = (endFreq - startFreq) / duration;

    // Generate FMCW chirp samples
    for (int i = 0; i < numSamples; i++) {
      // Calculate time for this sample: t = i / sampleRate
      // Time in seconds for this sample index
      final t = i / sampleRate;

      // Calculate instantaneous frequency: f(t) = startFreq + chirpRate * t
      // The frequency increases linearly from startFreq to endFreq
      // (Note: We calculate frequency to compute phase, not used directly)

      // Calculate phase: phase(t) = 2π * (startFreq * t + 0.5 * chirpRate * t²)
      // This is the integral of 2π * f(t) dt
      final phase = _twoPi * (startFreq * t + 0.5 * chirpRate * t * t);

      // Generate sine wave: sample = sin(phase)
      // The sine function produces the actual audio waveform
      chirp[i] = math.sin(phase).toDouble();
    }

    // Apply Hanning window to reduce spectral leakage
    // window[i] = 0.5 * (1 - cos(2π * i / (N-1)))
    // The window smoothly tapers samples at the edges to zero
    _applyHanningWindow(chirp);

    return chirp;
  }

  /// Apply Hanning window to reduce spectral leakage
  ///
  /// The Hanning window smoothly tapers the signal to zero at the edges,
  /// which reduces the spectral leakage caused by abrupt start/stop
  void _applyHanningWindow(Float32List samples) {
    final n = samples.length;
    if (n < 2) return;

    for (int i = 0; i < n; i++) {
      // Calculate window coefficient: 0.5 * (1 - cos(2π * i / (N-1)))
      // This creates a smooth bell curve envelope
      final windowCoeff = 0.5 * (1.0 - math.cos(_twoPi * i / (n - 1)));

      // Apply window: windowed_sample = sample * window[i]
      // Multiply the original sample by the window coefficient
      samples[i] = samples[i] * windowCoeff;
    }
  }
}
