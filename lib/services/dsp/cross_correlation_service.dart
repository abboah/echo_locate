import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Matched filtering: finds where [template] (the emitted chirp) sits
/// inside [received] (the recorded echo) via FFT-based cross-correlation.
class CrossCorrelationService {
  const CrossCorrelationService();

  /// Cross-correlation of `received` against `template`.
  ///
  /// Returned array has length `received.length + template.length - 1`.
  /// `result[k]` is the correlation at lag `k - (template.length - 1)`
  /// samples — i.e. the array index of a perfect match starting at sample
  /// `d` of `received` is `d + template.length - 1`. [ToFCalculator] reads
  /// the peak against this same convention.
  ///
  /// Cross-correlation(x, h) is convolution(x, reverse(h)) shifted by
  /// `template.length - 1`, which lets this reuse fftea's own
  /// `circularConvolution` instead of hand-rolling the FFT conjugate-multiply
  /// (and its lag-sign bookkeeping) from scratch. Passing the exact linear
  /// length (`received.length + template.length - 1`) as the circular size
  /// is the minimum needed to avoid wraparound aliasing, so the circular and
  /// linear results are identical.
  Float64List correlate(List<double> received, List<double> template) {
    if (received.isEmpty || template.isEmpty) return Float64List(0);

    final reversedTemplate = Float64List(template.length);
    for (var i = 0; i < template.length; i++) {
      reversedTemplate[i] = template[template.length - 1 - i];
    }

    final fullLength = received.length + template.length - 1;
    return circularConvolution(received, reversedTemplate, fullLength);
  }
}
