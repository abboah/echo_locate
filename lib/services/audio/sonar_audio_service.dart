import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:hive_ce/hive.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../core/utils/logger.dart';
import '../dsp/chirp_generator.dart';
import '../dsp/chirp_params.dart';
import '../dsp/cross_correlation_service.dart';
import '../dsp/tof_calculator.dart';
import 'wav_encoder.dart';

/// Owns the sonar's hardware I/O: speaker playback (flutter_soloud) and mic
/// capture (record). GetIt-registered per CLAUDE.md's live-sensing pattern —
/// [SonarBloc] calls [ping] and turns the result into UI state; this class
/// owns the mic/speaker and the DSP pipeline that turns one recording into
/// a distance.
class SonarAudioService {
  SonarAudioService({
    ChirpParams params = const ChirpParams(),
    ChirpGenerator generator = const ChirpGenerator(),
    CrossCorrelationService correlator = const CrossCorrelationService(),
    ToFCalculator calculator = const ToFCalculator(),
    // Spectral analysis of a dumped recording (tool/analyze_wav.dart) showed
    // SoLoud.play() itself has ~560ms of latency between the call resolving
    // and audio actually starting — a genuine 2-6kHz upward sweep showed up
    // at t=847ms into a recording whose chirp was "played" at t=288ms. The
    // old 500ms window was ending capture before the chirp ever sounded.
    // 1000ms clears the observed latency with margin for an echo after it.
    this.captureWindow = const Duration(milliseconds: 1000),
    // On-device measurement (Infinix X657C, Android 10): AudioRecord takes
    // meaningfully longer than a naive 30ms to actually start delivering
    // stream data. SONAR-PING timing logs showed firstByteAt landing ~450ms
    // after startStream() resolved — well after playAt at 250ms warmup, so
    // the chirp played before the recorder was actually capturing anything.
    // 600ms clears that with margin.
    this.recorderWarmup = const Duration(milliseconds: 600),
    // Transmit at full scale: echo SNR is the binding constraint, and every
    // dB of transmit power is a dB at the receiver.
    //
    // This was briefly lowered to 0.35 on the theory that the direct
    // speaker-to-mic breakthrough was saturating the ADC and distorting the
    // correlation. That theory rested on ratios measured while ToFCalculator
    // still anchored its search at the buffer's first sample — a window that
    // did not contain the chirp at all (it lands ~740ms in), so those
    // "ratios" were pure noise and the comparison across volumes was
    // meaningless. Measured peaks also barely moved across an 8x volume
    // swing (0.931 -> 0.858), which is the opposite of what saturation by
    // the chirp would look like. At 1.0 the captured peak sits at ~0.93,
    // below the clipping point, so there is headroom to use.
    this.playbackVolume = 1.0,
    // Chirps per ping, emitted as ONE sound (see
    // ChirpGenerator.generateTrain) and averaged by ToFCalculator. More
    // pulses buy a lower noise floor at the cost of a longer measurement.
    this.pulseCount = 4,
    // Silence between pulses inside the train. Must exceed the full round
    // trip at ToFCalculator.maxRangeMeters (10m ≈ 58ms) so one pulse's
    // echoes have died out before the next pulse's breakthrough.
    this.pulseGap = const Duration(milliseconds: 150),
    Box<dynamic>? calibrationBox,
  })  : _calibrationBox = calibrationBox,
        _params = params,
        _generator = generator,
        _correlator = correlator,
        _calculator = calculator;

  final ChirpParams _params;
  final ChirpGenerator _generator;
  final CrossCorrelationService _correlator;
  final ToFCalculator _calculator;
  final Duration captureWindow;
  final Duration recorderWarmup;
  final double playbackVolume;
  final int pulseCount;
  final Duration pulseGap;

  int get _pulseGapSamples =>
      (pulseGap.inMicroseconds * _params.sampleRate) ~/
      Duration.microsecondsPerSecond;

