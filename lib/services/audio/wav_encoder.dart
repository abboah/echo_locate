import 'dart:typed_data';

/// Wraps headerless 16-bit PCM bytes (as produced by
/// `ChirpGenerator.toPcm16Bytes`) in a minimal WAV container, so
/// `flutter_soloud`'s file-format decoder can load it from memory.
Uint8List wrapPcm16AsWav(
  Uint8List pcm16Bytes, {
  required int sampleRate,
  int numChannels = 1,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = pcm16Bytes.length;

  final header = ByteData(44)
    ..setUint8(0, 0x52) // 'R'
    ..setUint8(1, 0x49) // 'I'
    ..setUint8(2, 0x46) // 'F'
    ..setUint8(3, 0x46) // 'F'
    ..setUint32(4, 36 + dataSize, Endian.little)
    ..setUint8(8, 0x57) // 'W'
    ..setUint8(9, 0x41) // 'A'
    ..setUint8(10, 0x56) // 'V'
    ..setUint8(11, 0x45) // 'E'
    ..setUint8(12, 0x66) // 'f'
    ..setUint8(13, 0x6D) // 'm'
    ..setUint8(14, 0x74) // 't'
    ..setUint8(15, 0x20) // ' '
    ..setUint32(16, 16, Endian.little) // fmt chunk size (PCM)
    ..setUint16(20, 1, Endian.little) // audio format: PCM
    ..setUint16(22, numChannels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, byteRate, Endian.little)
    ..setUint16(32, blockAlign, Endian.little)
    ..setUint16(34, bitsPerSample, Endian.little)
    ..setUint8(36, 0x64) // 'd'
    ..setUint8(37, 0x61) // 'a'
    ..setUint8(38, 0x74) // 't'
    ..setUint8(39, 0x61) // 'a'
    ..setUint32(40, dataSize, Endian.little);

  final wav = Uint8List(44 + dataSize);
  wav.setRange(0, 44, header.buffer.asUint8List());
  wav.setRange(44, 44 + dataSize, pcm16Bytes);
  return wav;
}
