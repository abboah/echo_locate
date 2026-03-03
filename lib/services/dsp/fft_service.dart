import 'dart:math';
import 'dart:typed_data';
import 'package:fftea/fftea.dart';

/// FFT (Fast Fourier Transform) service for signal processing
class FFTService {
  /// Computes magnitude spectrum from the input signal
  ///
  /// [signal] - Input time-domain signal as List<double>
  ///
  /// Returns:
  /// - List<double> containing the magnitude of each frequency bin
  /// - Only returns the first half (real spectrum is symmetric for real-valued input)
  ///
  /// Steps:
  /// 1. Compute FFT of the signal
  /// 2. Return the magnitude of each frequency bin (abs of complex number)
  /// 3. Only return the first half (real spectrum is symmetric)
  List<double> computeMagnitudeSpectrum(List<double> signal) {
    if (signal.isEmpty) {
      return [];
    }

    // Find next power of 2 for FFT efficiency
    // FFT algorithms work most efficiently with power-of-2 sizes
    final fftSize = _nextPowerOf2(signal.length);

    // Create FFT instance with calculated size
    final fft = FFT(fftSize);

    // Pad signal with zeros to fftSize
    // This doesn't change the frequency content, just improves FFT efficiency
    final paddedSignal = Float64List(fftSize)
      ..setAll(0, signal.map((e) => e).toList());

    // Compute FFT of the signal
    // This transforms from time domain to frequency domain
    final fftResult = fft.realFft(paddedSignal);

    // Compute magnitude of each frequency bin
    // realFft() returns Float64x2List where each element is a complex number
    // with .x (real) and .y (imaginary) parts
    // Magnitude = sqrt(real² + imag²)
    final magnitudeSpectrum = <double>[];

    for (int i = 0; i < fftResult.length; i++) {
      // Extract real and imaginary parts of this frequency bin
      final real = fftResult[i].x;
      final imag = fftResult[i].y;

      // Calculate magnitude = sqrt(real² + imag²)
      // The magnitude represents the amplitude at this frequency
      final magnitude = sqrt(real * real + imag * imag);
      magnitudeSpectrum.add(magnitude);
    }

    // Only return the first half (real spectrum is symmetric for real-valued input)
    // The second half mirrors the first half, so we only need half the spectrum
    return magnitudeSpectrum.sublist(0, (magnitudeSpectrum.length / 2).ceil());
  }

  /// Finds the dominant frequency in the magnitude spectrum
  ///
  /// [magnitudeSpectrum] - Magnitude spectrum from computeMagnitudeSpectrum()
  /// [sampleRate] - Audio sample rate in Hz
  ///
  /// Returns:
  /// - Dominant frequency in Hz as int
  ///
  /// Steps:
  /// 1. Find the index of the max magnitude
  /// 2. Convert to Hz: frequency = index * sampleRate / (spectrum.length * 2)
  /// 3. Return frequency as int
  int findDominantFrequency(List<double> magnitudeSpectrum, int sampleRate) {
    if (magnitudeSpectrum.isEmpty) {
      return 0;
    }

    // Find the index of the max magnitude
    // This is the frequency bin with the highest energy
    double maxMagnitude = 0;
    int peakIndex = 0;

    for (int i = 0; i < magnitudeSpectrum.length; i++) {
      if (magnitudeSpectrum[i] > maxMagnitude) {
        maxMagnitude = magnitudeSpectrum[i];
        peakIndex = i;
      }
    }

    // Convert to Hz: frequency = index * sampleRate / (spectrum.length * 2)
    // This maps the discrete frequency bin to actual Hz value
    // We multiply spectrum.length by 2 because we only stored half the spectrum
    final frequency = (peakIndex * sampleRate) / (magnitudeSpectrum.length * 2);

    // Return frequency as int
    return frequency.round();
  }

  /// Checks if a chirp is detected in the magnitude spectrum
  ///
  /// [magnitudeSpectrum] - Magnitude spectrum from computeMagnitudeSpectrum()
  /// [startFreq] - Starting frequency of expected chirp in Hz
  /// [endFreq] - Ending frequency of expected chirp in Hz
  /// [sampleRate] - Audio sample rate in Hz
  ///
  /// Returns:
  /// - true if there is significant energy between startFreq and endFreq bins
  /// - true if the average magnitude in that range is > 2x the average magnitude outside
  ///
  /// The chirp detection works by checking if energy is concentrated in the frequency
  /// band where we expect the chirp to be, rather than spread evenly across all frequencies.
  bool isChirpDetected(
    List<double> magnitudeSpectrum,
    double startFreq,
    double endFreq,
    int sampleRate,
  ) {
    if (magnitudeSpectrum.isEmpty) {
      return false;
    }

    // Convert frequency bounds to bin indices
    // binIndex = frequency * spectrumLength / (sampleRate / 2)
    // We divide sampleRate by 2 because we only have half the spectrum
    final startBin = (startFreq * magnitudeSpectrum.length / (sampleRate / 2))
        .toInt();
    final endBin = (endFreq * magnitudeSpectrum.length / (sampleRate / 2))
        .toInt();

    // Clamp to valid range
    final clampedStartBin = startBin.clamp(0, magnitudeSpectrum.length - 1);
    final clampedEndBin = endBin.clamp(0, magnitudeSpectrum.length - 1);

    // Calculate average magnitude in the chirp frequency band
    // This tells us how much energy is in the expected frequency range
    double sumInBand = 0;
    int countInBand = 0;

    for (int i = clampedStartBin; i <= clampedEndBin; i++) {
      sumInBand += magnitudeSpectrum[i];
      countInBand++;
    }

    final avgInBand = countInBand > 0 ? sumInBand / countInBand : 0;

    // Calculate average magnitude outside the chirp band
    // This tells us the background noise/energy level
    double sumOutBand = 0;
    int countOutBand = 0;

    for (int i = 0; i < magnitudeSpectrum.length; i++) {
      if (i < clampedStartBin || i > clampedEndBin) {
        sumOutBand += magnitudeSpectrum[i];
        countOutBand++;
      }
    }

    final avgOutBand = countOutBand > 0 ? sumOutBand / countOutBand : 0;

    // Return true if the average magnitude in the band is > 2x the average outside
    // This means the chirp signal is significantly stronger than noise
    return avgInBand > 2.0 * avgOutBand;
  }

  /// Finds the next power of 2 greater than or equal to n
  int _nextPowerOf2(int n) {
    if (n <= 1) return 1;
    int power = 1;
    while (power < n) {
      power <<= 1;
    }
    return power;
  }
}
