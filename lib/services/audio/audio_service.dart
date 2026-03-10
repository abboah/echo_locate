import 'dart:typed_data';
import 'package:echo_locate/core/constants/app_constants.dart';
import 'package:echo_locate/core/utils/logger.dart';
import 'package:echo_locate/services/audio/chirp_generator.dart';
import 'package:echo_locate/services/dsp/cross_correlation_service.dart';
import 'package:echo_locate/services/dsp/tof_calculator.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

/// Service for playing and recording audio using flutter_soloud for playback
/// and the record package for microphone input
class AudioService {
  final ChirpGenerator _chirpGenerator = ChirpGenerator();
  final CrossCorrelationService _crossCorrelation = CrossCorrelationService();
  final ToFCalculator _tofCalculator = ToFCalculator();

  late final SoLoud _soLoud;
  late final AudioRecorder _recorder;

  bool _isInitialized = false;
  bool _isRecording = false;
  List<double> _recordedSamples = [];

  AudioService() {
    _soLoud = SoLoud.instance;
    _recorder = AudioRecorder();
  }

  /// Initialize the audio service components
  /// Sets up flutter_soloud for audio playback
  Future<void> initialize() async {
    try {
      AppLogger.info('Initializing AudioService');

      // Initialize SoLoud
      await _soLoud.init();

      _isInitialized = true;
      AppLogger.info('AudioService initialized successfully');
    } catch (e) {
      AppLogger.error('Failed to initialize AudioService: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  /// Emits a chirp signal through the speaker
  ///
  /// Steps:
  /// 1. Generate chirp using ChirpGenerator with AppConstants values
  /// 2. Convert to WAV format
  /// 3. Load and play through flutter_soloud
  /// 4. Duration matches CHIRP_DURATION_MS
  Future<void> emitChirp() async {
    try {
      if (!_isInitialized) {
        AppLogger.warn('AudioService not initialized, initializing...');
        await initialize();
      }

      AppLogger.info('Generating chirp signal');

      // Generate chirp using ChirpGenerator with AppConstants values
      final chirp = _chirpGenerator.generateChirp(
        sampleRate: AppConstants.sampleRate,
        startFreq: AppConstants.chirpFrequencyStart,
        endFreq: AppConstants.chirpFrequencyEnd,
        durationMs: AppConstants.chirpDurationMs,
      );

      AppLogger.info(
        'Chirp generated: ${chirp.length} samples, '
        'duration: ${AppConstants.chirpDurationMs}ms',
      );

      // Convert Float32List to WAV Uint8List
      final wavData = _float32ListToWav(chirp, AppConstants.sampleRate);

      // Load the WAV data into SoLoud
      final audioSource = await _soLoud.loadMem('chirp.wav', wavData);

      // Play the chirp
      await _soLoud.play(audioSource);

      AppLogger.info('Chirp playback initiated');
    } catch (e) {
      AppLogger.error('Failed to emit chirp: $e');
      rethrow;
    }
  }

  /// Records audio echo for a specified duration
  ///
  /// [durationMs] - Recording duration in milliseconds
  ///
  /// Returns:
  /// - List<double> containing normalized samples between -1.0 and 1.0
  Future<List<double>> recordEcho(int durationMs) async {
    try {
      AppLogger.info('Recording echo for ${durationMs}ms');

      // Check permissions
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Microphone permission not granted');
      }

      _isRecording = true;
      _recordedSamples = [];

      // Start recording to stream
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: AppConstants.sampleRate,
          numChannels: 1,
        ),
      );

      final samples = <int>[];
      final subscription = stream.listen((data) {
        // Convert Uint8List to Int16List
        final int16Data = Int16List.view(data.buffer);
        samples.addAll(int16Data);
      });

      // Wait for the recording duration
      await Future.delayed(Duration(milliseconds: durationMs));

      // Stop recording
      await _recorder.stop();
      await subscription.cancel();

      _isRecording = false;

      // Convert to normalized double samples
      _recordedSamples = samples.map((s) => s / 32768.0).toList();

      AppLogger.info('Recording complete: ${_recordedSamples.length} samples');

      return _recordedSamples;
    } catch (e) {
      AppLogger.error('Failed to record echo: $e');
      _isRecording = false;
      rethrow;
    }
  }

