// TEMPORARY calibration diagnostic — not part of the app.
// Usage: dart run tool/analyze_wav.dart <path-to-wav> [--marker=<distanceMeters>]
//
// Parses a 16-bit PCM mono WAV, runs a coarse STFT, and prints the
// dominant frequency per time window so we can see by eye whether a
// 2->8kHz upward chirp sweep is actually present in a recording, and
// where in time it sits.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/analyze_wav.dart <path-to-wav>');
    exit(1);
  }

  final bytes = File(args[0]).readAsBytesSync();
  final header = ByteData.sublistView(bytes);
  final sampleRate = header.getUint32(24, Endian.little);
  final bitsPerSample = header.getUint16(34, Endian.little);
  final numChannels = header.getUint16(22, Endian.little);
  final dataSize = header.getUint32(40, Endian.little);
  print(
    'File: ${args[0]}\n'
    'sampleRate=$sampleRate bitsPerSample=$bitsPerSample '
    'channels=$numChannels dataBytes=$dataSize',
  );

  final sampleCount = dataSize ~/ 2;
  final samples = Float64List(sampleCount);
  final data = ByteData.sublistView(bytes, 44, 44 + dataSize);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }

  const windowSize = 1024;
  const hop = 256;
  final fft = FFT(windowSize);
  final window = <String>[];

  for (var start = 0; start + windowSize <= samples.length; start += hop) {
    final chunk = Float64List.sublistView(samples, start, start + windowSize);
    // Hann window to reduce spectral leakage.
    final windowed = Float64List(windowSize);
    for (var i = 0; i < windowSize; i++) {
      final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (windowSize - 1));
      windowed[i] = chunk[i] * w;
    }
    final spectrum = fft.realFft(windowed);
    final mags = spectrum.discardConjugates().magnitudes();

    var bestBin = 0;
    var bestMag = 0.0;
    // Only look at bins covering ~500Hz-12kHz, skip DC/near-DC.
    final minBin = (500 * windowSize / sampleRate).round();
    final maxBin = (12000 * windowSize / sampleRate).round();
    for (var b = minBin; b < maxBin && b < mags.length; b++) {
      if (mags[b] > bestMag) {
        bestMag = mags[b];
        bestBin = b;
      }
    }
    final freqHz = bestBin * sampleRate / windowSize;
    final timeMs = start * 1000 / sampleRate;
    window.add(
      't=${timeMs.toStringAsFixed(1).padLeft(7)}ms  '
      'dominant=${freqHz.toStringAsFixed(0).padLeft(5)}Hz  '
      'mag=${bestMag.toStringAsFixed(2)}',
    );
  }

  for (final line in window) {
    print(line);
  }
}
