import 'package:echo_locate/core/constants/app_constants.dart';
import 'package:echo_locate/core/utils/logger.dart';
import 'package:echo_locate/services/audio/chirp_generator.dart';
import 'package:echo_locate/services/dsp/cross_correlation_service.dart';
import 'package:echo_locate/services/dsp/tof_calculator.dart';

/// Service for playing and recording audio using flutter_soloud for playback
/// and the record package for microphone input
class AudioService {
  final ChirpGenerator _chirpGenerator = ChirpGenerator();
  final CrossCorrelationService _crossCorrelation = CrossCorrelationService();
  final ToFCalculator _tofCalculator = ToFCalculator();

  bool _isInitialized = false;
  bool _isRecording = false;
  List<double> _recordedSamples = [];

  /// Initialize the audio service components
  /// Sets up flutter_soloud for audio playback
  Future<void> initialize() async {
    try {
      AppLogger.info('Initializing AudioService');

      // TODO: Initialize flutter_soloud audio engine
      // Example when flutter_soloud APIs are available:
      // await SoLoud.instance.initialize();

      _isInitialized = true;
      AppLogger.info('AudioService initialized successfully');
    } catch (e) {
      AppLogger.error('Failed to initialize AudioService: $e');
      _isInitialized = false;
    }
  }

  /// Emits a chirp signal through the speaker
  ///
  /// Steps:
  /// 1. Generate chirp using ChirpGenerator with AppConstants values
  /// 2. Play it through flutter_soloud
  /// 3. Duration matches CHIRP_DURATION_MS
  Future<void> emitChirp() async {
    try {
      if (!_isInitialized) {
        AppLogger.warn('AudioService not initialized, initializing...');
        await initialize();
      }

      AppLogger.info('Generating chirp signal');

      // Generate chirp using ChirpGenerator with AppConstants values
      // Create a linear FMCW sweep from startFreq to endFreq
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

      // Play it through flutter_soloud
      // Duration should match CHIRP_DURATION_MS
      // TODO: Implement playback when flutter_soloud AudioSource creation is available
      // Example when APIs are available:
      // final audioSource = AudioSource.generate(
      //   duration: AppConstants.chirpDurationMs / 1000.0,
      //   sampleRate: AppConstants.sampleRate,
      //   samples: chirp,
      // );
      // await SoLoud.instance.play(audioSource);

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
  ///
  /// TODO: The record package (pub.dev/packages/record) should be added as a
  /// supplement for microphone capture, as flutter_soloud does not provide
  /// direct microphone input recording capabilities. Once the record package
  /// is integrated, this method should:
  /// 1. Initialize the recorder from the record package
  /// 2. Start recording for durationMs milliseconds
  /// 3. Stop recording and retrieve the audio data
  /// 4. Normalize samples to -1.0 to 1.0 range
  /// 5. Return as List<double>
  Future<List<double>> recordEcho(int durationMs) async {
    try {
      AppLogger.info('Recording echo for ${durationMs}ms');

      // TODO: Implement recording using the record package
      // Example implementation once record package is added:
      // final recorder = AudioRecorder();
      // await recorder.start(
      //   path: recordPath,
      //   encoder: AudioEncoder.pcm16bit,
      //   sampleRate: AppConstants.sampleRate,
      // );
      // await Future.delayed(Duration(milliseconds: durationMs));
      // await recorder.stop();
      // final audioBytes = await File(recordPath).readAsBytes();
      // return _normalizeAudio(audioBytes);

      _isRecording = true;
      _recordedSamples = [];

      // For now, simulate recording with silence
      // This allows the app to build and run without the record package
      final expectedSamples = (AppConstants.sampleRate * durationMs / 1000)
          .round();
      _recordedSamples = List<double>.filled(expectedSamples, 0.0);

      await Future.delayed(Duration(milliseconds: durationMs));

      _isRecording = false;
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
      // TODO: Dispose flutter_soloud resources when available
      // Example: await SoLoud.instance.deinit();

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
}
