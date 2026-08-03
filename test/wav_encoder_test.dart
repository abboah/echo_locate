import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/services/audio/wav_encoder.dart';

void main() {
  test('produces a well-formed 44-byte PCM16 mono header', () {
    final pcm = Uint8List.fromList(List.generate(200, (i) => i % 256));
    final wav = wrapPcm16AsWav(pcm, sampleRate: 44100);

    expect(wav.length, 44 + pcm.length);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

    final header = ByteData.sublistView(wav);
    expect(header.getUint32(4, Endian.little), 36 + pcm.length);
    expect(header.getUint32(16, Endian.little), 16); // fmt chunk size
    expect(header.getUint16(20, Endian.little), 1); // PCM
    expect(header.getUint16(22, Endian.little), 1); // mono
    expect(header.getUint32(24, Endian.little), 44100); // sample rate
    expect(header.getUint16(34, Endian.little), 16); // bits per sample
    expect(header.getUint32(40, Endian.little), pcm.length); // data size
  });

  test('data section is a byte-for-byte copy of the PCM input', () {
    final pcm = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final wav = wrapPcm16AsWav(pcm, sampleRate: 16000, numChannels: 1);
    expect(wav.sublist(44), pcm);
  });

  test('byte rate and block align account for channel count', () {
    final pcm = Uint8List.fromList(List.filled(400, 0));
    final wav = wrapPcm16AsWav(pcm, sampleRate: 44100, numChannels: 2);
    final header = ByteData.sublistView(wav);
    expect(header.getUint16(32, Endian.little), 4); // blockAlign = 2ch * 2B
    expect(header.getUint32(28, Endian.little), 44100 * 4); // byteRate
  });
}
