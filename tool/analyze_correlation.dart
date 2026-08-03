// TEMPORARY calibration diagnostic — not part of the app.
// Usage: dart run tool/analyze_correlation.dart <path-to-received-wav>
//
// Runs the app's own matched filter over a dumped sonar recording, anchors
// t=0 on the direct-breakthrough peak exactly like ToFCalculator, then
// prints the correlation envelope per distance bin so the speaker's ringing
// tail and any real echo bump can be seen by eye.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:echo_locate/services/dsp/chirp_generator.dart';
import 'package:echo_locate/services/dsp/chirp_params.dart';
import 'package:echo_locate/services/dsp/cross_correlation_service.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/analyze_correlation.dart <wav>');
    exit(1);
  }

  final bytes = File(args[0]).readAsBytesSync();
  final header = ByteData.sublistView(bytes);
  final sampleRate = header.getUint32(24, Endian.little);
  final dataSize = header.getUint32(40, Endian.little);
  final sampleCount = dataSize ~/ 2;
  final data = ByteData.sublistView(bytes, 44, 44 + dataSize);
  final received = Float64List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    received[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }

  const params = ChirpParams();
  final chirp = const ChirpGenerator().generate(params);
  final correlation =
      const CrossCorrelationService().correlate(received, chirp);

  const c = 343.0;
  const maxMeters = 6.0;
  final maxDelay = (2 * maxMeters / c * sampleRate).round();

  var pulses = 1;
  var exclusionMs = 0.0;
  for (final a in args) {
    if (a.startsWith('--pulses=')) pulses = int.parse(a.split('=')[1]);
    if (a.startsWith('--exclusion-ms=')) {
      exclusionMs = double.parse(a.split('=')[1]);
    }
  }
  final exclusion = exclusionMs > 0
      ? (exclusionMs / 1000 * sampleRate).round()
      : maxDelay;

  // Same multi-anchor selection as ToFCalculator: iteratively take the
  // global max and mask +/- maxDelay around it.
  final magnitudes = Float64List(correlation.length);
  for (var i = 0; i < correlation.length; i++) {
    magnitudes[i] = correlation[i].abs();
  }
  final anchors = <int>[];
  final anchorPeaks = <double>[];
  for (var p = 0; p < pulses; p++) {
    var bestIndex = -1;
    var bestValue = 0.0;
    for (var i = 0; i < magnitudes.length; i++) {
      if (magnitudes[i] > bestValue) {
        bestValue = magnitudes[i];
        bestIndex = i;
      }
    }
    if (bestIndex < 0 || bestValue == 0) break;
    anchors.add(bestIndex);
    anchorPeaks.add(bestValue);
    final s = math.max(0, bestIndex - exclusion);
    final e = math.min(magnitudes.length, bestIndex + exclusion + 1);
    for (var i = s; i < e; i++) {
      magnitudes[i] = 0;
    }
  }

  print('sampleRate=$sampleRate samples=$sampleCount pulses=${anchors.length}');
  for (var i = 0; i < anchors.length; i++) {
    print('  anchor[$i] index=${anchors[i]} '
        '(${(anchors[i] * 1000 / sampleRate).toStringAsFixed(1)}ms) '
        'peak=${anchorPeaks[i].toStringAsFixed(1)}');
  }

  // Pulse-averaged envelope, aligned per anchor (matches ToFCalculator).
  final envelope = Float64List(maxDelay + 1);
  for (var d = 0; d <= maxDelay; d++) {
    var sum = 0.0;
    var n = 0;
    for (final anchor in anchors) {
      final i = anchor + d;
      if (i >= correlation.length) continue;
      sum += correlation[i].abs();
      n++;
    }
    envelope[d] = n == 0 ? 0 : sum / n;
  }

  // Noise floor estimated by median of the far half of the window, which
  // no plausible indoor echo dominates.
  final far = envelope.sublist(envelope.length ~/ 2)..sort();
  final medianFloor = far[far.length ~/ 2];
  final anchorValue = anchorPeaks.isEmpty ? 1.0 : anchorPeaks[0];

  print('');
  print('median far-field floor = ${medianFloor.toStringAsExponential(2)}');
  print('distance-binned pulse-averaged envelope '
      '(max per 10cm bin; xFloor = multiples of median floor):');

  const binMeters = 0.10;
  final binSamples = (2 * binMeters / c * sampleRate).round();
  final bins = (maxMeters / binMeters).round();
  for (var b = 0; b < bins; b++) {
    final start = b * binSamples;
    final end = math.min(envelope.length, start + binSamples);
    if (start >= envelope.length) break;
    var peak = 0.0;
    for (var i = start; i < end; i++) {
      if (envelope[i] > peak) peak = envelope[i];
    }
    final xFloor = peak / medianFloor;
    final rel = peak / anchorValue;
    final bar = '#' * math.min(60, (xFloor * 3).round());
    print('${(b * binMeters).toStringAsFixed(2).padLeft(5)}-'
        '${((b + 1) * binMeters).toStringAsFixed(2).padLeft(4)}m  '
        'rel=${rel.toStringAsFixed(4)}  '
        'xFloor=${xFloor.toStringAsFixed(1).padLeft(5)}  $bar');
  }
}
