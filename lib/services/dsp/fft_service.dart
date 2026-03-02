import 'dart:typed_data';

/// FFT (Fast Fourier Transform) service for signal processing
class FFTService {
  // TODO: Implement FFT using fftea package

  /// Performs FFT on the input signal
  /// Returns the magnitude spectrum
  Float32List performFFT(List<double> signal) {
    // TODO: Implement FFT using fftea
    // This is a placeholder that returns the input as-is
    return Float32List.fromList(signal.map((e) => e.toDouble()).toList());
  }

  /// Performs inverse FFT to convert frequency domain back to time domain
  Float32List performInverseFFT(List<double> frequencyData) {
    // TODO: Implement inverse FFT
    return Float32List.fromList(
      frequencyData.map((e) => e.toDouble()).toList(),
    );
  }

  /// Computes the magnitude spectrum from complex FFT output
  List<double> computeMagnitude(List<double> real, List<double> imag) {
    // TODO: Compute magnitude = sqrt(real^2 + imag^2)
    final magnitude = <double>[];
    for (int i = 0; i < real.length; i++) {
      magnitude.add((real[i] * real[i] + imag[i] * imag[i]));
    }
    return magnitude;
  }

  /// Finds the peak frequency index in the spectrum
  int findPeakFrequency(List<double> magnitude) {
    // TODO: Find the index of the maximum magnitude
    double maxVal = 0;
    int maxIndex = 0;
    for (int i = 0; i < magnitude.length; i++) {
      if (magnitude[i] > maxVal) {
        maxVal = magnitude[i];
        maxIndex = i;
      }
    }
    return maxIndex;
  }
}