  /// Breakthrough-to-breakthrough spacing inside the emitted train.
  int get _pulseSpacingSamples => _params.sampleCount + _pulseGapSamples;

  final AudioRecorder _recorder = AudioRecorder();
  bool _ready = false;
  bool _busy = false;
  AudioSource? _chirpSource;

  /// This device's fixed acoustic signature, captured by
  /// [calibrateClutter]. Null until calibrated, in which case [ping] falls
  /// back to raw envelopes and can only see past the ringing.
  Float64List? _clutterProfile;

  final Box<dynamic>? _calibrationBox;

  static const String calibrationBoxName = 'sonar_calibration';
  static const String _profileKey = 'clutter_profile';
  static const String _fingerprintKey = 'clutter_profile_params';

  /// Identifies the signal parameters a stored profile was captured under.
  ///
  /// A clutter profile is only meaningful for the exact chirp that produced
  /// it — change the band, duration, sample rate or pulse layout and the
  /// stored ringing signature describes a different signal entirely.
  /// Subtracting it would then corrupt every reading rather than clean it,
  /// and silently, so a profile whose fingerprint does not match is
  /// discarded instead of used.
  String get _paramsFingerprint => '${_params.startFrequencyHz}-'
      '${_params.endFrequencyHz}-${_params.sampleRate}-'
      '${_params.duration.inMicroseconds}-$pulseCount-$_pulseGapSamples';

  /// Restores a stored profile, if one was captured under these exact signal
  /// parameters. Never throws — a bad or stale profile just means the user
  /// is asked to calibrate again.
  void _restoreClutterProfile() {
    final box = _calibrationBox;
    if (box == null) return;
    try {
      if (box.get(_fingerprintKey) != _paramsFingerprint) {
        if (box.get(_profileKey) != null) {
          AppLogger.info(
            'SONAR-CALIBRATE stored profile ignored :: captured under '
            'different signal parameters',
          );
        }
        return;
      }
      final stored = box.get(_profileKey);
      if (stored is! List) return;
      _clutterProfile = Float64List.fromList(
        stored.map((v) => (v as num).toDouble()).toList(),
      );
      AppLogger.info(
        'SONAR-CALIBRATE restored :: ${_clutterProfile!.length} bins',
      );
    } catch (e) {
      AppLogger.warn('SONAR-CALIBRATE restore failed: $e');
    }
  }

  Future<void> _persistClutterProfile(Float64List profile) async {
    final box = _calibrationBox;
    if (box == null) return;
    try {
      await box.put(_profileKey, profile.toList());
      await box.put(_fingerprintKey, _paramsFingerprint);
    } catch (e) {
      // Persisting is a convenience; the in-memory profile still works for
      // this session.
      AppLogger.warn('SONAR-CALIBRATE persist failed: $e');
    }
  }

  /// Brings up the mic + audio engine. Returns false when unavailable
  /// (permission denied, no audio hardware) — callers should disable the
  /// sonar UI rather than let [ping] fail silently.
  Future<bool> start() async {
    if (_ready) return true;
    try {
      final micPermission = await Permission.microphone.request();
      if (!micPermission.isGranted) {
        AppLogger.warn('Microphone permission not granted — sonar unavailable');
        return false;
      }
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
      }
      _restoreClutterProfile();
      _ready = true;
      return true;
    } catch (e) {
      AppLogger.warn('Sonar audio engine unavailable: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (_chirpSource != null) {
      await SoLoud.instance.disposeSource(_chirpSource!);
      _chirpSource = null;
    }
    if (_ready) {
      SoLoud.instance.deinit();
      _ready = false;
    }
  }

