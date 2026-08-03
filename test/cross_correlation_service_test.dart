import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/services/dsp/chirp_generator.dart';
import 'package:echo_locate/services/dsp/cross_correlation_service.dart';

void main() {
  const correlator = CrossCorrelationService();
  final chirp = const ChirpGenerator().generate();

  test('output length is received + template - 1', () {
    final received = Float64List(5000);
    final result = correlator.correlate(received, chirp);
    expect(result.length, received.length + chirp.length - 1);
  });

  test('autocorrelation peaks at zero lag', () {
    final result = correlator.correlate(chirp, chirp);
    // Zero lag sits at index (template.length - 1) per the documented
    // convention in CrossCorrelationService.correlate.
    final zeroLagIndex = chirp.length - 1;
    var peakIndex = 0;
    var peakValue = 0.0;
    for (var i = 0; i < result.length; i++) {
      if (result[i].abs() > peakValue) {
        peakValue = result[i].abs();
        peakIndex = i;
      }
    }
    expect(peakIndex, zeroLagIndex);
  });

  test('peaks at the known offset for a delayed copy', () {
    const delaySamples = 300;
    final received = Float64List(delaySamples + chirp.length + 200);
    for (var i = 0; i < chirp.length; i++) {
      received[delaySamples + i] = chirp[i];
    }

    final result = correlator.correlate(received, chirp);
    final expectedIndex = delaySamples + chirp.length - 1;

    var peakIndex = 0;
    var peakValue = 0.0;
    for (var i = 0; i < result.length; i++) {
      if (result[i].abs() > peakValue) {
        peakValue = result[i].abs();
        peakIndex = i;
      }
    }
    expect(peakIndex, expectedIndex);
  });

  test('empty inputs return an empty result', () {
    expect(correlator.correlate(Float64List(0), chirp), isEmpty);
    expect(correlator.correlate(chirp, Float64List(0)), isEmpty);
  });
}