  /// Main measurement pipeline: emit chirp and measure distance
  ///
  /// Steps:
  /// 1. Call emitChirp()
  /// 2. Immediately call recordEcho(200) to capture reflection window
  /// 3. Pass recorded samples and the original chirp to CrossCorrelationService
  /// 4. Pass correlation result to ToFCalculator
  /// 5. Return distance in meters
  Future<double> measureDistance() async {
    try {
      AppLogger.info('Starting distance measurement');

      // Call emitChirp()
      // This transmits the acoustic chirp signal
      await emitChirp();

      // Immediately call recordEcho(200) to capture reflection window
      // Record for 200ms to capture the echo with some buffer time
      // This accounts for the round-trip travel time
      final recordedSamples = await recordEcho(200);

      if (recordedSamples.isEmpty) {
        AppLogger.warn('No samples recorded');
        return -1.0;
      }

      AppLogger.info('Received ${recordedSamples.length} recorded samples');

      // Generate the chirp template to correlate against
      final chirpTemplate = _chirpGenerator.generateChirp(
        sampleRate: AppConstants.sampleRate,
        startFreq: AppConstants.chirpFrequencyStart,
        endFreq: AppConstants.chirpFrequencyEnd,
        durationMs: AppConstants.chirpDurationMs,
      );

      AppLogger.info(
        'Chirp template generated: ${chirpTemplate.length} samples',
      );

      // Pass recorded samples and the original chirp to CrossCorrelationService
      // This finds the time delay between transmission and reception
      final correlation = _crossCorrelation.correlate(
        recordedSamples,
        chirpTemplate.cast<double>(),
      );

      if (correlation.isEmpty) {
        AppLogger.warn('Cross-correlation resulted in empty data');
        return -1.0;
      }

      AppLogger.info('Cross-correlation computed: ${correlation.length} lags');

      // Pass correlation result to ToFCalculator
      // Calculate distance based on the peak time delay
      final distance = _tofCalculator.calculateDistance(
        correlation,
        AppConstants.sampleRate,
        AppConstants.speedOfSound,
      );

      AppLogger.info('Distance measured: ${distance.toStringAsFixed(2)}m');

      return distance;
    } catch (e) {
      AppLogger.error('Distance measurement failed: $e');
      return -1.0;
    }
  }

  /// Dispose of audio resources
  Future<void> dispose() async {
    try {
      _soLoud.deinit();
      await _recorder.dispose();

      _isInitialized = false;
      _isRecording = false;
      _recordedSamples = [];
      AppLogger.info('AudioService disposed');
    } catch (e) {
      AppLogger.error('Error during AudioService disposal: $e');
    }
  }

  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  List<double> get recordedSamples => _recordedSamples;

  /// Convert Float32List audio samples to WAV format Uint8List
  Uint8List _float32ListToWav(Float32List samples, int sampleRate) {
    final numSamples = samples.length;
    const numChannels = 1; // Mono
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = numSamples * bitsPerSample ~/ 8;
    final fileSize = 36 + dataSize;

    final buffer = BytesBuilder();

    // WAV header
    buffer.add('RIFF'.codeUnits); // ChunkID
    buffer.add(_int32ToBytes(fileSize)); // ChunkSize
    buffer.add('WAVE'.codeUnits); // Format

    // fmt subchunk
    buffer.add('fmt '.codeUnits); // Subchunk1ID
    buffer.add(_int32ToBytes(16)); // Subchunk1Size (16 for PCM)
    buffer.add(_int16ToBytes(1)); // AudioFormat (1 for PCM)
    buffer.add(_int16ToBytes(numChannels)); // NumChannels
    buffer.add(_int32ToBytes(sampleRate)); // SampleRate
    buffer.add(_int32ToBytes(byteRate)); // ByteRate
    buffer.add(_int16ToBytes(blockAlign)); // BlockAlign
    buffer.add(_int16ToBytes(bitsPerSample)); // BitsPerSample

    // data subchunk
    buffer.add('data'.codeUnits); // Subchunk2ID
    buffer.add(_int32ToBytes(dataSize)); // Subchunk2Size

    // Convert float samples to 16-bit PCM
    for (final sample in samples) {
      // Clamp to [-1, 1] and convert to 16-bit
      final clamped = sample.clamp(-1.0, 1.0);
      final pcm = (clamped * 32767).round();
      buffer.add(_int16ToBytes(pcm));
    }

    return buffer.toBytes();
  }

  Uint8List _int16ToBytes(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  }

  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  }
}