  /// [sweeps] independent measurements, reported as their median.
  ///
  /// A single sweep is a point estimate of a moving target: the phone is
  /// hand-held, people and air move, and any one sweep can lock onto a
  /// transient. On-device that showed as a static 0.15m surface reading
  /// 0.11m and 0.17m on consecutive attempts, and as occasional outright
  /// misses. The median of several sweeps discards both — one bad sweep
  /// cannot move it, and a miss costs a sample rather than the reading.
  ///
  /// Returns null only if fewer than half the sweeps found an echo, so
  /// "no reading" now means the scene genuinely had nothing, not that one
  /// sweep was unlucky.
  Future<ToFResult?> measure({int sweeps = 3}) async {
    final results = <ToFResult>[];
    for (var i = 0; i < sweeps; i++) {
      final result = await ping();
      if (result != null) results.add(result);
    }
    if (results.length * 2 < sweeps) {
      AppLogger.info(
        'SONAR-MEASURE discarded :: only ${results.length}/$sweeps sweeps '
        'found an echo',
      );
      return null;
    }

    results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final median = results[results.length ~/ 2];
    final spread =
        results.last.distanceMeters - results.first.distanceMeters;
    AppLogger.info(
      'SONAR-MEASURE median=${median.distanceMeters.toStringAsFixed(3)}m '
      'from ${results.length}/$sweeps sweeps '
      '[${results.map((r) => r.distanceMeters.toStringAsFixed(3)).join(", ")}] '
      'spread=${spread.toStringAsFixed(3)}m',
    );
    return median;
  }

  /// One full emit → record → correlate → time-of-flight pass. Returns
  /// null when the service isn't started, a ping is already in flight, no
  /// confident echo is found, or any hardware call fails — this never
  /// throws, and never returns a clamped/guessed distance.
  Future<ToFResult?> ping() async {
    final correlation = await _emitAndCorrelate();
    if (correlation == null) return null;

    final raw = _calculator.calculate(
      correlation: correlation,
      sampleRate: _params.sampleRate,
      pulseCount: pulseCount,
      pulseSpacingSamples: _pulseSpacingSamples,
      clutterProfile: _clutterProfile,
    );
    if (raw == null) {
      final debug = _calculator.debugBestPeak(
        correlation: correlation,
        sampleRate: _params.sampleRate,
        pulseCount: pulseCount,
        pulseSpacingSamples: _pulseSpacingSamples,
        clutterProfile: _clutterProfile,
      );
      AppLogger.info(
        debug == null
            ? 'SONAR-PING no echo :: no in-range peak at all'
            : 'SONAR-PING no echo :: best candidate '
                'distance=${debug.distanceMeters.toStringAsFixed(3)}m '
                'peakToNoiseRatio=${debug.peakToNoiseRatio.toStringAsFixed(2)} '
                '(gate=${_calculator.noiseGateRatio}) '
                'clutter=${_clutterProfile == null ? "none" : "applied"}',
      );
      return null;
    }

    // No latency compensation needed: ToFCalculator anchors t=0 on the
    // direct speaker-to-mic breakthrough peak, which physically cancels
    // playback/recording scheduling latency.
    AppLogger.info(
      'SONAR-PING distance=${raw.distanceMeters.toStringAsFixed(3)}m '
      'peakToNoiseRatio=${raw.peakToNoiseRatio.toStringAsFixed(2)} '
      'clutter=${_clutterProfile == null ? "none" : "applied"}',
    );
    return raw;
  }

