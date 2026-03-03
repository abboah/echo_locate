import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Cross-correlation service for finding time delay between signals
/// Uses FFT-based cross-correlation for efficiency
class CrossCorrelationService {
  /// Computes cross-correlation between signal and template using FFT
  ///
  /// The FFT-based approach:
  /// 1. Zero-pad both signals to the next power of 2 that fits (signal.length + template.length - 1)
  /// 2. Compute FFT of signal → Signal_F
  /// 3. Compute FFT of template → Template_F
  /// 4. Multiply element-wise: Signal_F * conjugate(Template_F)
  /// 5. Compute inverse FFT of the result
  /// 6. Return the real parts as List<double>
  List<double> correlate(List<double> signal, List<double> template) {
    if (signal.isEmpty || template.isEmpty) {
      return [];
    }

    // Calculate the output size: length = signal.length + template.length - 1
    // This is the maximum possible lag distance
    final outputSize = signal.length + template.length - 1;

    // Find the next power of 2 that can fit the output size
    // This is required by FFT algorithms for efficiency
    final fftSize = _nextPowerOf2(outputSize);

    // Create FFT instance with the calculated size
    final fft = FFT(fftSize);

    // Pad signal with zeros to fftSize
    // Zero-padding converts circular convolution to linear convolution
    final paddedSignal = Float64List(fftSize)
      ..setAll(0, signal.map((e) => e).toList());

    // Pad template with zeros to fftSize
    // The template is also zero-padded to match the signal length
    final paddedTemplate = Float64List(fftSize)
      ..setAll(0, template.map((e) => e).toList());

    // Compute FFT of signal → Signal_F
    // This transforms the signal from time domain to frequency domain
    final signalFFT = fft.realFft(paddedSignal);

    // Compute FFT of template → Template_F
    // This transforms the template from time domain to frequency domain
    final templateFFT = fft.realFft(paddedTemplate);

    // Multiply element-wise: Signal_F * conjugate(Template_F)
    // For each frequency bin, multiply by the complex conjugate of the template
    final correlationFFT = _multiplyByConjugate(signalFFT, templateFFT);

    // Compute inverse FFT of the result
    // This transforms the result back from frequency domain to time domain
    final correlationTime = fft.realInverseFft(correlationFFT);

    // Extract and return the real parts as List<double>
    // Return only the valid correlation values (up to outputSize)
    return _extractRealParts(correlationTime, outputSize);
  }

  /// Multiplies fftA by the complex conjugate of fftB element-wise
  ///
  /// FFT results from realFft() are represented as a Float64x2List where each
  /// element is a complex number with .x (real) and .y (imaginary) parts.
  /// Complex multiplication: (a + bi) * (c - di) = (ac + bd) + (bc - ad)i
  Float64x2List _multiplyByConjugate(Float64x2List fftA, Float64x2List fftB) {
    final result = Float64x2List(fftA.length);

    for (int i = 0; i < fftA.length; i++) {
      // Extract complex numbers: A = a + bi, B = c + di
      final a = fftA[i].x;
      final b = fftA[i].y;
      final c = fftB[i].x;
      final d = fftB[i].y;

      // Compute (a + bi) * (c - di) = (ac + bd) + (bc - ad)i
      final realPart = a * c + b * d; // Real part
      final imagPart = b * c - a * d; // Imaginary part
      result[i] = Float64x2(realPart, imagPart);
    }

    return result;
  }

  /// Extracts the real parts from FFT result, limiting to outputSize
  ///
  /// FFT results from inverseRealFft() are stored as Float64List with real values.
  /// We extract the real parts and limit the output to the valid correlation size.
  List<double> _extractRealParts(Float64List fftResult, int outputSize) {
    final realParts = <double>[];

    for (
      int i = 0;
      i < fftResult.length && realParts.length < outputSize;
      i++
    ) {
      realParts.add(fftResult[i]);
    }

    return realParts;
  }

  /// Finds the next power of 2 greater than or equal to n
  ///
  /// FFT algorithms are most efficient when the input size is a power of 2.
  /// This helper finds the smallest power of 2 that can fit the required output size.
  int _nextPowerOf2(int n) {
    if (n <= 1) return 1;
    // Use bit length to find the power of 2
    // If n is already a power of 2, return n
    // Otherwise, return the next power of 2
    int power = 1;
    while (power < n) {
      power <<= 1;
    }
    return power;
  }
}
