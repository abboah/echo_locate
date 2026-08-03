import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:hive_ce/hive.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../core/utils/logger.dart';
import '../acoustic/reverb_analyzer.dart';
import '../acoustic/reverb_measurement.dart';
import '../dsp/chirp_generator.dart';
import '../dsp/chirp_params.dart';
import '../dsp/cross_correlation_service.dart';
import '../dsp/tof_calculator.dart';
import 'audio_arbiter.dart';
import 'sonar_latency_profile.dart';
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
    // FALLBACK timings only — used for the first sweep of a fresh install,
    // and whenever a measured [SonarLatencyProfile] is unavailable or
    // implausible. Both are sized for the worst case rather than this
    // device's actual behaviour, which is why they are slow; after one sweep
    // the service measures the real latencies and schedules itself from
    // those instead (see [_latency]).
    //
    // Spectral analysis of a dumped recording (tool/analyze_wav.dart) showed
    // SoLoud.play() itself has ~560ms of latency between the call resolving
    // and audio actually starting — a genuine 2-6kHz upward sweep showed up
    // at t=847ms into a recording whose chirp was "played" at t=288ms. The
    // old 500ms window was ending capture before the chirp ever sounded.
    // 1000ms clears the observed latency with margin for an echo after it.
    this.captureWindow = const Duration(milliseconds: 1000),
    // No longer a delay that is always waited out — it is the TIMEOUT on
    // waiting for the recorder's first chunk. The capture now waits for that
    // chunk to actually arrive (see [_emitAndCorrelate]), so this only comes
    // into play when the recorder never delivers at all, and the sweep is
    // going to fail either way. Kept generous for that reason: on-device
    // startup was seen anywhere from 358ms to 652ms.
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
    //
    // 80ms rather than the original 150ms: the constraint is 58ms, so 150ms
    // was carrying ~92ms of unused slack on every gap — 276ms per train, and
    // three times that per measurement. 80ms keeps a 22ms margin over the
    // constraint. (The true limit is looser still, since the 120ms chirp is
    // itself longer than the 58ms echo window, but the gap is what the
    // envelope-overlap argument is stated in terms of, so it is what is kept
    // honest.)
    //
    // Changing this invalidates any stored clutter profile — the fingerprint
    // in [_paramsFingerprint] includes the pulse layout, so a profile
    // captured under the old gap is discarded rather than misapplied, and
    // devices need recalibrating once.
    this.pulseGap = const Duration(milliseconds: 80),
    // Silence recorded after the reverb chirp, for the room to fall quiet in.
    // Must outlast the longest reverberation worth classifying — a bare hall
    // runs to roughly 2s — and also cover the playback latency before the
    // chirp sounds at all. ReverbAnalyzer separately refuses any fit that only
    // completes as the buffer ends, so a window that proves too short for a
    // very live space yields no reading rather than a wrong one.
    this.reverbTail = const Duration(milliseconds: 3000),
    ReverbAnalyzer reverbAnalyzer = const ReverbAnalyzer(),
    Box<dynamic>? calibrationBox,
    AudioArbiter? arbiter,
  })  : _arbiter = arbiter,
        _calibrationBox = calibrationBox,
        _params = params,
        _generator = generator,
        _correlator = correlator,
        _reverbAnalyzer = reverbAnalyzer,
        _calculator = calculator;

  final ChirpParams _params;
  final ChirpGenerator _generator;
  final CrossCorrelationService _correlator;
  final ToFCalculator _calculator;
  final ReverbAnalyzer _reverbAnalyzer;
  final Duration captureWindow;
  final Duration recorderWarmup;
  final double playbackVolume;
  final int pulseCount;
  final Duration pulseGap;
  final Duration reverbTail;

  int get _pulseGapSamples =>
      (pulseGap.inMicroseconds * _params.sampleRate) ~/
      Duration.microsecondsPerSecond;

  /// Breakthrough-to-breakthrough spacing inside the emitted train.
  int get _pulseSpacingSamples => _params.sampleCount + _pulseGapSamples;

  /// This device's measured audio latencies. Null until the first successful
  /// sweep (or a restore from storage), while the conservative constructor
  /// fallbacks are used instead.
  SonarLatencyProfile? _latency;

  SonarLatencyProfile? get latencyProfile => _latency;

  /// Round-trip flight time of the furthest echo still worth recording.
  Duration get _maxEchoDelay => Duration(
        microseconds: (2 *
                _calculator.maxRangeMeters /
                _calculator.speedOfSoundMps *
                Duration.microsecondsPerSecond)
            .round(),
      );

  /// Settle time after the recorder's first chunk arrives, before the chirp
  /// fires. One chunk is ~80ms on this hardware; this keeps the chirp off the
  /// boundary of the very first buffer handed over.
  static const Duration _captureSettle = Duration(milliseconds: 80);

  Duration get _effectiveWindow =>
      _latency?.captureWindow(maxEchoDelay: _maxEchoDelay) ?? captureWindow;

  /// Mediates the mic/speaker against speech. Null in tests and in any build
  /// where nothing else contends for audio, in which case sonar simply takes
  /// the hardware as it always did.
  final AudioArbiter? _arbiter;

  final AudioRecorder _recorder = AudioRecorder();
  bool _ready = false;
  bool _busy = false;

  bool _lastCaptureYielded = false;

  /// Whether a measurement could be started right now.
  bool get isReady => _ready;

  /// Whether a capture is already in flight. Chirping over one would corrupt
  /// both.
  bool get isBusy => _busy;

  /// Whether the most recent capture attempt came back empty because the
  /// hardware was taken, rather than because the scene held nothing.
  ///
  /// The distinction cannot be recovered from an empty result and matters a
  /// great deal to a fusion layer: "nothing came back" is evidence there is
  /// no surface ahead, while "a callout took the speaker" is evidence about
  /// nothing at all. Treating the second as the first tells the caller that
  /// empty air was confirmed. Valid only immediately after a capture call.
  bool get lastCaptureYielded => _lastCaptureYielded;

  /// Whether THIS service was the one that brought SoLoud up.
  ///
  /// `SoLoud.instance` is process-wide. [stop] used to deinit it
  /// unconditionally, which was harmless only while sonar was its sole user —
  /// the moment anything else (a sound cue, a future audio feature) shares the
  /// engine, closing the sonar screen would silently tear it out from under
  /// them. Only the initialiser deinitialises.
  bool _initialisedSoLoud = false;
  AudioSource? _chirpSource;

  /// A lone chirp, for [captureImpulseResponse]. Held separately from
  /// [_chirpSource] because that one is a train of pulses — useless for
  /// reverberation, where each pulse would excite the room again partway
  /// through the previous decay.
  AudioSource? _singleChirpSource;

  /// This device's fixed acoustic signature, captured by
  /// [calibrateClutter]. Null until calibrated, in which case [ping] falls
  /// back to raw envelopes and can only see past the ringing.
  Float64List? _clutterProfile;

  final Box<dynamic>? _calibrationBox;

  static const String calibrationBoxName = 'sonar_calibration';
  static const String _profileKey = 'clutter_profile';
  static const String _fingerprintKey = 'clutter_profile_params';
  static const String _latencyKey = 'latency_profile';
  static const String _latencyRateKey = 'latency_profile_sample_rate';

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

  /// Restores a stored latency profile.
  ///
  /// Keyed on sample rate alone, not the full chirp fingerprint: how long the
  /// recorder takes to start and the playback engine takes to sound are
  /// properties of the device and the audio stack, not of the waveform being
  /// played. Retuning the chirp invalidates the clutter profile but leaves
  /// these measurements perfectly valid.
  void _restoreLatencyProfile() {
    final box = _calibrationBox;
    if (box == null) return;
    try {
      if (box.get(_latencyRateKey) != _params.sampleRate) return;
      final profile = SonarLatencyProfile.fromJson(box.get(_latencyKey));
      if (profile == null) return;
      _latency = profile;
      AppLogger.info('SONAR-LATENCY restored :: $profile');
    } catch (e) {
      AppLogger.warn('SONAR-LATENCY restore failed: $e');
    }
  }

  Future<void> _persistLatencyProfile(SonarLatencyProfile profile) async {
    final box = _calibrationBox;
    if (box == null) return;
    try {
      await box.put(_latencyKey, profile.toJson());
      await box.put(_latencyRateKey, _params.sampleRate);
    } catch (e) {
      AppLogger.warn('SONAR-LATENCY persist failed: $e');
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

  /// Measures how reverberant the surrounding space is (M5).
  ///
  /// Deliberately does NOT reuse the ranging capture. Ranging fires a train
  /// of chirps [pulseGap] apart so their echoes can be averaged, but each
  /// pulse then lands on top of the previous one's decay — which is precisely
  /// the quantity reverberation analysis measures. Reverb needs the opposite:
  /// one excitation, then silence long enough for the room to fall quiet.
  ///
  /// Reports why rather than just failing — see [ReverbFailure]. Never
  /// guesses: an unmeasurable room yields a failure, not a number.
  Future<ReverbMeasurement> measureReverb() async {
    final capture = await _capture();
    final response = capture.response;
    if (response == null) {
      AppLogger.info('SONAR-REVERB failed :: ${capture.failure!.name}');
      return ReverbMeasurement.failed(capture.failure!);
    }

    final features = _reverbAnalyzer.analyze(
      impulseResponse: response,
      sampleRate: _params.sampleRate,
    );
    AppLogger.info(
      features == null
          ? 'SONAR-REVERB no decay :: capture held no measurable reverberation'
          : 'SONAR-REVERB $features',
    );
    return features == null
        ? const ReverbMeasurement.failed(ReverbFailure.noMeasurableDecay)
        : ReverbMeasurement.measured(features);
  }

  /// One chirp, then the room's decay, matched-filtered into an impulse
  /// response. Exposed separately from [measureReverb] so the raw response
  /// can be dumped and inspected during evaluation (M10).
  Future<Float64List?> captureImpulseResponse() async =>
      (await _capture()).response;

  Future<({Float64List? response, ReverbFailure? failure})> _capture() async {
    if (!_ready) return (response: null, failure: ReverbFailure.audioUnavailable);
    if (_busy) return (response: null, failure: ReverbFailure.audioBusy);

    final lease = await _arbiter?.acquire(AudioUse.ranging);
    if (_arbiter != null && lease == null) {
      AppLogger.debug('SONAR-REVERB skipped :: audio in use by something louder');
      return (response: null, failure: ReverbFailure.audioBusy);
    }

    _busy = true;
    StreamSubscription<Uint8List>? subscription;
    try {
      final chirpSamples = _generator.generate(_params);
      _singleChirpSource ??= await SoLoud.instance.loadMem(
        'sonar_chirp_single.wav',
        wrapPcm16AsWav(
          _generator.toPcm16Bytes(chirpSamples),
          sampleRate: _params.sampleRate,
        ),
      );

      final stopwatch = Stopwatch()..start();
      final capturing = Completer<void>();
      Duration? firstByteAt;
      final recordedBytes = <int>[];

      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _params.sampleRate,
          numChannels: 1,
          // Same reasoning as the ranging capture: platform voice processing
          // would rewrite the very decay being measured. Automatic gain
          // control is especially destructive here — it would fight the
          // fade-out, flattening the slope that IS the measurement.
          androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.unprocessed,
          ),
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      subscription = stream.listen((chunk) {
        if (firstByteAt == null) {
          firstByteAt = stopwatch.elapsed;
          if (!capturing.isCompleted) capturing.complete();
        }
        recordedBytes.addAll(chunk);
      });

      await capturing.future
          .timeout(recorderWarmup, onTimeout: () {})
          .catchError((Object _) {});
      await Future<void>.delayed(_captureSettle);

      // Nothing below tolerates a competing sound. This window records
      // SILENCE by design — a callout spoken over it is not noise the
      // analyzer can see through, it is a second excitation arriving
      // mid-decay, and Schroeder integration turns that into a smooth,
      // convincing, entirely wrong RT60. So the capture is abandoned at the
      // first sign of pre-emption rather than analysed: with the camera
      // feature running alongside, this is the common case, not the rare one.
      if (lease?.isCancelled ?? false) {
        return (response: null, failure: ReverbFailure.interrupted);
      }

      await SoLoud.instance.play(_singleChirpSource!, volume: playbackVolume);
      // The decay window has to outlast the longest reverberation worth
      // classifying, plus the playback latency before the chirp even sounds.
      final settled = await _waitUnlessCancelled(
        _params.duration + reverbTail,
        lease,
      );

      await subscription.cancel();
      subscription = null;
      await _recorder.stop();
      stopwatch.stop();

      if (!settled) {
        return (response: null, failure: ReverbFailure.interrupted);
      }
      if (firstByteAt == null) {
        return (response: null, failure: ReverbFailure.captureFailed);
      }
      final received = _pcm16BytesToFloat64(Uint8List.fromList(recordedBytes));
      AppLogger.debug(
        'SONAR-REVERB capture :: ${_signalStats(received)} '
        'samples=${received.length}',
      );
      if (received.isEmpty) {
        return (response: null, failure: ReverbFailure.captureFailed);
      }

      // Matched filtering compresses the chirp to an impulse, so the result
      // is this room's impulse response — the input reverberation analysis
      // needs, and the same transform ranging already relies on.
      return (
        response: _correlator.correlate(received, chirpSamples),
        failure: null,
      );
    } catch (e, stack) {
      AppLogger.error('Sonar reverb capture failed: $e', e, stack);
      return (response: null, failure: ReverbFailure.captureFailed);
    } finally {
      await subscription?.cancel();
      try {
        await _recorder.stop();
      } catch (_) {}
      _busy = false;
      lease?.release();
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
        _initialisedSoLoud = true;
      }
      _restoreClutterProfile();
      _restoreLatencyProfile();
      _ready = true;
      return true;
    } catch (e) {
      AppLogger.warn('Sonar audio engine unavailable: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (_singleChirpSource != null) {
      await SoLoud.instance.disposeSource(_singleChirpSource!);
      _singleChirpSource = null;
    }
    if (_chirpSource != null) {
      await SoLoud.instance.disposeSource(_chirpSource!);
      _chirpSource = null;
    }
    if (_ready) {
      if (_initialisedSoLoud) {
        SoLoud.instance.deinit();
        _initialisedSoLoud = false;
      }
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
    final captures = await _captureSweeps(sweeps: sweeps);
    final results = <ToFResult>[];
    for (final capture in captures) {
      final result = _resolve(capture);
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
    final captures = await _captureSweeps(sweeps: 1);
    if (captures.isEmpty) return null;
    return _resolve(captures.first);
  }

  /// Turns one captured sweep into a distance, or null when no confident echo
  /// stands out of it.
  ToFResult? _resolve(({Float64List correlation, DateTime playedAt}) capture) {
    final correlation = capture.correlation;

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
      AppLogger.debug(
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
    //
    // Per-sweep detail is debug-level: one user-facing measurement is several
    // sweeps, and only the median it resolves to (logged by [measure]) is
    // worth a line at info during joint camera/sonar runs.
    AppLogger.debug(
      'SONAR-PING distance=${raw.distanceMeters.toStringAsFixed(3)}m '
      'peakToNoiseRatio=${raw.peakToNoiseRatio.toStringAsFixed(2)} '
      'clutter=${_clutterProfile == null ? "none" : "applied"}',
    );
    return raw.at(capture.playedAt);
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
    for (final capture in await _captureSweeps(sweeps: captures)) {
      final profile = _calculator.buildClutterProfile(
        correlation: capture.correlation,
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

  /// Emits [sweeps] pulse trains inside ONE recording and matched-filters each
  /// against a single chirp. Shared by [ping] and [calibrateClutter] so both
  /// measure through exactly the same signal path.
  ///
  /// One recorder session, not one per sweep. Bringing `AudioRecord` up costs
  /// 322-739ms on the Infinix X657C and is pure overhead repeated per sweep —
  /// for a 3-sweep measurement that was up to 1.5s spent starting a recorder
  /// that had just been stopped. The trains are fired back to back into a
  /// single continuous capture and the recording is sliced afterwards, which
  /// pays that cost once. Sweeps stay independent: each slice is correlated
  /// and gated on its own, so [measure]'s median still discards a bad one.
  ///
  /// Each entry carries the wall-clock instant its chirp was emitted, so
  /// [ping] can stamp the result for later fusion with camera depth frames.
  Future<List<({Float64List correlation, DateTime playedAt})>> _captureSweeps({
    required int sweeps,
  }) async {
    _lastCaptureYielded = false;
    if (!_ready || _busy || sweeps < 1) return const [];

    // Claim the mic and speaker before touching either. Refusal means
    // something more urgent (a spoken obstacle callout) owns the hardware —
    // the sweep is abandoned rather than queued, because a chirp fired at an
    // unpredictable later moment is worse than no chirp.
    final lease = await _arbiter?.acquire(AudioUse.ranging);
    if (_arbiter != null && lease == null) {
      AppLogger.debug('SONAR-PING skipped :: audio in use by something louder');
      _lastCaptureYielded = true;
      return const [];
    }

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
          // This is a measurement, not a recording: the platform's voice
          // processing actively destroys it. Automatic gain control is the
          // worst offender — it rescales the input to keep speech at a
          // comfortable level, which on an Infinix X6855 swung the captured
          // amplitude 40x between identical sweeps (peak 0.009 to 0.388).
          // Clutter subtraction normalises against the breakthrough, so a
          // gain that moves between the calibration sweep and the
          // measurement invalidates the profile outright.
          //
          // Echo cancellation is equally fatal here: the direct
          // speaker-to-mic breakthrough is exactly what AEC exists to
          // remove, and it is the timing anchor everything else is measured
          // from.
          androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.unprocessed,
          ),
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      final startStreamAt = stopwatch.elapsed;
      final capturing = Completer<void>();
      subscription = stream.listen((chunk) {
        if (firstByteAt == null) {
          firstByteAt = stopwatch.elapsed;
          if (!capturing.isCompleted) capturing.complete();
        }
        recordedBytes.addAll(chunk);
      });

      // Wait for the recorder to actually deliver audio, rather than guessing
      // how long it will take.
      //
      // This used to be a fixed delay sized to the worst startup ever
      // observed, and then briefly a delay derived from a measured average.
      // Both were wrong for the same reason: on-device, `firstByteAt` swings
      // between 358ms and 652ms from run to run, because the recorder hands
      // over ~80ms chunks and where the first one lands is mostly scheduling
      // jitter. Any single number is therefore either too short (the chirp
      // fires into a dead mic and the sweep returns nothing) or needlessly
      // long — and a schedule derived from the last sample chases the noise,
      // which on device drove it from 816ms up to 1111ms instead of down.
      //
      // The first chunk arriving IS the event being waited for, so waiting on
      // it directly is exact every time and needs no calibration at all. The
      // fallback timeout only matters if the recorder never delivers, in
      // which case the sweep was going to fail regardless.
      final window = _effectiveWindow;
      await capturing.future
          .timeout(recorderWarmup, onTimeout: () {})
          .catchError((Object _) {});
      // One chunk's worth of settle, so the chirp cannot land on the boundary
      // of the very first buffer the recorder hands over.
      await Future<void>.delayed(_captureSettle);

      final trainDuration = Duration(
        microseconds: (_params.duration.inMicroseconds * pulseCount) +
            (pulseGap.inMicroseconds * (pulseCount - 1)),
      );
      // One sweep owns this much of the timeline: long enough for its train to
      // sound (late by the playback latency the window covers) and for the
      // furthest echo to return, before the next train starts.
      final sweepSpan = trainDuration + window;

      final playAts = <Duration>[];
      // Wall clock alongside the stopwatch readings: the stopwatch measures
      // this capture's internal timing, while these are what a depth frame
      // from the camera can be lined up against.
      final playedAts = <DateTime>[];
      var emitted = 0;
      for (var i = 0; i < sweeps; i++) {
        if (lease?.isCancelled ?? false) break;
        playAts.add(stopwatch.elapsed);
        playedAts.add(DateTime.now());
        await SoLoud.instance.play(_chirpSource!, volume: playbackVolume);
        emitted++;
        if (!await _waitUnlessCancelled(sweepSpan, lease)) break;
      }
      if (emitted == 0) {
        // Pre-empted before a single chirp went out, so there is no scene
        // information here at all.
        _lastCaptureYielded = true;
        return const [];
      }
      // Cut short partway through: fewer sweeps than asked for, which
      // [measure] may reject as too few to trust. That rejection is about the
      // hardware being taken, not about the room.
      if (emitted < sweeps) _lastCaptureYielded = true;

      // Cancel and stop before reading the buffer, so every chunk emitted
      // during the capture window is flushed to [recordedBytes] first.
      await subscription.cancel();
      subscription = null;
      await _recorder.stop();
      stopwatch.stop();

      final captureStart = firstByteAt;
      final expectedSamples =
          _params.sampleRate * stopwatch.elapsedMilliseconds ~/ 1000;
      AppLogger.debug(
        'SONAR-PING timing :: startStreamAt=${startStreamAt.inMilliseconds}ms '
        'firstByteAt=${captureStart?.inMilliseconds}ms '
        'playAts=${playAts.map((p) => p.inMilliseconds).join(",")}ms '
        'totalElapsed=${stopwatch.elapsedMilliseconds}ms '
        'samples=${recordedBytes.length ~/ 2}/$expectedSamples',
      );
      if (captureStart == null) return const [];

      final received = _pcm16BytesToFloat64(Uint8List.fromList(recordedBytes));
      AppLogger.debug(
        'SONAR-PING rawSignal :: ${_signalStats(received)} '
        'chirpPeak=${chirpSamples.reduce((a, b) => a.abs() > b.abs() ? a : b).toStringAsFixed(3)}',
      );

      final results = <({Float64List correlation, DateTime playedAt})>[];
      // Over what was actually emitted, not what was asked for: a pre-empted
      // capture stops early, and slicing for trains that never sounded would
      // correlate silence.
      for (var i = 0; i < playAts.length; i++) {
        // Slice on the schedule the trains were fired to. Segment i runs from
        // the instant its train was scheduled to the instant the next one was,
        // which is exactly [sweepSpan] and therefore contains that train plus
        // its echoes and nothing of its neighbour's.
        final from = _samplesSince(playAts[i] - captureStart);
        final to = i + 1 < playAts.length
            ? _samplesSince(playAts[i + 1] - captureStart)
            : received.length;
        if (from < 0 || from >= received.length || to <= from) continue;

        final segment = Float64List.sublistView(
          received,
          from,
          to > received.length ? received.length : to,
        );
        final correlation = _correlator.correlate(segment, chirpSamples);
        final anchors = _calculator.debugAnchors(
          correlation: correlation,
          pulseCount: pulseCount,
          pulseSpacingSamples: _pulseSpacingSamples,
        );
        AppLogger.debug(
          'SONAR-PING sweep$i :: samples=$from..$to '
          'spacing=$_pulseSpacingSamples at=${anchors.join(",")} '
          'peaks=${anchors.map((j) => correlation[j].abs().toStringAsFixed(1)).join(",")}',
        );

        if (i == 0) {
          // Measured once per capture, from the first sweep. Because the
          // segment starts exactly when `play()` was called, the breakthrough's
          // offset INSIDE the segment is the playback latency directly — no
          // arithmetic against the recording's own start needed.
          await _updateLatencyProfile(
            recorderStartup: captureStart,
            firstAnchor: anchors.isEmpty ? null : anchors.first,
            chirpLength: chirpSamples.length,
            usedWindow: window,
          );
        }

        results.add((correlation: correlation, playedAt: playedAts[i]));
      }
      return results;
    } catch (e, stack) {
      AppLogger.error('Sonar capture failed: $e', e, stack);
      return const [];
    } finally {
      await subscription?.cancel();
      try {
        await _recorder.stop();
      } catch (_) {}
      _busy = false;
      // Released only after the recorder is actually stopped, so a pre-empting
      // speaker does not start talking into a microphone sonar still holds.
      lease?.release();
    }
  }

  /// Waits [total], giving up early if [lease] is pre-empted. Returns false
  /// when it was cut short.
  ///
  /// Polled rather than awaited on a cancellation future because the wait it
  /// replaces is a plain [Future.delayed] that cannot be interrupted. A
  /// ~100ms granularity bounds how long an urgent callout waits behind a
  /// measurement — against a 1.6s sweep span, which is what it would otherwise
  /// have to sit through.
  static const Duration _cancelPollInterval = Duration(milliseconds: 100);

  Future<bool> _waitUnlessCancelled(Duration total, AudioLease? lease) async {
    if (lease == null) {
      await Future<void>.delayed(total);
      return true;
    }
    var remaining = total;
    while (remaining > Duration.zero) {
      if (lease.isCancelled) return false;
      final slice =
          remaining < _cancelPollInterval ? remaining : _cancelPollInterval;
      await Future<void>.delayed(slice);
      remaining -= slice;
    }
    return !lease.isCancelled;
  }

  /// Samples of audio spanned by [elapsed].
  int _samplesSince(Duration elapsed) =>
      elapsed.inMicroseconds * _params.sampleRate ~/
      Duration.microsecondsPerSecond;

  /// Derives this device's audio latencies from a capture that just happened,
  /// and adopts them if they look sane.
  ///
  /// Playback latency is read off the recording itself. The direct
  /// speaker-to-mic breakthrough is the chirp arriving over ~0m, so the sample
  /// it starts at IS the moment the speaker sounded. Since each sweep's
  /// segment is sliced to begin exactly when `play()` was called, the
  /// breakthrough's offset within that segment is the playback lag directly —
  /// no test tone or special calibration pass needed, just the sweep that was
  /// already being taken.
  ///
  /// [recorderStartup] is when the recorder's first *chunk* arrived, which is
  /// at or after the moment its first sample was captured — recorded for
  /// diagnostics only, since the capture now waits on that chunk rather than
  /// predicting it.
  Future<void> _updateLatencyProfile({
    required Duration recorderStartup,
    required int? firstAnchor,
    required int chirpLength,
    required Duration usedWindow,
  }) async {
    if (firstAnchor == null) return;

    // Correlation index -> offset into the segment: a match starting at
    // sample d peaks at d + template.length - 1 (see CrossCorrelationService).
    final breakthroughSample = firstAnchor - (chirpLength - 1);
    if (breakthroughSample < 0) return;

    final observed = SonarLatencyProfile(
      recorderStartup: recorderStartup,
      playbackLatency: Duration(
        microseconds: breakthroughSample *
            Duration.microsecondsPerSecond ~/
            _params.sampleRate,
      ),
    );
    if (!observed.isPlausible) {
      AppLogger.debug('SONAR-LATENCY rejected implausible :: $observed');
      return;
    }

    // Keep the WORST playback latency seen, not the latest.
    //
    // On device this measurement varies widely between otherwise identical
    // sweeps (400ms and 569ms on consecutive pings). Adopting the latest
    // sample makes the window track that noise, and a window sized from a
    // low sample will cut off the chirp on the next sweep that runs long —
    // which costs the whole reading. A running maximum converges upward to a
    // window that covers every sweep and then stops moving.
    final merged = _latency == null
        ? observed
        : SonarLatencyProfile(
            recorderStartup: observed.recorderStartup,
            playbackLatency:
                observed.playbackLatency > _latency!.playbackLatency
                    ? observed.playbackLatency
                    : _latency!.playbackLatency,
          );

    final changed = merged.playbackLatency != _latency?.playbackLatency;
    _latency = merged;
    if (!changed) return;

    AppLogger.info(
      'SONAR-LATENCY measured :: observed $observed — window '
      '${usedWindow.inMilliseconds}ms -> '
      '${merged.captureWindow(maxEchoDelay: _maxEchoDelay).inMilliseconds}ms',
    );
    await _persistLatencyProfile(merged);
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

}