  /// Records this device's fixed acoustic signature — speaker ringing and
  /// the phone body's own reflections — so [ping] can subtract it.
  ///
  /// Takes [captures] sweeps and keeps the per-bin MINIMUM rather than
  /// averaging. The user is asked to move the phone slowly while this runs,
  /// which makes the difference: the speaker's ringing is present at the
  /// same delay in every sweep, while echoes off real surfaces move as the
  /// phone turns. The minimum therefore keeps what is always there (the
  /// device) and discards what comes and goes (the room).
  ///
  /// Averaging a single sweep instead bakes whatever happened to be in
  /// front into the profile, and it then gets subtracted out of every later
  /// measurement — on-device that showed up as the "fixed" signature at
  /// 0.15m varying 3x between calibrations (0.0518 to 0.1585 of the
  /// breakthrough) depending on where the phone was pointed.
  ///
  /// Returns false if every capture failed; the previous profile (if any)
  /// is then left untouched.
  Future<bool> calibrateClutter({int captures = 3}) async {
    final profiles = <Float64List>[];
    for (var i = 0; i < captures; i++) {
      final correlation = await _emitAndCorrelate();
      if (correlation == null) continue;

      final profile = _calculator.buildClutterProfile(
        correlation: correlation,
        sampleRate: _params.sampleRate,
        pulseCount: pulseCount,
        pulseSpacingSamples: _pulseSpacingSamples,
      );
      if (profile != null) profiles.add(profile);
    }
    if (profiles.isEmpty) {
      AppLogger.warn('SONAR-CALIBRATE failed :: no usable sweep');
      return false;
    }

    var length = profiles.first.length;
    for (final p in profiles) {
      if (p.length < length) length = p.length;
    }
    final profile = Float64List(length);
    for (var d = 0; d < length; d++) {
      var lowest = profiles.first[d];
      for (final p in profiles) {
        if (p[d] < lowest) lowest = p[d];
      }
      profile[d] = lowest;
    }

    _clutterProfile = profile;
    await _persistClutterProfile(profile);
    AppLogger.info(
      'SONAR-CALIBRATE merged ${profiles.length}/$captures sweeps '
      '(per-bin minimum)',
    );
    AppLogger.info(
      'SONAR-CALIBRATE captured :: ${profile.length} bins, '
      'ringing at 0.15m=${_profileAt(profile, 0.15).toStringAsFixed(4)} '
      '0.5m=${_profileAt(profile, 0.5).toStringAsFixed(4)} '
      '1.0m=${_profileAt(profile, 1.0).toStringAsFixed(4)} '
      '(fraction of breakthrough)',
    );
    return true;
  }

  bool get hasClutterProfile => _clutterProfile != null;

  double _profileAt(Float64List profile, double meters) {
    final index = (2 * meters / 343.0 * _params.sampleRate).round();
    if (index < 0 || index >= profile.length) return 0;
    return profile[index];
  }

  /// Emits the pulse train, records it, and matched-filters the recording
  /// against a single chirp. Shared by [ping] and [calibrateClutter] so both
  /// measure through exactly the same signal path.
  Future<Float64List?> _emitAndCorrelate() async {
    if (!_ready || _busy) return null;
    _busy = true;

    StreamSubscription<Uint8List>? subscription;
    try {
      // The correlation template is ONE chirp; the emitted sound is the
      // whole train. Matched-filtering the train against a single chirp is
      // what puts a breakthrough peak at each pulse.
      final chirpSamples = _generator.generate(_params);
      _chirpSource ??= await SoLoud.instance.loadMem(
        'sonar_chirp_train.wav',
        wrapPcm16AsWav(
          _generator.toPcm16Bytes(
            _generator.generateTrain(
              _params,
              pulseCount: pulseCount,
              gapSamples: _pulseGapSamples,
            ),
          ),
          sampleRate: _params.sampleRate,
        ),
      );

      final stopwatch = Stopwatch()..start();
      Duration? firstByteAt;

      final recordedBytes = <int>[];
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _params.sampleRate,
          numChannels: 1,
        ),
      );
      final startStreamAt = stopwatch.elapsed;
      subscription = stream.listen((chunk) {
        firstByteAt ??= stopwatch.elapsed;
        recordedBytes.addAll(chunk);
      });

      // Let mic capture spin up before the chirp fires, so its onset isn't
      // clipped by recorder startup latency (see [recorderWarmup] doc).
      await Future<void>.delayed(recorderWarmup);
      final playAt = stopwatch.elapsed;
      await SoLoud.instance.play(_chirpSource!, volume: playbackVolume);
      final trainDuration = Duration(
        microseconds: (_params.duration.inMicroseconds * pulseCount) +
            (pulseGap.inMicroseconds * (pulseCount - 1)),
      );
      await Future<void>.delayed(trainDuration + captureWindow);

      // Cancel and stop before reading the buffer, so every chunk emitted
      // during the capture window is flushed to [recordedBytes] first.
      await subscription.cancel();
      subscription = null;
      await _recorder.stop();
      stopwatch.stop();

      final expectedSamples =
          _params.sampleRate * stopwatch.elapsedMilliseconds ~/ 1000;
      AppLogger.info(
        'SONAR-PING timing :: startStreamAt=${startStreamAt.inMilliseconds}ms '
        'firstByteAt=${firstByteAt?.inMilliseconds}ms '
        'playAt=${playAt.inMilliseconds}ms '
        'totalElapsed=${stopwatch.elapsedMilliseconds}ms '
        'samples=${recordedBytes.length ~/ 2}/$expectedSamples',
      );

      final received = _pcm16BytesToFloat64(Uint8List.fromList(recordedBytes));
      AppLogger.info(
        'SONAR-PING rawSignal :: ${_signalStats(received)} '
        'chirpPeak=${chirpSamples.reduce((a, b) => a.abs() > b.abs() ? a : b).toStringAsFixed(3)}',
      );
      await _debugDumpWav(received, chirpSamples);
      final correlation = _correlator.correlate(received, chirpSamples);
      final anchors = _calculator.debugAnchors(
        correlation: correlation,
        pulseCount: pulseCount,
        pulseSpacingSamples: _pulseSpacingSamples,
      );
      AppLogger.info(
        'SONAR-PING anchors :: spacing=$_pulseSpacingSamples '
        'at=${anchors.join(",")} '
        'peaks=${anchors.map((i) => correlation[i].abs().toStringAsFixed(1)).join(",")}',
      );
      return correlation;
    } catch (e, stack) {
      AppLogger.error('Sonar capture failed: $e', e, stack);
      return null;
    } finally {
      await subscription?.cancel();
      try {
        await _recorder.stop();
      } catch (_) {}
      _busy = false;
    }
  }

  Float64List _pcm16BytesToFloat64(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final data = ByteData.sublistView(bytes, 0, sampleCount * 2);
    final samples = Float64List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  /// Peak/RMS of the raw captured signal, before correlation. Diagnostic
  /// only — tells "mic captured near-silence" (playback/capture broken)
  /// apart from "captured real audio, but no echo correlated" (acoustic/
  /// gate tuning issue).
  String _signalStats(Float64List samples) {
    if (samples.isEmpty) return 'peak=0.000 rms=0.000 (empty)';
    var peak = 0.0;
    var sumSquares = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
      sumSquares += s * s;
    }
    final rms = math.sqrt(sumSquares / samples.length);
    return 'peak=${peak.toStringAsFixed(3)} rms=${rms.toStringAsFixed(4)}';
  }

  /// TEMPORARY calibration aid: dumps the captured recording and the
  /// reference chirp as WAV files to this app's private cache dir (always
  /// writable, no external-storage permission needed), so they can be
  /// pulled with `adb shell run-as <pkg> cat <path>` and inspected directly
  /// instead of guessing from summary stats. Remove once calibration is done.
  Future<void> _debugDumpWav(Float64List received, Float64List chirp) async {
    try {
      final dir = Directory.systemTemp.path;
      await File('$dir/sonar_received.wav').writeAsBytes(
        wrapPcm16AsWav(
          _generator.toPcm16Bytes(received),
          sampleRate: _params.sampleRate,
        ),
      );
      await File('$dir/sonar_chirp.wav').writeAsBytes(
        wrapPcm16AsWav(
          _generator.toPcm16Bytes(chirp),
          sampleRate: _params.sampleRate,
        ),
      );
      AppLogger.info('SONAR-PING debug WAVs written to $dir');
    } catch (e) {
      AppLogger.warn('SONAR-PING debug WAV dump failed: $e');
    }
  }
}
